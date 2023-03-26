// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TestERC721 is ERC721Enumerable, Ownable {

    string public placeholderURI;

    constructor(
        string memory name,
        string memory symbol,
        string memory placeholderURI_
    ) ERC721(name, symbol) {
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
            _mint(to, tokenIds[i]);
        }
    }

}
