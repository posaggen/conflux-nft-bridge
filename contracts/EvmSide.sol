// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./Bridge.sol";
import "./utils/Initializable.sol";

import "./interfaces/IEvmSide.sol";
import "./interfaces/IEvmRegistry.sol";

contract EvmSide is IEvmSide, Initializable, Bridge {
    using EnumerableMap for EnumerableMap.UintToUintMap;
    using Math for uint256;

    // privileged cfx side to mint/transfer/burn tokens on eSpace.
    address public cfxSide;

    // NFT registry for all token pairs
    IEvmRegistry public registry;

    // locked NFTs for cfx account on core space
    // evm token => cfx account => token id => amount
    // amount is always 1 in case of ERC721
    mapping(address => mapping(address => EnumerableMap.UintToUintMap)) private _lockedTokens;

    /**
     * @dev Connect to cfx side, which is a mapped address of base32 address.
     */
    function setCfxSide() public {
        require(cfxSide == address(0), "EvmSide: cfx side set already");
        cfxSide = msg.sender;
    }

    modifier onlyCfxSide() {
        require(msg.sender == cfxSide, "EvmSide: only cfx side permitted");
        _;
    }

    function initialize(IEvmRegistry registry_) public onlyInitializeOnce {
        registry = registry_;
    }

    function lockedTokens(
        address evmToken,
        address cfxAccount,
        uint256 offset,
        uint256 limit
    ) public view returns (uint256 total, uint256[] memory tokenIds, uint256[] memory amounts) {
        EnumerableMap.UintToUintMap storage id2amounts = _lockedTokens[evmToken][cfxAccount];

        total = id2amounts.length();
        if (offset >= total) {
            return (total, new uint256[](0), new uint256[](0));
        }

        uint256 endExclusive = total.min(offset + limit);
        tokenIds = new uint256[](endExclusive - offset);
        amounts = new uint256[](endExclusive - offset);

        for (uint256 i = offset; i < endExclusive; i++) {
            (tokenIds[i - offset], amounts[i - offset]) = id2amounts.at(i);
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    // Origin tokens on core space, and pegged tokens on eSpace.
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Mint tokens by cfx side, when user cross NFT from core space (origin) to eSpace (pegged).
     */
    function mint(
        address evmToken,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        string[] memory uris
    ) public onlyCfxSide {
        PeggedNFTUtil.batchMint(evmToken, to, ids, amounts, uris);
    }

    /**
     * @dev Burn locked tokens by cfx side, when user withdraw NFT from eSpace (pegged) to core space (origin).
     */
    function burn(
        address evmToken,
        address cfxAccount,
        uint256[] memory ids,
        uint256[] memory amounts
    ) public onlyCfxSide {
        _unlock(evmToken, cfxAccount, ids, amounts);

        PeggedNFTUtil.batchBurn(evmToken, ids, amounts);
    }

    function _unlock(address evmToken, address cfxAccount, uint256[] memory ids, uint256[] memory amounts) private {
        for (uint256 i = 0; i < ids.length; i++) {
            (, uint256 locked) = _lockedTokens[evmToken][cfxAccount].tryGet(ids[i]);
            require(locked >= amounts[i], "EvmSide: insufficent locked tokens");

            if (locked == amounts[i]) {
                _lockedTokens[evmToken][cfxAccount].remove(ids[i]);
            } else {
                _lockedTokens[evmToken][cfxAccount].set(ids[i], locked - amounts[i]);
            }
        }
    }

    /**
     * @dev Lock tokens for `to` cfx address to operate on core space in advance.
     */
    function _onNFTReceived(
        address nft,
        address operator,
        address from,
        uint256[] memory ids,
        uint256[] memory amounts,
        address to
    ) internal override {
        registry.validateToken(nft);

        for (uint256 i = 0; i < ids.length; i++) {
            (, uint256 locked) = _lockedTokens[nft][to].tryGet(ids[i]);
            _lockedTokens[nft][to].set(ids[i], locked + amounts[i]);
        }

        emit TokenLocked(nft, operator, from, to, ids, amounts);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    // Origin tokens on eSpace, and pegged tokens on core space.
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Unlock tokens by cfx side, when user cross NFT from eSpace to core space (pegged).
     */
    function unlock(
        address evmToken,
        address cfxAccount,
        uint256[] memory ids,
        uint256[] memory amounts
    ) public onlyCfxSide {
        _unlock(evmToken, cfxAccount, ids, amounts);
    }

    /**
     * @dev Transfer tokens by cfx side, when user withdraw NFT from core space (pegged) back to eSpace (origin).
     */
    function transfer(address evmToken, address to, uint256[] memory ids, uint256[] memory amounts) public onlyCfxSide {
        PeggedNFTUtil.batchTransfer(evmToken, to, ids, amounts);
    }
}
