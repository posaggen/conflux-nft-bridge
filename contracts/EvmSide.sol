// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./Bridge.sol";
import "./PeggedTokenDeployer.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract EvmSide is Initializable, Bridge, PeggedTokenDeployer {
    using EnumerableMap for EnumerableMap.UintToUintMap;
    using EnumerableSet for EnumerableSet.AddressSet;
    using Math for uint256;

    // privileged cfx side to deploy or register/unregister token pairs.
    address public cfxRegistry;
    // privileged cfx side to mint/transfer/burn tokens on eSpace.
    address public cfxSide;

    // locked NFTs for cfx account on core space
    // evm token => cfx account => token id => amount
    // amount is always 1 in case of ERC721
    mapping(address => mapping(address => EnumerableMap.UintToUintMap)) private _lockedTokens;

    // all evm tokens that have been pegged on core space
    EnumerableSet.AddressSet private _originTokens;

    // token => cfx operator, all approved cfx operators by NFT admin to register/unregister token pair.
    mapping(address => address) public approvedOperators;

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
        Initializable._initialize();
        PeggedTokenDeployer._initialize(beacon721, beacon1155);
    }

    /**
     * @dev Connect to cfx side, which is a mapped address of base32 address.
     */
    function setCfxRegistry() public {
        require(cfxRegistry == address(0), "cfx registry set already");
        cfxRegistry = msg.sender;
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

    modifier onlyCfxRegistry() {
        require(msg.sender == cfxRegistry, "only cfx registry permitted");
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
    function deploy(uint256 nftType, string memory name, string memory symbol) public onlyCfxRegistry returns (address) {
        return _deployPeggedToken(nftType, name, symbol, bytes20(0));
    }

    /**
     * @dev Check if the specified `evmToken` is valid to be registered as a pegged token on eSpace.
     */
    function registerEvm(address evmToken) public onlyCfxRegistry onlyPeggable(evmToken) {
        require(!_originTokens.contains(evmToken), "cycle pegged");
        require(_peggedTokens.add(evmToken), "registered already");
    }

    /**
     * @dev Remove token pair if `evmToken` is empty.
     */
    function unregisterEvm(address evmToken) public onlyCfxRegistry {
        require(PeggedNFTUtil.totalSupply(evmToken) == 0, "evm token has tokens");
        require(_peggedTokens.remove(evmToken), "already unregistered");
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
        address nft,
        address operator,
        address from,
        uint256[] memory ids,
        uint256[] memory amounts,
        address to
    ) internal override {
        require(_peggedTokens.contains(nft) || _originTokens.contains(nft), "invalid token received");

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
     * @dev Check if the specified `evmToken` is valid to create pegged NFT contract on core space.
     */
    function preDeployCfx(address evmToken)
        public
        onlyCfxRegistry onlyPeggable(evmToken)
        returns (uint256 nftType, string memory name, string memory symbol)
    {
        require(_originTokens.add(evmToken), "deployed already");

        return (
            PeggedNFTUtil.nftType(evmToken),
            IERC721Metadata(evmToken).name(),
            IERC721Metadata(evmToken).symbol()
        );
    }

    /**
     * @dev Owner or admin of `evmToken` approves the `cfxOperator` to register/unregister token pair on core space.
     */
    function approve(address evmToken, address cfxOperator) public {
        require(PeggedNFTUtil.isOwnerOrAdmin(evmToken, msg.sender), "owner or admin required");
        approvedOperators[evmToken] = cfxOperator;
    }

    /**
     * @dev Check if the specified `evmToken` is valid to be registered as origin token on eSpace.
     */
    function registerCfx(address evmToken, address cfxOperator) public onlyCfxRegistry onlyPeggable(evmToken) {
        require(approvedOperators[evmToken] == cfxOperator, "cfx operator not approved");

        // pegged token may already been deployed on core spce
        _originTokens.add(evmToken);
    }

    /**
     * @dev Remove token pair by approved `cfxOperator` if `evmToken` is empty.
     */
    function unregisterCfx(address evmToken, address cfxOperator, bool removed) public onlyCfxRegistry {
        require(approvedOperators[evmToken] == cfxOperator, "cfx operator not approved");

        // remove if both deployed and registered pegged token removed on core space
        if (removed) {
            _originTokens.remove(evmToken);
        }
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
