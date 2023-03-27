// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./PeggedTokenDeployer.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

abstract contract Bridge is Initializable, PeggedTokenDeployer, IERC721Receiver {

    function _initialize(address beacon) internal override {
        Initializable._initialize();
        super._initialize(beacon);
    }

    /**
     * @dev Handle NFT cross space request via `IERC721Receiver.safeTransferFrom`.
     */
    function _onERC721Received(address operator, address from, uint256 tokenId, address to) internal virtual;

    /**
     * @dev Implements the IERC721Receiver interface for users to cross NFT via IERC721.safeTransferFrom.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public override returns (bytes4) {
        require(data.length == 20, "invalid to address");
        bytes20 to = bytes20(0);
        assembly {
            to := calldataload(data.offset)
        }
        require(to != bytes20(0), "to address is zero");

        _onERC721Received(operator, from, tokenId, address(to));

        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @dev For owner to withdraw tokens to `receipient` if user use `transferFrom` to cross NFT, which
     * leads to `IERC721Receiver` callback not triggered.
     */
    function withdraw(address token, address receipient, uint256 tokenId) public onlyOwner {
        IERC721(token).transferFrom(address(this), receipient, tokenId);
    }

    function withdrawBatch(address token, address receipient, uint256[] memory tokenIds) public onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            IERC721(token).transferFrom(address(this), receipient, tokenIds[i]);
        }
    }

}
