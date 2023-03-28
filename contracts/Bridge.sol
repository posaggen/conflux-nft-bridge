// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./PeggedTokenDeployer.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

abstract contract Bridge is Initializable, PeggedTokenDeployer, IERC721Receiver, ERC1155Holder {

    function _initialize(address beacon721, address beacon1155) internal override {
        Initializable._initialize();
        super._initialize(beacon721, beacon1155);
    }

    function _onNFTReceived(
        address nft,
        address operator,
        address from,
        uint256[] memory ids,       // one id for ERC721
        uint256[] memory amounts,   // 1 for ERC721
        address to                  // to address on opposite space
    ) internal virtual;

    /**
     * @dev Implements the IERC721Receiver interface for users to cross NFT via IERC721.safeTransferFrom.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory data
    ) public override returns (bytes4) {
        uint256[] memory ids = _asSingletonArray(tokenId);
        uint256[] memory amounts = _asSingletonArray(1);
        address to = _parseToAddress(data);

        _onNFTReceived(msg.sender, operator, from, ids, amounts, to);

        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @dev Allow users to cross ERC721 tokens in batch.
     */
    function safeBatchTransferFrom(address erc721, uint256[] memory ids, bytes memory data) public {
        require(PeggedNFTUtil.nftType(erc721) == PeggedNFTUtil.NFT_TYPE_ERC721, "ERC721 token required");

        uint256[] memory amounts = new uint256[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            IERC721(erc721).transferFrom(msg.sender, address(this), ids[i]);
            amounts[i] = 1;
        }

        address to = _parseToAddress(data);
        _onNFTReceived(erc721, msg.sender, msg.sender, ids, amounts, to);
    }

    /**
     * @dev Implements the IERC1155Receiver interface for users to cross NFT via IERC1155.safeTransferFrom.
     */
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes memory data
    ) public virtual override returns (bytes4) {
        uint256[] memory ids = _asSingletonArray(id);
        uint256[] memory amounts = _asSingletonArray(value);
        address to = _parseToAddress(data);

        _onNFTReceived(msg.sender, operator, from, ids, amounts, to);

        return IERC1155Receiver.onERC1155Received.selector;
    }

    /**
     * @dev Implements the IERC1155Receiver interface for users to cross multiple NFT via IERC1155.safeBatchTransferFrom.
     */
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) public virtual override returns (bytes4) {
        require(ids.length == values.length, "ids and values length mismatch");

        address to = _parseToAddress(data);

        _onNFTReceived(msg.sender, operator, from, ids, values, to);

        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    function _parseToAddress(bytes memory data) private pure returns (address to) {
        require(data.length == 20, "invalid to address");
        assembly {
            to := mload(add(data, 20))
        }
        require(to != address(0), "to address is zero");
    }

    function _asSingletonArray(uint256 element) private pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;
        return array;
    }

}
