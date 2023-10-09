// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PeggedNFT.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Pausable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import "@confluxfans/contracts/InternalContracts/InternalContractsHandler.sol";
import "@confluxfans/contracts/token/CRC1155/extensions/ICRC1155Metadata.sol";
import "@confluxfans/contracts/token/CRC1155/extensions/CRC1155Enumerable.sol";
import "@confluxfans/contracts/InternalContracts/InternalContractsLib.sol";

contract PeggedERC1155 is
    PeggedNFT,
    CRC1155Enumerable,
    ERC1155Burnable,
    ERC1155Pausable,
    ERC1155URIStorage,
    ICRC1155Metadata
{
    constructor() ERC1155("") {}

    function name() public view override returns (string memory) {
        return _name_;
    }

    function symbol() public view override returns (string memory) {
        return _symbol_;
    }

    function mint(address to, uint256 id, uint256 amount, string memory uri_) public onlyRole(MINTER_ROLE) {
        _mint(to, id, amount, "");

        if (bytes(uri_).length > 0) {
            _setURI(id, uri_);
        }
    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        string[] memory uris
    ) public onlyRole(MINTER_ROLE) {
        require(ids.length == uris.length, "PeggedERC1155: ids and uris length mismatch");

        _mintBatch(to, ids, amounts, "");

        for (uint256 i = 0; i < ids.length; i++) {
            if (bytes(uris[i]).length > 0) {
                _setURI(ids[i], uris[i]);
            }
        }
    }

    function uri(
        uint256 tokenId
    ) public view virtual override(ERC1155, ERC1155URIStorage, IERC1155MetadataURI) returns (string memory) {
        if (evmSideToken == bytes20(0)) {
            return ERC1155URIStorage.uri(tokenId);
        }

        // read token URI from eSpace for pegged token on core space
        bytes memory result = InternalContracts.CROSS_SPACE_CALL.staticCallEVM(
            evmSideToken,
            abi.encodeWithSelector(IERC1155MetadataURI.uri.selector, tokenId)
        );

        return abi.decode(result, (string));
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(CRC1155Enumerable, ERC1155, ERC1155Pausable) {}

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControlEnumerable, CRC1155Enumerable, ERC1155, IERC165) returns (bool) {
        return interfaceId == type(ICRC1155Metadata).interfaceId || super.supportsInterface(interfaceId);
    }
}
