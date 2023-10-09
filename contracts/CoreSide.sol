// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Bridge.sol";
import "./utils/Initializable.sol";
import "./utils/PeggedNFTUtil.sol";
import "./utils/UpgradeableInternalContractsHandler.sol";

import "./interfaces/ICoreRegistry.sol";
import "./interfaces/ICoreSide.sol";
import "./interfaces/IEvmSide.sol";
import "./interfaces/ICoreToEvmCallback.sol";
import "./interfaces/IEvmToCoreCallback.sol";

contract CoreSide is ICoreSide, Initializable, Bridge, UpgradeableInternalContractsHandler {
    // interact via cross space internal contract
    bytes20 public evmSide;

    // NFT registry for all token pairs
    ICoreRegistry public registry;

    function initialize(ICoreRegistry registry_, bytes20 evmSide_) public onlyInitializeOnce {
        registry = registry_;
        evmSide = evmSide_;

        // connect to evm side
        InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide, abi.encodeWithSelector(IEvmSide.setCfxSide.selector));

        _setupInternalContracts();
    }

    // NFT receiver callback handler.
    function _onNFTReceived(
        address nft,
        address operator, // cfx operator
        address from, // cfx from
        uint256[] memory ids,
        uint256[] memory amounts,
        address to // evm to
    ) internal override {
        // cross origin token from core space to the registered pegged token on eSpace with priority
        bytes20 registered = registry.registeredCore2EvmTokens(nft);
        if (registered != bytes20(0)) {
            _crossToEvm(nft, operator, from, ids, amounts, registered, to);
            return;
        }

        // cross origin token from core space to the deployed pegged token on eSpace
        bytes20 deployed = registry.core2EvmTokens(nft);
        if (deployed != bytes20(0)) {
            _crossToEvm(nft, operator, from, ids, amounts, deployed, to);
            return;
        }

        // withdraw pegged token on core space to eSpace
        require(registry.peggedCore2EvmTokens(nft) != bytes20(0), "CoreSide: invalid token received");
        _withdrawToEvm(nft, operator, from, ids, amounts, to);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    // Origin tokens on core space, and pegged tokens on eSpace.
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Cross origin token from core space to eSpace as pegged.
     */
    function _crossToEvm(
        address cfxToken,
        address operator,
        address from,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes20 evmToken,
        address evmAccount
    ) private {
        // mint on evm side
        address callback = registry.core2EvmCallbacks(cfxToken);
        if (callback == address(0)) {
            // no callback, use default cross space function
            string[] memory uris = new string[](ids.length);
            for (uint256 i = 0; i < ids.length; i++) {
                uris[i] = PeggedNFTUtil.tokenURI(cfxToken, ids[i]);
            }

            // mint on eSpace via cross space internal contract
            InternalContracts.CROSS_SPACE_CALL.callEVM(
                evmSide,
                abi.encodeWithSelector(IEvmSide.mint.selector, address(evmToken), evmAccount, ids, amounts, uris)
            );
        } else {
            // cross space through callback
            // NOTE: callback is developed by NFT contract owner, its correctness is not guaranteed.
            try
                ICoreToEvmCallback(callback).onCoreToEvm(cfxToken, operator, from, ids, amounts, evmToken, evmAccount)
            returns (bytes4 retval) {
                require(retval == ICoreToEvmCallback.onCoreToEvm.selector, "CoreSide: invalid callback return value");
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("CoreSide: non CoreToEvmCallback implementer");
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }

        emit CrossToEvm(cfxToken, evmToken, operator, from, bytes20(evmAccount), ids, amounts);
    }

    /**
     * @dev Withdraw locked NFT from eSpace to core space.
     */
    function withdrawFromEvm(
        bytes20 evmToken,
        uint256[] memory ids,
        uint256[] memory amounts,
        address recipient
    ) public {
        require(ids.length == amounts.length, "CoreSide: ids and amounts length mismatch");

        address cfxToken = registry.peggedEvm2CoreTokens(evmToken);
        require(cfxToken != address(0), "CoreSide: invalid pegged evm token");

        // burn on eSpace via cross space internal contract
        InternalContracts.CROSS_SPACE_CALL.callEVM(
            evmSide,
            abi.encodeWithSelector(IEvmSide.burn.selector, address(evmToken), msg.sender, ids, amounts)
        );
        // transfer on core side
        PeggedNFTUtil.batchTransfer(cfxToken, recipient, ids, amounts);

        emit WithdrawFromEvm(cfxToken, evmToken, msg.sender, recipient, ids, amounts);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    // Origin tokens on eSpace, and pegged tokens on core space.
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Cross locked NFT from eSpace to core space as pegged.
     */
    function crossFromEvm(address cfxToken, uint256[] memory ids, uint256[] memory amounts, address recipient) public {
        require(ids.length == amounts.length, "CoreSide: ids and amounts length mismatch");

        bytes20 evmToken = registry.peggedCore2EvmTokens(cfxToken);
        require(evmToken != bytes20(0), "CoreSide: cfx token unsupported");
        // unlock on evm side
        InternalContracts.CROSS_SPACE_CALL.callEVM(
            evmSide,
            abi.encodeWithSelector(IEvmSide.unlock.selector, address(evmToken), msg.sender, ids, amounts)
        );
        // mint on core side
        address callback = registry.evm2CoreCallbacks(cfxToken);
        if (callback == address(0)) {
            // no callback, use default cross space function
            // pegged NFT on core space do not require uri, instead, read from eSpace directly.
            PeggedNFTUtil.batchMint(cfxToken, recipient, ids, amounts, new string[](ids.length));
        } else {
            // cross space through callback
            // NOTE: callback is developed by NFT contract owner, its correctness is not guaranteed.
            try IEvmToCoreCallback(callback).onEvmToCore(evmToken, cfxToken, ids, amounts, recipient) returns (
                bytes4 retval
            ) {
                require(retval == IEvmToCoreCallback.onEvmToCore.selector, "CoreSide: invalid callback return value");
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("CoreSide: non EvmToCoreCallback implementer");
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }

        emit CrossFromEvm(cfxToken, evmToken, msg.sender, recipient, ids, amounts);
    }

    /**
     * @dev Withdraw pegged token on core space back to eSpace.
     */
    function _withdrawToEvm(
        address cfxToken,
        address operator,
        address from,
        uint256[] memory ids,
        uint256[] memory amounts,
        address evmAccount
    ) private {
        bytes20 evmToken = registry.peggedCore2EvmTokens(cfxToken);
        require(evmToken != bytes20(0), "CoreSide: cfx token unsupported");
        // burn on core side
        PeggedNFTUtil.batchBurn(cfxToken, ids, amounts);
        // transfer on evm side
        InternalContracts.CROSS_SPACE_CALL.callEVM(
            evmSide,
            abi.encodeWithSelector(IEvmSide.transfer.selector, address(evmToken), evmAccount, ids, amounts)
        );

        emit WithdrawToEvm(cfxToken, evmToken, operator, from, bytes20(evmAccount), ids, amounts);
    }
}
