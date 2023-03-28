// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Bridge.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract EvmSide is Bridge {
    using EnumerableMap for EnumerableMap.UintToUintMap;
    using Math for uint256;

    // privileged cfx side to mint/burn tokens on eSpace
    address public cfxSide;

    // locked NFTs for cfx account on core space
    // evm token => cfx account => token id => amount
    // amount is always 1 in case of ERC721
    mapping(address => mapping(address => EnumerableMap.UintToUintMap)) private _lockedTokens;

    // emitted when user lock tokens for core space users to operate in advance
    event TokenLocked(
        address indexed evmToken,
        address evmOperator,
        address indexed evmFrom,
        address indexed cfxTo,
        uint256[] ids,
        uint256[] values
    );

    function initialize(address beacon721, address beacon1155) public {
        Bridge._initialize(beacon721, beacon1155);
    }

    /**
     * @dev Connect to cfx side, which is a mapped address of base32 address.
     */
    function setCfxSide() public {
        require(cfxSide == address(0), "cfx side set already");
        cfxSide = msg.sender;
    }

    modifier onlyCfxSide() {
        require(msg.sender == cfxSide, "only cfx side permitted");
        _;
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
     * @dev Create a NFT contract with beacon proxy on eSpace. This is called by core space
     * via cross space internal contract.
     */
    function deploy(uint256 nftType, string memory name, string memory symbol) public onlyCfxSide returns (address) {
        return _deployPeggedToken(nftType, name, symbol, bytes20(0));
    }

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
            require(locked >= amounts[i], "insufficent locked tokens");

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
        address operator,
        address from,
        uint256[] memory ids,
        uint256[] memory amounts,
        address to
    ) internal override {
        for (uint256 i = 0; i < ids.length; i++) {
            (, uint256 locked) = _lockedTokens[msg.sender][to].tryGet(ids[i]);
            _lockedTokens[msg.sender][to].set(ids[i], locked + amounts[i]);
        }

        emit TokenLocked(msg.sender, operator, from, to, ids, amounts);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    // Origin tokens on eSpace, and pegged tokens on core space.
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Check if the specified `evmToken` is valid to create pegged NFT contract on core space.
     */
    function preDeployCfx(address evmToken)
        public
        view
        onlyCfxSide onlyPeggable(evmToken)
        returns (uint256 nftType, string memory name, string memory symbol)
    {
        return (
            PeggedNFTUtil.nftType(evmToken),
            IERC721Metadata(evmToken).name(),
            IERC721Metadata(evmToken).symbol()
        );
    }

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
    function transfer(
        address evmToken,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts
    ) public onlyCfxSide {
        PeggedNFTUtil.batchTransfer(evmToken, to, ids, amounts);
    }

}
