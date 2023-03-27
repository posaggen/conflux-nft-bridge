// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Bridge.sol";
import "./PeggedERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract EvmSide is Bridge {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using Math for uint256;

    // privileged cfx side to mint/burn tokens on eSpace
    address public cfxSide;

    // locked NFTs for cfx account on core space
    // evm token => cfx account => token ids
    mapping(address => mapping(address => EnumerableSet.UintSet)) private _lockedTokens;

    // emitted when user lock tokens for core space users to operate in advance
    event TokenLocked(
        address indexed evmToken,
        address evmOperator,
        address indexed evmFrom,
        address indexed cfxTo,
        uint256 tokenId
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
    ) public view returns (uint256 total, uint256[] memory tokenIds) {
        EnumerableSet.UintSet storage all = _lockedTokens[evmToken][cfxAccount];

        total = all.length();
        if (offset >= total) {
            return (total, new uint256[](0));
        }

        uint256 endExclusive = total.min(offset + limit);
        tokenIds = new uint256[](endExclusive - offset);

        for (uint256 i = offset; i < endExclusive; i++) {
            tokenIds[i - offset] = all.at(i);
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
    function deploy(bool erc721, string memory name, string memory symbol) public onlyCfxSide returns (address) {
        return _deployPeggedToken(erc721, name, symbol, bytes20(0));
    }

    /**
     * @dev Mint a token with optional `tokenURI` by cfx side, when user cross NFT from core space (origin)
     * to eSpace (pegged).
     */
    function mint(address evmToken, address to, uint256 tokenId, string memory tokenURI) public onlyCfxSide {
        PeggedERC721(evmToken).mint(to, tokenId, tokenURI);
    }

    /**
     * @dev Burn a locked token for specified `cfxAccount` by cfx side, when user withdraw NFT from
     * eSpace (pegged) to core space (origin).
     */
    function burn(address evmToken, address cfxAccount, uint256 tokenId) public onlyCfxSide {
        require(_lockedTokens[evmToken][cfxAccount].remove(tokenId), "token not locked");
        PeggedERC721(evmToken).burn(tokenId);
    }

    function _onERC721Received(
        address operator,   // evm operator
        address from,       // evm from
        uint256 tokenId,
        address to          // cfx to
    ) internal override {
        // lock token to withdraw from cfx side
        require(_lockedTokens[msg.sender][to].add(tokenId), "token already locked");
        emit TokenLocked(msg.sender, operator, from, to, tokenId);
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
        returns (bool erc721, string memory name, string memory symbol)
    {
        return (
            IERC165(evmToken).supportsInterface(type(IERC721).interfaceId),
            IERC721Metadata(evmToken).name(),
            IERC721Metadata(evmToken).symbol()
        );
    }

    /**
     * @dev Unlock specified token by cfx side, when user cross NFT from eSpace to core space (pegged). 
     */
    function unlock(address evmToken, address cfxAccount, uint256 tokenId) public onlyCfxSide {
        require(_lockedTokens[evmToken][cfxAccount].remove(tokenId), "token not locked");
    }

    /**
     * @dev Transfer token to specified user by cfx side, when user withdraw NFT from core space (pegged)
     * back to eSpace (origin).
     */
    function transfer(address evmToken, address to, uint256 tokenId) public onlyCfxSide {
        IERC721(evmToken).safeTransferFrom(address(this), to, tokenId);
    }

}
