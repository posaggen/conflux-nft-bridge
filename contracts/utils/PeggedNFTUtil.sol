// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PeggedERC721.sol";
import "./PeggedERC1155.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import "@confluxfans/contracts/token/CRC1155/extensions/ICRC1155Enumerable.sol";

library PeggedNFTUtil {
    uint256 public constant NFT_TYPE_ERC721 = 721;
    uint256 public constant NFT_TYPE_ERC1155 = 1155;

    function nftType(address token) internal view returns (uint256) {
        if (IERC165(token).supportsInterface(type(IERC721).interfaceId)) {
            return NFT_TYPE_ERC721;
        }

        // only ERC721 and ERC1155 supported
        require(IERC165(token).supportsInterface(type(IERC1155).interfaceId), "unsupported NFT type");

        return NFT_TYPE_ERC1155;
    }

    function tokenURI(address token, uint256 id) internal view returns (string memory) {
        if (nftType(token) == NFT_TYPE_ERC721) {
            return IERC721Metadata(token).tokenURI(id);
        }

        return IERC1155MetadataURI(token).uri(id);
    }

    function isOwnerOrAdmin(address token, address account) internal view returns (bool) {
        if (IERC165(token).supportsInterface(type(IAccessControl).interfaceId)) {
            // DEFAULT_ADMIN_ROLE
            if (IAccessControl(token).hasRole(0x00, account)) {
                return true;
            }
        }

        try Ownable(token).owner() returns (address owner) {
            return account == owner;
        } catch {
            return false;
        }
    }

    function totalSupply(address token) internal view returns (uint256) {
        if (nftType(token) == NFT_TYPE_ERC721) {
            return IERC721Enumerable(token).totalSupply();
        }

        return ICRC1155Enumerable(token).totalSupply();
    }

    function batchMint(
        address token,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        string[] memory uris
    ) internal {
        if (nftType(token) == NFT_TYPE_ERC721) {
            for (uint256 i = 0; i < ids.length; i++) {
                require(amounts[i] == 1, "invalid amount for ERC721");
                PeggedERC721(token).mint(to, ids[i], uris[i]);
            }
        } else if (ids.length == 1) {
            PeggedERC1155(token).mint(to, ids[0], amounts[0], uris[0]);
        } else {
            PeggedERC1155(token).mintBatch(to, ids, amounts, uris);
        }
    }

    function batchBurn(address token, uint256[] memory ids, uint256[] memory amounts) internal {
        if (nftType(token) == NFT_TYPE_ERC721) {
            for (uint256 i = 0; i < ids.length; i++) {
                require(amounts[i] == 1, "invalid amount for ERC721");
                PeggedERC721(token).burn(ids[i]);
            }
        } else if (ids.length == 1) {
            PeggedERC1155(token).burn(address(this), ids[0], amounts[0]);
        } else {
            PeggedERC1155(token).burnBatch(address(this), ids, amounts);
        }
    }

    function batchTransfer(address token, address to, uint256[] memory ids, uint256[] memory amounts) internal {
        if (nftType(token) == NFT_TYPE_ERC721) {
            for (uint256 i = 0; i < ids.length; i++) {
                require(amounts[i] == 1, "invalid amount for ERC721");
                IERC721(token).safeTransferFrom(address(this), to, ids[i]);
            }
        } else if (ids.length == 1) {
            IERC1155(token).safeTransferFrom(address(this), to, ids[0], amounts[0], "");
        } else {
            IERC1155(token).safeBatchTransferFrom(address(this), to, ids, amounts, "");
        }
    }
}
