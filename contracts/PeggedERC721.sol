// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PeggedNFT.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@confluxfans/contracts/InternalContracts/InternalContractsHandler.sol";
import "@confluxfans/contracts/InternalContracts/InternalContractsLib.sol";

/**
 * @dev Pegged NFT contracts that deployed on core space or eSpace via beacon proxy.
 */
contract PeggedERC721 is
    PeggedNFT,
    ERC721Enumerable,
    ERC721Burnable,
    ERC721Pausable,
    ERC721URIStorage
{
    constructor() ERC721("", "") {
    }

    function name() public view override returns (string memory) {
        return _name_;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol_;
    }

    function mint(address to, uint256 tokenId, string memory tokenURI_) public onlyRole(MINTER_ROLE) {
        _mint(to, tokenId);

        // Always set uri for each token, however:
        // 1) Could improve storage cost via baseURI or placeholder URI.
        // 2) Pegged NFT on core space could read URI from eSpace.
        if (bytes(tokenURI_).length > 0) {
            _setTokenURI(tokenId, tokenURI_);
        }
    }

    function tokenURI(uint256 tokenId) public view virtual override(ERC721, ERC721URIStorage) returns (string memory) {
        if (evmSide == bytes20(0)) {
            return ERC721URIStorage.tokenURI(tokenId);
        }

        // read token URI from eSpace for pegged token on core space
        bytes memory result = InternalContracts.CROSS_SPACE_CALL.staticCallEVM(evmSide,
            abi.encodeWithSelector(IERC721Metadata.tokenURI.selector, tokenId)
        );

        return abi.decode(result, (string));
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override(ERC721, ERC721Enumerable, ERC721Pausable) {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlEnumerable, ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _burn(uint256 tokenId) internal virtual override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

}
