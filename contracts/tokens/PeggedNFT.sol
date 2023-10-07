// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../utils/Initializable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@confluxfans/contracts/InternalContracts/InternalContractsHandler.sol";

abstract contract PeggedNFT is Initializable, AccessControlEnumerable, Pausable, InternalContractsHandler {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // to support initialization out of constructor
    string internal _name_;
    string internal _symbol_;

    // used on core space to read token URI from eSpace
    bytes20 public evmSide;

    // to support deployment behind a proxy
    function initialize(
        string memory name_,
        string memory symbol_,
        bytes20 evmSide_,
        address admin
    ) public virtual onlyInitializeOnce {
        _name_ = name_;
        _symbol_ = symbol_;

        evmSide = evmSide_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function grantRole(bytes32 role, address account) public override onlyRole(getRoleAdmin(role)) {
        // to prevent invalid token minted by admin in pegged contract
        require(role != MINTER_ROLE, "cannot grant MINTER_ROLE");

        super.grantRole(role, account);
    }
}
