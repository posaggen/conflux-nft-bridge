// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IEvmRegistry.sol";

interface IEvmSide {
    /*=== events ===*/

    // emitted when user lock tokens for core space users to operate in advance
    event TokenLocked(
        address indexed evmToken,
        address evmOperator,
        address indexed evmFrom,
        address indexed cfxTo,
        uint256[] ids,
        uint256[] values
    );

    /*=== functions ===*/

    function burn(address evmToken, address cfxAccount, uint256[] memory ids, uint256[] memory amounts) external;

    function cfxSide() external view returns (address);

    function lockedTokens(
        address evmToken,
        address cfxAccount,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256 total, uint256[] memory tokenIds, uint256[] memory amounts);

    function mint(
        address evmToken,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        string[] memory uris
    ) external;

    function registry() external view returns (IEvmRegistry);

    function setCfxSide() external;

    function transfer(address evmToken, address to, uint256[] memory ids, uint256[] memory amounts) external;

    function unlock(address evmToken, address cfxAccount, uint256[] memory ids, uint256[] memory amounts) external;
}
