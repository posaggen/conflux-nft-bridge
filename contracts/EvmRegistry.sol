// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PeggedTokenDeployer.sol";
import "./utils/Initializable.sol";
import "./interfaces/IEvmRegistry.sol";

contract EvmRegistry is IEvmRegistry, Initializable, PeggedTokenDeployer {
    using EnumerableSet for EnumerableSet.AddressSet;

    // cfx tokens pegged on evm space => pegged token deployment info
    mapping(address => Deployment) public deployments;

    // privileged cfx registry to deploy/register tokens on eSpace.
    address public cfxRegistry;

    // all evm tokens that have been pegged on core space
    EnumerableSet.AddressSet private _originTokens;

    // token => cfx operator, all approved cfx operators by NFT admin to register/unregister token pair.
    mapping(address => address) public approvedOperators;

    /**
     * @dev Connect to cfx side, which is a mapped address of base32 address.
     */
    function setCfxRegistry() public {
        require(cfxRegistry == address(0), "EvmSide: cfx registry set already");
        cfxRegistry = msg.sender;
    }

    modifier onlyCfxRegistry() {
        require(msg.sender == cfxRegistry, "EvmSide: only cfx registry permitted");
        _;
    }

    function initialize(address beacon721, address beacon1155) public onlyInitializeOnce {
        PeggedTokenDeployer._initialize(beacon721, beacon1155);
    }

    /*=== view functions ===*/

    function getDeployed(address nft) external view returns (address deployed) {
        deployed = deployments[nft].deployed;
        require(_peggedTokens.contains(deployed), "EvmRegistry: unregistered token");
    }

    function validateToken(address nft) external view {
        require(_peggedTokens.contains(nft) || _originTokens.contains(nft), "EvmRegistry: invalid token received");
    }

    /**
     * @dev Get origin tokens on eSpace in paging view.
     */
    function evmTokens(uint256 offset, uint256 limit) public view returns (uint256 total, address[] memory tokens) {
        return _pagedTokens(_originTokens, offset, limit);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    // Origin tokens on core space, and pegged tokens on eSpace.
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////

    function registerDeploy(
        address cfxToken,
        uint256 nftType,
        string memory name,
        string memory symbol
    ) public onlyCfxRegistry {
        Deployment storage deployment = deployments[cfxToken];
        if (deployment.deployed == address(0)) {
            deployment.name = name;
            deployment.symbol = symbol;
            deployment.nftType = nftType;
        }
    }

    /**
     * @dev Create a NFT contract with beacon proxy on eSpace. This is called by core space
     * via cross space internal contract.
     */
    function deploy(address cfxToken) public {
        Deployment storage deployment = deployments[cfxToken];
        require(deployment.deployed == address(0), "EvmRegistry: deployed already");
        require(deployment.nftType > 0, "EvmRegistry: unregistered deploy");
        deployment.deployed = _deployPeggedToken(deployment.nftType, deployment.name, deployment.symbol, bytes20(0));
    }

    /**
     * @dev Check if the specified `evmToken` is valid to be registered as a pegged token on eSpace.
     */
    function registerEvm(address evmToken) public onlyCfxRegistry onlyPeggable(evmToken) {
        require(!_originTokens.contains(evmToken), "EvmSide: cycle pegged");
        require(_peggedTokens.add(evmToken), "EvmSide: registered already");
    }

    /**
     * @dev Remove token pair if `evmToken` is empty.
     */
    function unregisterEvm(address evmToken) public onlyCfxRegistry {
        require(_peggedTokens.remove(evmToken), "EvmSide: already unregistered");
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    // Origin tokens on eSpace, and pegged tokens on core space.
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Check if the specified `evmToken` is valid to create pegged NFT contract on core space.
     */
    function preDeployCfx(
        address evmToken
    )
        public
        onlyCfxRegistry
        onlyPeggable(evmToken)
        returns (uint256 nftType, string memory name, string memory symbol)
    {
        require(_originTokens.add(evmToken), "EvmSide: deployed already");

        return (PeggedNFTUtil.nftType(evmToken), IERC721Metadata(evmToken).name(), IERC721Metadata(evmToken).symbol());
    }

    /**
     * @dev Owner or admin of `evmToken` approves the `cfxOperator` to register/unregister token pair on core space.
     */
    function approve(address evmToken, address cfxOperator) public {
        require(PeggedNFTUtil.isOwnerOrAdmin(evmToken, msg.sender), "EvmSide: owner or admin required");
        approvedOperators[evmToken] = cfxOperator;
    }

    /**
     * @dev Add token pair by core registry.
     */
    function registerCfx(address evmToken) public onlyCfxRegistry onlyPeggable(evmToken) {
        // pegged token may already been deployed on core spce
        _originTokens.add(evmToken);
    }

    /**
     * @dev Remove token pair by core registry.
     */
    function unregisterCfx(address evmToken) public onlyCfxRegistry {
        // remove if both deployed and registered pegged token removed on core space
        _originTokens.remove(evmToken);
    }
}
