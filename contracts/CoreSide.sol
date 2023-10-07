// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Bridge.sol";
import "./EvmSide.sol";
import "./Registry.sol";
import "./utils/Initializable.sol";
import "./utils/PeggedNFTUtil.sol";
import "@confluxfans/contracts/InternalContracts/InternalContractsHandler.sol";
import "@confluxfans/contracts/InternalContracts/InternalContractsLib.sol";

contract CoreSide is Initializable, Bridge, InternalContractsHandler {
    // interact via cross space internal contract
    bytes20 public evmSide;

    // NFT registry for all token pairs
    Registry public registry;

    // emitted when cross NFT from core space (origin) to eSpace (pegged)
    event CrossToEvm(
        address indexed cfxToken,
        bytes20 evmToken,
        address cfxOperator,
        address indexed cfxFrom,
        bytes20 indexed evmTo,
        uint256[] ids,
        uint256[] amounts
    );

    // emitted when withdraw NFT from eSpace (pegged) to core space (origin)
    event WithdrawFromEvm(
        address indexed cfxToken,
        bytes20 evmToken,
        address indexed cfxAccount,
        address indexed cfxRecipient,
        uint256[] ids,
        uint256[] amounts
    );

    // emitted when cross NFT from eSpace (origin) to core space (pegged)
    event CrossFromEvm(
        address indexed cfxToken,
        bytes20 evmToken,
        address indexed cfxAccount,
        address indexed cfxRecipient,
        uint256[] ids,
        uint256[] amounts
    );

    // emitted when withdraw NFT from core space (pegged) to eSpace (origin)
    event WithdrawToEvm(
        address indexed cfxToken,
        bytes20 evmToken,
        address cfxOperator,
        address indexed cfxFrom,
        bytes20 indexed evmTo,
        uint256[] ids,
        uint256[] amounts
    );

    function initialize(Registry registry_, bytes20 evmSide_) public onlyInitializeOnce {
        registry = registry_;
        evmSide = evmSide_;

        // connect to evm side
        InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide, abi.encodeWithSelector(EvmSide.setCfxSide.selector));
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
        require(registry.peggedCore2EvmTokens(nft) != bytes20(0), "invalid token received");
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
        string[] memory uris = new string[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            uris[i] = PeggedNFTUtil.tokenURI(cfxToken, ids[i]);
        }

        // mint on eSpace via cross space internal contract
        InternalContracts.CROSS_SPACE_CALL.callEVM(
            evmSide,
            abi.encodeWithSelector(EvmSide.mint.selector, address(evmToken), evmAccount, ids, amounts, uris)
        );

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
        require(ids.length == amounts.length, "ids and amounts length mismatch");

        address cfxToken = registry.peggedEvm2CoreTokens(evmToken);
        require(cfxToken != address(0), "invalid pegged evm token");

        // burn on eSpace via cross space internal contract
        InternalContracts.CROSS_SPACE_CALL.callEVM(
            evmSide,
            abi.encodeWithSelector(EvmSide.burn.selector, address(evmToken), msg.sender, ids, amounts)
        );

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
        require(ids.length == amounts.length, "ids and amounts length mismatch");

        bytes20 evmToken = registry.peggedCore2EvmTokens(cfxToken);
        require(evmToken != bytes20(0), "cfx token unsupported");

        InternalContracts.CROSS_SPACE_CALL.callEVM(
            evmSide,
            abi.encodeWithSelector(EvmSide.unlock.selector, address(evmToken), msg.sender, ids, amounts)
        );

        // pegged NFT on core space do not require uri, instead, read from eSpace directly.
        PeggedNFTUtil.batchMint(cfxToken, recipient, ids, amounts, new string[](ids.length));

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
        require(evmToken != bytes20(0), "cfx token unsupported");

        PeggedNFTUtil.batchBurn(cfxToken, ids, amounts);

        InternalContracts.CROSS_SPACE_CALL.callEVM(
            evmSide,
            abi.encodeWithSelector(EvmSide.transfer.selector, address(evmToken), evmAccount, ids, amounts)
        );

        emit WithdrawToEvm(cfxToken, evmToken, operator, from, bytes20(evmAccount), ids, amounts);
    }
}
