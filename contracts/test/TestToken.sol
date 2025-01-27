// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@confluxfans/contracts/token/CRC1155/extensions/CRC1155Metadata.sol";
import "@confluxfans/contracts/token/CRC1155/extensions/CRC1155Enumerable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";

contract TestERC721 is ERC721Enumerable, ERC721Burnable, Ownable {
    string public placeholderURI;

    constructor(string memory name, string memory symbol, string memory placeholderURI_) ERC721(name, symbol) {
        placeholderURI = placeholderURI_;
    }

    function setPlaceholderURI(string memory placeholderURI_) public onlyOwner {
        placeholderURI = placeholderURI_;
    }

    function tokenURI(uint256) public view override returns (string memory) {
        return placeholderURI;
    }

    function mint(address to, uint256[] memory tokenIds) public onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _safeMint(to, tokenIds[i]);
        }
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }
}

contract TestERC1155 is CRC1155Metadata, CRC1155Enumerable, ERC1155Burnable, Ownable {
    constructor(
        string memory name,
        string memory symbol,
        string memory uri
    ) ERC1155(uri) CRC1155Metadata(name, symbol) {}

    function setURI(string memory uri) public onlyOwner {
        _setURI(uri);
    }

    function mint(address to, uint256[] memory ids, uint256[] memory amounts) public onlyOwner {
        require(ids.length == amounts.length, "ids and amounts length mismatch");
        _mintBatch(to, ids, amounts, "");
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(CRC1155Enumerable, ERC1155, IERC165) returns (bool) {
        return interfaceId == type(ICRC1155Metadata).interfaceId || super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(CRC1155Enumerable, ERC1155) {}
}

contract TestERC20 is ERC20, Ownable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

contract TestTokenFactory {
    event Created(address indexed token, uint256 eip);

    address public latestDeployed;

    function deploy721(string memory name, string memory symbol, string memory placeholderURI) public {
        TestERC721 token = new TestERC721(name, symbol, placeholderURI);
        token.transferOwnership(msg.sender);
        latestDeployed = address(token);
        emit Created(address(token), 721);
    }

    function deploy1155(string memory name, string memory symbol, string memory uri) public {
        TestERC1155 token = new TestERC1155(name, symbol, uri);
        token.transferOwnership(msg.sender);
        latestDeployed = address(token);
        emit Created(address(token), 1155);
    }

    function deploy20(string memory name, string memory symbol) public {
        TestERC20 token = new TestERC20(name, symbol);
        token.transferOwnership(msg.sender);
        latestDeployed = address(token);
        emit Created(address(token), 20);
    }
}
