// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Bridge.sol";
import "./EvmSide.sol";
import "./PeggedNFTUtil.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@confluxfans/contracts/InternalContracts/InternalContractsHandler.sol";
import "@confluxfans/contracts/InternalContracts/InternalContractsLib.sol";

contract CoreSide is Bridge, InternalContractsHandler {

    // interact via cross space internal contract
    bytes20 public evmSide;

    // cfx token => evm token (pegged on eSpace)
    mapping(address => bytes20) public core2evmTokens;
    // all cfx tokens that pegged on eSpace
    address[] public allCfxTokens;

    // evm token => cfx token (pegged on core space)
    mapping(bytes20 => address) public evm2coreTokens;
    // cfx token => evm token (pegged on core space)
    mapping(address => bytes20) public peggedCore2EvmTokens;
    // all pegged cfx tokens on core space
    address[] public allPeggedCfxTokens;

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
        require(core2evmTokens[cfxToken] == bytes20(0), "deployed already");

        uint256 nftType = PeggedNFTUtil.nftType(cfxToken);

        // deply on eSpace via cross space internal contract
        bytes memory result = InternalContracts.CROSS_SPACE_CALL.callEVM(evmSide,
            abi.encodeWithSelector(EvmSide.deploy.selector, nftType, name, symbol)
        );

        address evmToken = abi.decode(result, (address));
        core2evmTokens[cfxToken] = bytes20(evmToken);
        allCfxTokens.push(cfxToken);
    }

    function _onNFTReceived(
        address nft,
        address operator,           // cfx operator
        address from,               // cfx from
        uint256[] memory ids,
        uint256[] memory amounts,
        address to                  // evm to
    ) internal override {
        if (core2evmTokens[nft] != bytes20(0)) {
            // cross origin token from core space to eSpace as pegged
            _crossToEvm(nft, operator, from, ids, amounts, to);
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
        address evmAccount
    ) private {
        bytes20 evmToken = core2evmTokens[cfxToken];
        require(evmToken != bytes20(0), "cfx token unsupported");

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
        address cfxToken,
        uint256[] memory ids,
        uint256[] memory amounts,
        address recipient
    ) public {
        require(ids.length == amounts.length, "ids and amounts length mismatch");

        bytes20 evmToken = core2evmTokens[cfxToken];
        require(evmToken != bytes20(0), "cfx token unsupported");

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
        require(evm2coreTokens[evmToken] == address(0), "deployed already");

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

        evm2coreTokens[evmToken] = cfxToken;
        peggedCore2EvmTokens[cfxToken] = evmToken;
        allPeggedCfxTokens.push(cfxToken);
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
