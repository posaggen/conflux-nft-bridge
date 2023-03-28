// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PeggedNFTUtil.sol";
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

    event ContractCreated(
        address indexed token,
        uint256 indexed nftType,
        string name,
        string symbol
    );

    // beacon for pegged tokens
    mapping(uint256 => address) public beacons;

    // all pegged tokens deployed
    EnumerableSet.AddressSet internal _peggedTokens;

    function _initialize(address beacon721, address beacon1155) internal virtual {
        beacons[PeggedNFTUtil.NFT_TYPE_ERC721] = beacon721;
        beacons[PeggedNFTUtil.NFT_TYPE_ERC1155] = beacon1155;

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
    function _deployPeggedToken(
        uint256 nftType,
        string memory name,
        string memory symbol,
        bytes20 evmOriginToken
    ) internal returns (address) {
        require(beacons[nftType] != address(0), "beacon uninitialized");
        require(bytes(name).length > 0, "name required");
        require(bytes(symbol).length > 0, "symbol required");

        address token = address(new BeaconProxy(beacons[nftType], ""));
        require(_peggedTokens.add(token), "duplicated pegged token created");
        PeggedNFT(token).initialize(name, symbol, evmOriginToken, owner());

        emit ContractCreated(token, nftType, name, symbol);

        return token;
    }

}
