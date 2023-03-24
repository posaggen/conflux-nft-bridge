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

    modifier onlyPeggable(address token) {
        require(token.isContract(), "token is not contract");
        require(!_peggedTokens.contains(token), "cycle pegged");
        require(IERC165(token).supportsInterface(type(IERC721Metadata).interfaceId), "IERC721Metadata required");
        _;
    }

    function _deployPeggedToken(string memory name, string memory symbol, bytes20 evmSide) internal returns (address) {
        require(beacon != address(0), "beacon uninitialized");

        address token = address(new BeaconProxy(beacon, ""));
        require(_peggedTokens.add(token), "duplicated pegged token created");

        PeggedERC721(token).initialize(name, symbol, evmSide, owner());

        return token;
    }

}
