// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@confluxfans/contracts/InternalContracts/InternalContractsLib.sol";

contract PeggedERC721 is
    ERC721Enumerable,
    ERC721Burnable,
    ERC721Pausable,
    ERC721URIStorage,
    Initializable,
    AccessControlEnumerable
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // to support initialization out of constructor
    string private _name_;
    string private _symbol_;

    bytes20 public evmSide;

    constructor() ERC721("", "") {
        // no baseURL provided
    }

    // to support deployment behind a proxy
    function initialize(
        string memory name_,
        string memory symbol_,
        bytes20 evmSide_,
        address admin
    ) public {
        Initializable._initialize();

        _name_ = name_;
        _symbol_ = symbol_;

        evmSide = evmSide_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(MINTER_ROLE, msg.sender);
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

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
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

    function grantRole(bytes32 role, address account) public override onlyRole(getRoleAdmin(role)) {
        // to prevent invalid token minted in pegged contract
        require(role != MINTER_ROLE, "cannot grant MINTER_ROLE");

        super.grantRole(role, account);
    }

}
