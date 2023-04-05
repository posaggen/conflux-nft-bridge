// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Bridge.sol";
import "./EvmSide.sol";
import "./PeggedNFTUtil.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@confluxfans/contracts/InternalContracts/InternalContractsHandler.sol";
import "@confluxfans/contracts/InternalContracts/InternalContractsLib.sol";

contract CoreSide is Bridge, InternalContractsHandler {
    using EnumerableSet for EnumerableSet.AddressSet;

    // interact via cross space internal contract
    bytes20 public evmSide;

    // indexes for token pair that pegged on eSpace
    // cfx token => evm token (pegged token deployed on eSpace)
    mapping(address => bytes20) public core2EvmTokens;
    // registered token pair by admin other than deployed with standard template
    mapping(address => bytes20) public registeredCore2EvmTokens;
    // evm token => cfx token (pegged token deployed on eSpace)
    mapping(bytes20 => address) public peggedEvm2CoreTokens;
    // all cfx tokens that pegged on eSpace
    EnumerableSet.AddressSet private _allCfxTokens;

    // indexes for token pair that pegged on core space
    // evm token => cfx token (pegged on core space)
    mapping(bytes20 => address) public evm2CoreTokens;
    // registered toke pair by admin other than deployed with standard template
    mapping(bytes20 => address) public registeredEvm2CoreTokens;
    // cfx token => evm token (pegged on core space)
    mapping(address => bytes20) public peggedCore2EvmTokens;

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

    function initialize(bytes20 evmSide_, address beacon721, address beacon1155) public {
        Bridge._initialize(beacon721, beacon1155);

        evmSide = evmSide_;

        // connect to evm side
        InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
            abi.encodeWithSelector(EvmSide.setCfxSide.selector)
        );
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    // Origin tokens on core space, and pegged tokens on eSpace.
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Get origin cfx tokens on core space in paging view.
     */
    function cfxTokens(uint256 offset, uint256 limit) public view returns (uint256 total, address[] memory tokens) {
        return _pagedTokens(_allCfxTokens, offset, limit);
    }

    /**
     * @dev Deploy NFT contract on eSpace for specified `cfxToken` with original `name` and `symbol`.
     */
    function deployEvm(address cfxToken) public onlyPeggable(cfxToken) {
        string memory name = IERC721Metadata(cfxToken).name();
        string memory symbol = IERC721Metadata(cfxToken).symbol();
        _deployEvm(cfxToken, name, symbol);
    }

    /**
     * @dev Deploy NFT contract on eSpace for specified `cfxToken` with `name` and `symbol` by owner only.
     */
    function deployEvmByAdmin(address cfxToken, string memory name, string memory symbol) public onlyPeggable(cfxToken) onlyOwner {
        _deployEvm(cfxToken, name, symbol);
    }

    function _deployEvm(address cfxToken, string memory name, string memory symbol) private {
        require(core2EvmTokens[cfxToken] == bytes20(0), "deployed already");
        require(registeredCore2EvmTokens[cfxToken] == bytes20(0), "registered already");

        uint256 nftType = PeggedNFTUtil.nftType(cfxToken);

        // deply on eSpace via cross space internal contract
        bytes memory result = InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
            abi.encodeWithSelector(EvmSide.deploy.selector, nftType, name, symbol)
        );

        address evmToken = abi.decode(result, (address));
        core2EvmTokens[cfxToken] = bytes20(evmToken);
        peggedEvm2CoreTokens[bytes20(evmToken)] = cfxToken;
        _allCfxTokens.add(cfxToken);
    }

    /**
     * @dev Register token pair by NFT contract admin instead of deploying with standard NFT template.
     *
     * Note, the pegged `evmToken` should be mintable and burnable for the `evmSide`.
     */
    function registerEvm(address cfxToken, bytes20 evmToken) public onlyPeggable(cfxToken) {
        // could be deployed with template already
        // require(core2EvmTokens[cfxToken] == bytes20(0), "deployed already");
        require(registeredCore2EvmTokens[cfxToken] == bytes20(0), "registered already");
        require(PeggedNFTUtil.isOwnerOrAdmin(cfxToken, msg.sender), "owner or admin required");

        // ensure `evmToken` is valid to be a pegged token on eSpace
        InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
            abi.encodeWithSelector(EvmSide.registerEvm.selector, address(evmToken))
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
        require(cfxToken != address(0), "invalid pegged evm token");

        require(PeggedNFTUtil.isOwnerOrAdmin(cfxToken, msg.sender), "owner or admin required");

        // ensure `evmToken` is vlaid to unregister on eSpace
        InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
            abi.encodeWithSelector(EvmSide.unregisterEvm.selector, address(evmToken))
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

    function _onNFTReceived(
        address nft,
        address operator,           // cfx operator
        address from,               // cfx from
        uint256[] memory ids,
        uint256[] memory amounts,
        address to                  // evm to
    ) internal override {
        // registered is prior to deployed
        if (registeredCore2EvmTokens[nft] != bytes20(0)) {
            // cross origin token from core space to eSpace as pegged
            _crossToEvm(nft, operator, from, ids, amounts, registeredCore2EvmTokens[nft], to);
        } else if (core2EvmTokens[nft] != bytes20(0)) {
            // cross origin token from core space to eSpace as pegged
            _crossToEvm(nft, operator, from, ids, amounts, core2EvmTokens[nft], to);
        } else {
            // withdraw pegged token on core space to eSpace
            require(peggedCore2EvmTokens[nft] != bytes20(0), "invalid token received");
            _withdrawToEvm(nft, operator, from, ids, amounts, to);
        }
    }

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
        InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
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

        address cfxToken = peggedEvm2CoreTokens[evmToken];
        require(cfxToken != address(0), "invalid pegged evm token");

        // burn on eSpace via cross space internal contract
        InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
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
     * @dev Deploy NFT contract on core space for specified `evmToken` with original `name` and `symbol`.
     */
    function deployCfx(bytes20 evmToken) public {
        _deployCfx(evmToken, "", "");
    }

    /**
     * @dev Deploy NFT contract on core space for specified `evmToken` with `name` and `symbol` by owner only.
     */
    function deployCfxByAdmin(bytes20 evmToken, string memory name, string memory symbol) public onlyOwner {
       _deployCfx(evmToken, name, symbol);
    }

    function _deployCfx(bytes20 evmToken, string memory name, string memory symbol) private {
        require(evm2CoreTokens[evmToken] == address(0), "deployed already");
        require(registeredEvm2CoreTokens[evmToken] == address(0), "registered already");

        bytes memory result = InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
            abi.encodeWithSelector(EvmSide.preDeployCfx.selector, address(evmToken))
        );

        (uint256 nftType, string memory name2, string memory symbol2) = abi.decode(result, (uint256, string, string));

        address cfxToken;
        if (bytes(name).length == 0 || bytes(symbol).length == 0) {
            cfxToken = _deployPeggedToken(nftType, name2, symbol2, evmToken);
        } else {
            cfxToken = _deployPeggedToken(nftType, name, symbol, evmToken);
        }

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
        require(registeredEvm2CoreTokens[evmToken] == address(0), "registered already");
        require(!_allCfxTokens.contains(cfxToken), "cycle pegged");

        InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
            abi.encodeWithSelector(EvmSide.registerCfx.selector, address(evmToken), msg.sender)
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
        require(evmToken != bytes20(0), "invalid pegged cfx token");

        require(PeggedNFTUtil.totalSupply(cfxToken) == 0, "cfx token has tokens");

        address deployed = evm2CoreTokens[evmToken];
        address registered = registeredEvm2CoreTokens[evmToken];

        bool removed = deployed == address(0) || registered == address(0);
        InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
            abi.encodeWithSelector(EvmSide.unregisterCfx.selector, address(evmToken), msg.sender, removed)
        );

        if (deployed == cfxToken) {
            // unregister the deployed template
            delete evm2CoreTokens[evmToken];
        } else {
            // allow admin to register another one
            delete registeredEvm2CoreTokens[evmToken];
        }

        delete peggedCore2EvmTokens[cfxToken];
        require(_peggedTokens.remove(cfxToken), "already removed");
    }

    /**
     * @dev Cross locked NFT from eSpace to core space as pegged.
     */
    function crossFromEvm(
        address cfxToken,
        uint256[] memory ids,
        uint256[] memory amounts,
        address recipient
    ) public {
        require(ids.length == amounts.length, "ids and amounts length mismatch");

        bytes20 evmToken = peggedCore2EvmTokens[cfxToken];
        require(evmToken != bytes20(0), "cfx token unsupported");

        InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
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
        bytes20 evmToken = peggedCore2EvmTokens[cfxToken];
        require(evmToken != bytes20(0), "cfx token unsupported");

        PeggedNFTUtil.batchBurn(cfxToken, ids, amounts);

        InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
            abi.encodeWithSelector(EvmSide.transfer.selector, address(evmToken), evmAccount, ids, amounts)
        );
        
        emit WithdrawToEvm(cfxToken, evmToken, operator, from, bytes20(evmAccount), ids, amounts);
    }

}
