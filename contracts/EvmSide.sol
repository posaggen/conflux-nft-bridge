// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./PeggedTokenDeployer.sol";
import "./PeggedERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract EvmSide is Initializable, PeggedTokenDeployer, IERC721Receiver {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

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

    function initialize(address beacon_) public {
        Initializable._initialize();
        PeggedTokenDeployer._initialize(beacon_);
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

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    // Origin tokens on core space, and pegged tokens on eSpace.
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Create a NFT contract with beacon proxy on eSpace. This is called by core space
     * via cross space internal contract.
     */
    function deploy(string memory name, string memory symbol) public onlyCfxSide returns (address) {
        return _deployPeggedToken(name, symbol, bytes20(0));
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

    /**
     * @dev Implements the IERC721Receiver interface for users to lock tokens via IERC721.safeTransferFrom,
     * so that user could withdraw token from eSpace (pegged) to core space (origin) in advance.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public override returns (bytes4) {
        // parse cfx account from data
        require(data.length == 20, "data should be cfx address");
        address cfxAccount = abi.decode(data, (address));
        require(cfxAccount != address(0), "cfx address not provided");

        // lock token to withdraw from cfx side
        address evmToken = msg.sender;
        require(_lockedTokens[evmToken][cfxAccount].add(tokenId), "token already locked");

        emit TokenLocked(evmToken, operator, from, cfxAccount, tokenId);

        return IERC721Receiver.onERC721Received.selector;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    // Origin tokens on eSpace, and pegged tokens on core space.
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Check if the specified `evmToken` is valid to create pegged NFT contract on core space.
     */
    function preDeployCfx(address evmToken) public view onlyCfxSide onlyPeggable(evmToken) returns (string memory name, string memory symbol) {
        return (IERC721Metadata(evmToken).name(), IERC721Metadata(evmToken).symbol());
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
