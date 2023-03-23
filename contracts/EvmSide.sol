// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./PeggedERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract EvmSide is Initializable, IERC721Receiver, Ownable {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    // privileged cfx side to mint/burn tokens on eSpace
    address public cfxSide;

    // NFT beacon (ERC721)
    address public beacon;

    // all evm tokens for enumeration
    EnumerableSet.AddressSet private _evmTokens;

    // locked NFTs that allow core space to withdraw
    // evm token => cfx account => token ids
    mapping(address => mapping(address => EnumerableSet.UintSet)) private _lockedTokens;

    // emitted when user lock tokens for core space users to withdraw in another transaction
    event LockedMappedToken(
        address evmToken,
        address indexed evmOperator,
        address indexed evmFrom,
        address indexed cfxTo,
        uint256 tokenId
    );

    function initialize(address beacon_) public {
        Initializable._initialize();

        beacon = beacon_;

        _transferOwnership(msg.sender);
    }

    /**
     * @dev Connect to cfx side, which is a mapped address.
     */
    function setCfxSide() public {
        require(cfxSide == address(0), "cfx side set already");
        cfxSide = msg.sender;
    }

    modifier onlyCfxSide() {
        require(msg.sender == cfxSide, "only cfx side permitted");
        _;
    }

    /**
     * @dev Create a NFT contract with beacon proxy on eSpace. This is called by core space
     * via cross space internal contract.
     */
    function deploy(string memory name, string memory symbol) public onlyCfxSide returns (address evmToken) {
        evmToken = address(new BeaconProxy(beacon, ""));
        PeggedERC721(evmToken).initialize(name, symbol, owner());
        require(_evmTokens.add(evmToken), "duplicated evm token created");
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
        address evmToken = msg.sender;
        require(_evmTokens.contains(evmToken), "evm token unsupported");

        // parse cfx account from data
        require(data.length == 20, "data should be cfx address");
        address cfxAccount = abi.decode(data, (address));
        require(cfxAccount != address(0), "cfx address not provided");

        // lock token to withdraw from cfx side
        require(_lockedTokens[evmToken][cfxAccount].add(tokenId), "token already locked");

        emit LockedMappedToken(evmToken, operator, from, cfxAccount, tokenId);

        return IERC721Receiver.onERC721Received.selector;
    }

}