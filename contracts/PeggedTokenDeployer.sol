// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PeggedERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@confluxfans/contracts/token/CRC1155/extensions/ICRC1155Metadata.sol";
import "@confluxfans/contracts/token/CRC1155/extensions/ICRC1155Enumerable.sol";

/**
 * @dev Utility to deploy pegged NFT contracts on core space and eSpace.
 */
abstract contract PeggedTokenDeployer is Ownable {
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    event ContractCreated(address indexed token, bool indexed erc721, string name, string symbol);

    // beacon for pegged ERC721 token
    address public beacon721;

    // beacon for pegged ERC1155 token
    address public beacon1155;

    // all pegged tokens deployed
    EnumerableSet.AddressSet internal _peggedTokens;

    function _initialize(address beacon721_, address beacon1155_) internal virtual {
        beacon721 = beacon721_;
        beacon1155 = beacon1155_;

        _transferOwnership(msg.sender);
    }

    modifier onlyPeggable(address originToken) {
        require(originToken.isContract(), "token is not contract");

        // avoid cycle pegged
        require(!_peggedTokens.contains(originToken), "cycle pegged");

        // requires necessary metadata and enumerable interfaces
        if (IERC165(originToken).supportsInterface(type(IERC721).interfaceId)) {
            require(IERC165(originToken).supportsInterface(type(IERC721Metadata).interfaceId), "IERC721Metadata required");
            require(IERC165(originToken).supportsInterface(type(IERC721Enumerable).interfaceId), "IERC721Enumerable required");
        } else {
            require(IERC165(originToken).supportsInterface(type(IERC1155).interfaceId), "IERC721 or IERC1155 required");

            require(IERC165(originToken).supportsInterface(type(ICRC1155Metadata).interfaceId), "ICRC1155Metadata required");
            require(IERC165(originToken).supportsInterface(type(ICRC1155Enumerable).interfaceId), "ICRC1155Enumerable required");
        }

        _;
    }

    /**
     * @dev Deploy pegged NFT contract with specified `name` and `symbol`. To deploy pegged contract on core space,
     * `evmOriginToken` should be provided so as to read token URI from eSpace via cross space internal contract.
     */
    function _deployPeggedToken(bool erc721, string memory name, string memory symbol, bytes20 evmOriginToken) internal returns (address) {
        address token;

        if (erc721) {
            require(beacon721 != address(0), "beacon721 uninitialized");
            token = address(new BeaconProxy(beacon721, ""));
        } else {
            require(beacon1155 != address(0), "beacon1155 uninitialized");
            token = address(new BeaconProxy(beacon1155, ""));
        }

        require(_peggedTokens.add(token), "duplicated pegged token created");

        PeggedNFT(token).initialize(name, symbol, evmOriginToken, owner());

        emit ContractCreated(token, erc721, name, symbol);

        return token;
    }

}
