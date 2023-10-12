// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./utils/PeggedNFTUtil.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@confluxfans/contracts/token/CRC1155/extensions/ICRC1155Metadata.sol";
import "@confluxfans/contracts/token/CRC1155/extensions/ICRC1155Enumerable.sol";

/**
 * @dev Utility to deploy pegged NFT contracts on core space and eSpace.
 */
abstract contract PeggedTokenDeployer is Ownable {
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;
    using Math for uint256;

    event ContractCreated(address indexed token, uint256 indexed nftType, string name, string symbol);

    // beacon for pegged tokens
    mapping(uint256 => address) public beacons;

    // all pegged tokens deployed
    EnumerableSet.AddressSet internal _peggedTokens;

    // bridge address
    address public bridge;

    function _initialize(address beacon721, address beacon1155) internal virtual {
        beacons[PeggedNFTUtil.NFT_TYPE_ERC721] = beacon721;
        beacons[PeggedNFTUtil.NFT_TYPE_ERC1155] = beacon1155;

        _transferOwnership(msg.sender);
    }

    function setBridge(address _bridge) external onlyOwner {
        bridge = _bridge;
    }

    function _pagedTokens(
        EnumerableSet.AddressSet storage all,
        uint256 offset,
        uint256 limit
    ) internal view returns (uint256 total, address[] memory tokens) {
        total = all.length();
        if (offset >= total) {
            return (total, new address[](0));
        }

        uint256 endExclusive = total.min(offset + limit);
        tokens = new address[](endExclusive - offset);

        for (uint256 i = offset; i < endExclusive; i++) {
            tokens[i - offset] = all.at(i);
        }
    }

    /**
     * @dev Get pegged tokens in paging view.
     */
    function peggedTokens(uint256 offset, uint256 limit) public view returns (uint256 total, address[] memory tokens) {
        return _pagedTokens(_peggedTokens, offset, limit);
    }

    function _validateNFTContract(address originToken) internal view {
        require(originToken.isContract(), "PeggedTokenDeployer: token is not contract");
        // requires necessary metadata and enumerable interfaces
        if (IERC165(originToken).supportsInterface(type(IERC721).interfaceId)) {
            require(
                IERC165(originToken).supportsInterface(type(IERC721Metadata).interfaceId),
                "PeggedTokenDeployer: IERC721Metadata required"
            );
        } else {
            require(
                IERC165(originToken).supportsInterface(type(IERC1155).interfaceId),
                "PeggedTokenDeployer: IERC721 or IERC1155 required"
            );

            require(
                IERC165(originToken).supportsInterface(type(ICRC1155Metadata).interfaceId),
                "PeggedTokenDeployer: ICRC1155Metadata required"
            );
        }
    }

    modifier onlyPeggable(address originToken) {
        _validateNFTContract(originToken);

        // avoid cycle pegged
        require(!_peggedTokens.contains(originToken), "PeggedTokenDeployer: cycle pegged");

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
        require(beacons[nftType] != address(0), "PeggedTokenDeployer: beacon uninitialized");
        require(bytes(name).length > 0, "PeggedTokenDeployer: name required");
        require(bytes(symbol).length > 0, "PeggedTokenDeployer: symbol required");

        address token = address(new BeaconProxy(beacons[nftType], ""));
        require(_peggedTokens.add(token), "PeggedTokenDeployer: duplicated pegged token created");
        PeggedNFT(token).initialize(name, symbol, evmOriginToken, owner(), bridge);

        emit ContractCreated(token, nftType, name, symbol);

        return token;
    }
}
