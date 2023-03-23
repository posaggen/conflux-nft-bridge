// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EvmSide.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@confluxfans/contracts/InternalContracts/InternalContractsHandler.sol";
import "@confluxfans/contracts/InternalContracts/InternalContractsLib.sol";

contract CoreSide is Initializable, AccessControlEnumerable, InternalContractsHandler, IERC721Receiver {
    using Address for address;

    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

    // interact via cross space internal contract
    bytes20 public evmSide;

    // cfx token => evm token
    mapping(address => address) public core2evmTokens;
    // all cfx tokens for enumeration
    address[] public coreTokens;

    // emitted when cross NFT from core space (origin) to eSpace (pegged)
    event CrossToEvm(
        address indexed cfxToken,
        address evmToken,
        address cfxOperator,
        address indexed cfxFrom,
        address indexed evmTo,
        uint256 tokenId
    );

    // emitted when withdraw NFT from eSpace (pegged) to core space (origin)
    event WithdrawFromEvm(
        address indexed cfxToken,
        address evmToken,
        address indexed operator,
        address indexed recipient,
        uint256 tokenId
    );

    function initialize(bytes20 evmSide_) public {
        Initializable._initialize();

        evmSide = evmSide_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEPLOYER_ROLE, msg.sender);

        // connect with evm side
        InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
            abi.encodeWithSelector(EvmSide.setCfxSide.selector)
        );
    }

    /**
     * @dev Deploy NFT contract on eSpace for specified `cfxToken` with optional `name` and `symbol`.
     */
    function deployEvm(address cfxToken, string memory name, string memory symbol) public onlyRole(DEPLOYER_ROLE) {
        require(cfxToken.isContract(), "cfxToken is not contract");
        require(core2evmTokens[cfxToken] == address(0), "deployed already");
        require(IERC165(cfxToken).supportsInterface(type(IERC721Metadata).interfaceId), "IERC721Metadata required");

        // read NFT metadata from cfx token
        if (bytes(name).length == 0 || bytes(symbol).length == 0) {
            name = IERC721Metadata(cfxToken).name();
            symbol = IERC721Metadata(cfxToken).symbol();
        }

        // deply on eSpace via cross space internal contract
        bytes memory result = InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
            abi.encodeWithSelector(EvmSide.deploy.selector, name, symbol)
        );

        core2evmTokens[cfxToken] = abi.decode(result, (address));
        coreTokens.push(cfxToken);
    }

    /**
     * @dev Implements the IERC721Receiver interface for users to cross NFT from core to eSpace via IERC721.safeTransferFrom.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public override returns (bytes4) {
        address cfxToken = msg.sender;
        address evmToken = core2evmTokens[cfxToken];
        require(evmToken != address(0), "cfx token unsupported");

        // parse evm account from data
        require(data.length == 20, "data should be evm address");
        address evmAccount = abi.decode(data, (address));
        require(evmAccount != address(0), "evm address not provided");

        // mint with token uri for non-placeholder case
        string memory uri = IERC721Metadata(cfxToken).tokenURI(tokenId);

        // mint on eSpace via cross space internal contract
        InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
            abi.encodeWithSelector(EvmSide.mint.selector, evmToken, evmAccount, uri)
        );

        emit CrossToEvm(cfxToken, evmToken, operator, from, evmAccount, tokenId);

        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @dev Withdraw locked NFT from eSpace to core space.
     */
    function withdrawFromEvm(address cfxToken, uint256 tokenId, address recipient) public {
        address evmToken = core2evmTokens[cfxToken];
        require(evmToken != address(0), "cfx token unsupported");

        // burn on eSpace via cross space internal contract
        InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
            abi.encodeWithSelector(EvmSide.burn.selector, evmToken, msg.sender, tokenId)
        );

        IERC721(cfxToken).safeTransferFrom(address(this), recipient, tokenId);

        emit WithdrawFromEvm(cfxToken, evmToken, msg.sender, recipient, tokenId);
    }

}