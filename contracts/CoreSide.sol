// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./PeggedTokenDeployer.sol";
import "./EvmSide.sol";
import "./PeggedERC721.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@confluxfans/contracts/InternalContracts/InternalContractsHandler.sol";
import "@confluxfans/contracts/InternalContracts/InternalContractsLib.sol";

contract CoreSide is Initializable, PeggedTokenDeployer, AccessControlEnumerable, InternalContractsHandler, IERC721Receiver {

    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

    // interact via cross space internal contract
    bytes20 public evmSide;

    // cfx token => evm token (pegged on eSpace)
    mapping(address => bytes20) public core2evmTokens;

    // evm token => cfx token (pegged on core space)
    mapping(bytes20 => address) public evm2coreTokens;
    // cfx token => evm token (pegged on core space)
    mapping(address => bytes20) public peggedCore2EvmTokens;

    // emitted when cross NFT from core space (origin) to eSpace (pegged)
    event CrossToEvm(
        address indexed cfxToken,
        bytes20 evmToken,
        address cfxOperator,
        address indexed cfxFrom,
        bytes20 indexed evmTo,
        uint256 tokenId
    );

    // emitted when withdraw NFT from eSpace (pegged) to core space (origin)
    event WithdrawFromEvm(
        address indexed cfxToken,
        bytes20 evmToken,
        address indexed cfxAccount,
        address indexed cfxRecipient,
        uint256 tokenId
    );

    // emitted when cross NFT from eSpace (origin) to core space (pegged)
    event CrossFromEvm(
        address indexed cfxToken,
        bytes20 evmToken,
        address indexed cfxAccount,
        address indexed cfxRecipient,
        uint256 tokenId
    );

    // emitted when withdraw NFT from core space (pegged) to eSpace (origin)
    event WithdrawToEvm(
        address indexed cfxToken,
        bytes20 evmToken,
        address cfxOperator,
        address indexed cfxFrom,
        bytes20 indexed evmTo,
        uint256 tokenId
    );

    function initialize(bytes20 evmSide_, address beacon_) public {
        Initializable._initialize();
        PeggedTokenDeployer._initialize(beacon_);

        evmSide = evmSide_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEPLOYER_ROLE, msg.sender);

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
     * @dev Deploy NFT contract on eSpace for specified `cfxToken` with optional `name` and `symbol`.
     */
    function deployEvm(address cfxToken, string memory name, string memory symbol) public onlyRole(DEPLOYER_ROLE) onlyPeggable(cfxToken) {
        require(core2evmTokens[cfxToken] == bytes20(0), "deployed already");

        // read NFT metadata from cfx token
        if (bytes(name).length == 0 || bytes(symbol).length == 0) {
            name = IERC721Metadata(cfxToken).name();
            symbol = IERC721Metadata(cfxToken).symbol();
        }

        // deply on eSpace via cross space internal contract
        bytes memory result = InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
            abi.encodeWithSelector(EvmSide.deploy.selector, name, symbol)
        );

        address evmToken = abi.decode(result, (address));
        core2evmTokens[cfxToken] = bytes20(evmToken);
    }

    /**
     * @dev Implements the IERC721Receiver interface for users to cross NFT via IERC721.safeTransferFrom.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public override returns (bytes4) {
        // parse evm account from data
        require(data.length == 20, "data should be evm address");
        address evmAccount = abi.decode(data, (address));
        require(evmAccount != address(0), "evm address not provided");

        if (core2evmTokens[msg.sender] != bytes20(0)) {
            // cross origin token from core space to eSpace as pegged
            _crossToEvm(operator, from, tokenId, evmAccount);
        } else {
            // withdraw pegged token on core space to eSpace
            require(peggedCore2EvmTokens[msg.sender] != bytes20(0), "invalid token received");
            _withdrawToEvm(operator, from, tokenId, evmAccount);
        }

        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @dev Cross origin token from core space to eSpace as pegged.
     */
    function _crossToEvm(address operator, address from, uint256 tokenId, address evmAccount) private {
        address cfxToken = msg.sender;
        bytes20 evmToken = core2evmTokens[cfxToken];

        string memory uri = IERC721Metadata(cfxToken).tokenURI(tokenId);

        // mint on eSpace via cross space internal contract
        InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
            abi.encodeWithSelector(EvmSide.mint.selector, address(evmToken), evmAccount, uri)
        );

        emit CrossToEvm(cfxToken, evmToken, operator, from, bytes20(evmAccount), tokenId);
    }

    /**
     * @dev Withdraw locked NFT from eSpace to core space.
     */
    function withdrawFromEvm(address cfxToken, uint256 tokenId, address recipient) public {
        bytes20 evmToken = core2evmTokens[cfxToken];
        require(evmToken != bytes20(0), "cfx token unsupported");

        // burn on eSpace via cross space internal contract
        InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
            abi.encodeWithSelector(EvmSide.burn.selector, address(evmToken), msg.sender, tokenId)
        );

        IERC721(cfxToken).safeTransferFrom(address(this), recipient, tokenId);

        emit WithdrawFromEvm(cfxToken, evmToken, msg.sender, recipient, tokenId);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    // Origin tokens on eSpace, and pegged tokens on core space.
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Deploy NFT contract on core space for specified `evmToken` with optional `name` and `symbol`.
     */
    function deployCfx(bytes20 evmToken, string memory name, string memory symbol) public onlyRole(DEPLOYER_ROLE) {
        require(evm2coreTokens[evmToken] == address(0), "deployed already");

        bytes memory result = InternalContracts.CROSS_SPACE_CALL.staticCallEVM(evmSide,
            abi.encodeWithSelector(EvmSide.preDeployCfx.selector, address(evmToken))
        );

        if (bytes(name).length == 0 || bytes(symbol).length == 0) {
            (name, symbol) = abi.decode(result, (string, string));
        }

        address cfxToken = _deployPeggedToken(name, symbol, evmToken);

        evm2coreTokens[evmToken] = cfxToken;
        peggedCore2EvmTokens[cfxToken] = evmToken;
    }

    /**
     * @dev Cross locked NFT from eSpace to core space as pegged.
     */
    function crossFromEvm(address cfxToken, uint256 tokenId, address recipient) public {
        bytes20 evmToken = peggedCore2EvmTokens[cfxToken];
        require(evmToken != bytes20(0), "cfx token unsupported");

        InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
            abi.encodeWithSelector(EvmSide.unlock.selector, address(evmToken), msg.sender, tokenId)
        );

        // pegged NFT on core space do not require uri, instead, read from eSpace directly.
        PeggedERC721(cfxToken).mint(recipient, tokenId, "");

        emit CrossFromEvm(cfxToken, evmToken, msg.sender, recipient, tokenId);
    }

    /**
     * @dev Withdraw pegged token on core space back to eSpace.
     */
    function _withdrawToEvm(address operator, address from, uint256 tokenId, address evmAccount) private {
        address cfxToken = msg.sender;
        bytes20 evmToken = peggedCore2EvmTokens[cfxToken];

        PeggedERC721(cfxToken).burn(tokenId);

        InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
            abi.encodeWithSelector(EvmSide.transfer.selector, address(evmToken), evmAccount, tokenId)
        );
        
        emit WithdrawToEvm(cfxToken, evmToken, operator, from, bytes20(evmAccount), tokenId);
    }

}
