// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PeggedERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @dev Utility to deploy pegged NFT contracts on core space and eSpace.
 */
abstract contract PeggedTokenDeployer is Ownable {
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    // beacon for pegged token
    address public beacon;

    // all pegged tokens deployed
    EnumerableSet.AddressSet internal _peggedTokens;

    function _initialize(address beacon_) internal {
        beacon = beacon_;

        _transferOwnership(msg.sender);
    }

    modifier onlyPeggable(address originToken) {
        require(originToken.isContract(), "token is not contract");
        require(!_peggedTokens.contains(originToken), "cycle pegged");
        require(IERC165(originToken).supportsInterface(type(IERC721Metadata).interfaceId), "IERC721Metadata required");
        _;
    }

    /**
     * @dev Deploy pegged NFT contract with specified `name` and `symbol`. To deploy pegged contract on core space,
     * `evmOriginToken` should be provided so as to read token URI from eSpace via cross space internal contract.
     */
    function _deployPeggedToken(string memory name, string memory symbol, bytes20 evmOriginToken) internal returns (address) {
        require(beacon != address(0), "beacon uninitialized");

        address token = address(new BeaconProxy(beacon, ""));
        require(_peggedTokens.add(token), "duplicated pegged token created");

        PeggedERC721(token).initialize(name, symbol, evmOriginToken, owner());

        return token;
    }

}
