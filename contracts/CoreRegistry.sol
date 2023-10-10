// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "@confluxfans/contracts/InternalContracts/InternalContractsHandler.sol";

import "./PeggedTokenDeployer.sol";
import "./utils/Initializable.sol";

import "./interfaces/IEvmRegistry.sol";
import "./interfaces/ICoreRegistry.sol";

/**
 * @dev NFT registry that holds deployed or registered token pairs.
 *
 * Generally, this contract will not use sponsorship for NFT admins.
 */
contract CoreRegistry is ICoreRegistry, Initializable, PeggedTokenDeployer, InternalContractsHandler {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Address for address;

    // interact via cross space internal contract
    bytes20 public evmRegistry;

    // indexes for token pair that pegged on eSpace
    // cfx token => evm token (pegged token deployed on eSpace)
    mapping(address => bytes20) public core2EvmTokens;
    // registered token pair by admin other than deployed with standard template
    mapping(address => bytes20) public registeredCore2EvmTokens;
    // evm token => cfx token (pegged token deployed on eSpace)
    mapping(bytes20 => address) public peggedEvm2CoreTokens;
    // core to evm crosschain callback handlers
    mapping(address => address) public core2EvmCallbacks;
    // all cfx tokens that pegged on eSpace
    EnumerableSet.AddressSet private _allCfxTokens;

    // indexes for token pair that pegged on core space
    // evm token => cfx token (pegged on core space)
    mapping(bytes20 => address) public evm2CoreTokens;
    // registered toke pair by admin other than deployed with standard template
    mapping(bytes20 => address) public registeredEvm2CoreTokens;
    // cfx token => evm token (pegged on core space)
    mapping(address => bytes20) public peggedCore2EvmTokens;
    // evm to core crosschain callback handlers
    mapping(address => address) public evm2CoreCallbacks;

    function initialize(bytes20 evmRegistry_, address beacon721, address beacon1155) public onlyInitializeOnce {
        evmRegistry = evmRegistry_;

        // initalize peggedTokenDeployer
        PeggedTokenDeployer._initialize(beacon721, beacon1155);

        // connect to evm side
        InternalContracts.CROSS_SPACE_CALL.callEVM(
            evmRegistry,
            abi.encodeWithSelector(IEvmRegistry.setCfxRegistry.selector)
        );
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    // Origin tokens on core space, and pegged tokens on eSpace.
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////

    function _isCfxOwnerOrAdmin(address cfxToken, address account) internal view returns (bool) {
        return PeggedNFTUtil.isOwnerOrAdmin(cfxToken, msg.sender) || account == owner();
    }

    /**
     * @dev Get origin cfx tokens on core space in paging view.
     */
    function cfxTokens(uint256 offset, uint256 limit) public view returns (uint256 total, address[] memory tokens) {
        return _pagedTokens(_allCfxTokens, offset, limit);
    }

    /**
     * @dev Register deployment of NFT contract on eSpace for specified `cfxToken` with original `name` and `symbol`.
     */
    function registerDeployEvm(address cfxToken) public onlyPeggable(cfxToken) {
        require(core2EvmTokens[cfxToken] == bytes20(0), "CoreRegistry: deployed already");
        require(registeredCore2EvmTokens[cfxToken] == bytes20(0), "CoreRegistry: registered already");

        string memory name = IERC721Metadata(cfxToken).name();
        string memory symbol = IERC721Metadata(cfxToken).symbol();
        uint256 nftType = PeggedNFTUtil.nftType(cfxToken);

        // register deployment on eSpace via cross space internal contract
        InternalContracts.CROSS_SPACE_CALL.callEVM(
            evmRegistry,
            abi.encodeWithSelector(IEvmRegistry.registerDeploy.selector, cfxToken, nftType, name, symbol)
        );
    }

    /**
     * @dev retrieve deployed pegged token address from eSpace
     */
    function updateDeployed(address cfxToken) public {
        require(core2EvmTokens[cfxToken] == bytes20(0), "CoreRegistry: deployed already");
        require(registeredCore2EvmTokens[cfxToken] == bytes20(0), "CoreRegistry: registered already");

        // register deployment on eSpace via cross space internal contract
        bytes memory result = InternalContracts.CROSS_SPACE_CALL.staticCallEVM(
            evmRegistry,
            abi.encodeWithSelector(IEvmRegistry.getDeployed.selector, cfxToken)
        );

        address evmToken = abi.decode(result, (address));
        core2EvmTokens[cfxToken] = bytes20(evmToken);
        peggedEvm2CoreTokens[bytes20(evmToken)] = cfxToken;
        _allCfxTokens.add(cfxToken);
    }

    /**
     * @dev Register token pair by NFT contract admin instead of deploying with standard NFT template.
     *
     * Note, the pegged `evmToken` should be mintable and burnable for the `evmRegistry`.
     */
    function registerEvm(address cfxToken, bytes20 evmToken) public onlyPeggable(cfxToken) {
        // could be deployed with template already
        // require(core2EvmTokens[cfxToken] == bytes20(0), "deployed already");
        require(registeredCore2EvmTokens[cfxToken] == bytes20(0), "CoreRegistry: registered already");
        require(_isCfxOwnerOrAdmin(cfxToken, msg.sender), "CoreRegistry: forbidden");

        // ensure `evmToken` is valid to be a pegged token on eSpace
        InternalContracts.CROSS_SPACE_CALL.callEVM(
            evmRegistry,
            abi.encodeWithSelector(IEvmRegistry.registerEvm.selector, address(evmToken))
        );

        registeredCore2EvmTokens[cfxToken] = evmToken;
        peggedEvm2CoreTokens[evmToken] = cfxToken;
        _allCfxTokens.add(cfxToken);
    }

    /**
     * @dev Unregister token pair by admin for the specified pegged `evmToken` on eSpace.
     */
    function unregisterEvm(bytes20 evmToken) public {
        address cfxToken = peggedEvm2CoreTokens[evmToken];
        require(cfxToken != address(0), "CoreRegistry: invalid pegged evm token");
        require(_isCfxOwnerOrAdmin(cfxToken, msg.sender), "CoreRegistry: forbidden");

        // ensure `evmToken` is valid to unregister on eSpace
        InternalContracts.CROSS_SPACE_CALL.callEVM(
            evmRegistry,
            abi.encodeWithSelector(IEvmRegistry.unregisterEvm.selector, address(evmToken))
        );

        delete peggedEvm2CoreTokens[evmToken];

        if (core2EvmTokens[cfxToken] == evmToken) {
            // unregister the deployed template
            delete core2EvmTokens[cfxToken];
        } else {
            // allow admin to register another one
            delete registeredCore2EvmTokens[cfxToken];
        }

        if (core2EvmTokens[cfxToken] == bytes20(0) && registeredCore2EvmTokens[cfxToken] == bytes20(0)) {
            _allCfxTokens.remove(cfxToken);
        }
    }

    function setCore2EvmCallback(address cfxToken, address callback) public onlyPeggable(cfxToken) {
        require(_isCfxOwnerOrAdmin(cfxToken, msg.sender), "CoreRegistry: forbidden");
        require(callback.isContract(), "CoreRegistry: not contract");
        core2EvmCallbacks[cfxToken] = callback;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    // Origin tokens on eSpace, and pegged tokens on core space.
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////

    function _isCfxOperatorOrAdmin(bytes20 evmToken, address account) internal returns (bool) {
        require(evmToken != bytes20(0), "CoreRegistry: zero evm address");

        bytes memory result = InternalContracts.CROSS_SPACE_CALL.callEVM(
            evmRegistry,
            abi.encodeWithSelector(IEvmRegistry.approvedOperators.selector, address(evmToken))
        );

        address cfxOperator = abi.decode(result, (address));
        return account == cfxOperator || account == owner();
    }

    /**
     * @dev Deploy NFT contract on core space for specified `evmToken` with original `name` and `symbol`.
     */
    function deployCfx(bytes20 evmToken) public {
        require(evm2CoreTokens[evmToken] == address(0), "CoreRegistry: deployed already");
        require(registeredEvm2CoreTokens[evmToken] == address(0), "CoreRegistry: registered already");

        bytes memory result = InternalContracts.CROSS_SPACE_CALL.callEVM(
            evmRegistry,
            abi.encodeWithSelector(IEvmRegistry.preDeployCfx.selector, address(evmToken))
        );

        (uint256 nftType, string memory name, string memory symbol) = abi.decode(result, (uint256, string, string));

        address cfxToken = _deployPeggedToken(nftType, name, symbol, evmToken);

        evm2CoreTokens[evmToken] = cfxToken;
        peggedCore2EvmTokens[cfxToken] = evmToken;
    }

    /**
     * @dev Register token pair by NFT contract admin instead of deploying with standard NFT template.
     *
     * Note, the pegged `cfxToken` should be mintable and burnable for this `CoreSide`.
     */
    function registerCfx(bytes20 evmToken, address cfxToken) public onlyPeggable(cfxToken) {
        // could be deployed with template already
        // require(evm2coreTokens[evmToken] == address(0), "deployed already");
        require(registeredEvm2CoreTokens[evmToken] == address(0), "CoreRegistry: registered already");
        require(!_allCfxTokens.contains(cfxToken), "CoreRegistry: cycle pegged");
        require(_isCfxOperatorOrAdmin(evmToken, msg.sender), "CoreRegistry: forbidden");

        InternalContracts.CROSS_SPACE_CALL.callEVM(
            evmRegistry,
            abi.encodeWithSelector(IEvmRegistry.registerCfx.selector, address(evmToken))
        );

        registeredEvm2CoreTokens[evmToken] = cfxToken;
        peggedCore2EvmTokens[cfxToken] = evmToken;
        _peggedTokens.add(cfxToken);
    }

    /**
     * @dev Unregister token pair by admin for the specified pegged `cfxToken` on core space.
     */
    function unregisterCfx(address cfxToken) public {
        bytes20 evmToken = peggedCore2EvmTokens[cfxToken];
        require(_isCfxOperatorOrAdmin(evmToken, msg.sender), "CoreRegistry: forbidden");
        require(PeggedNFTUtil.totalSupply(cfxToken) == 0, "CoreRegistry: cfx token has tokens");

        address deployed = evm2CoreTokens[evmToken];
        address registered = registeredEvm2CoreTokens[evmToken];

        if (deployed == address(0) || registered == address(0)) {
            InternalContracts.CROSS_SPACE_CALL.callEVM(
                evmRegistry,
                abi.encodeWithSelector(IEvmRegistry.unregisterCfx.selector, address(evmToken))
            );
        }

        if (deployed == cfxToken) {
            // unregister the deployed template
            delete evm2CoreTokens[evmToken];
        } else {
            // allow admin to register another one
            delete registeredEvm2CoreTokens[evmToken];
        }

        delete peggedCore2EvmTokens[cfxToken];
        require(_peggedTokens.remove(cfxToken), "CoreRegistry: already removed");
    }

    function setEvm2CoreCallback(address cfxToken, address callback) public onlyPeggable(cfxToken) {
        bytes20 evmToken = peggedCore2EvmTokens[cfxToken];
        require(_isCfxOperatorOrAdmin(evmToken, msg.sender), "CoreRegistry: forbidden");
        require(callback.isContract(), "CoreRegistry: not contract");

        core2EvmCallbacks[cfxToken] = callback;
    }
}
