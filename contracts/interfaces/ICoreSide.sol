// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ICoreRegistry.sol";

interface ICoreSide {
    /*=== events ===*/

    // emitted when cross NFT from core space (origin) to eSpace (pegged)
    event CrossToEvm(
        address indexed cfxToken,
        bytes20 evmToken,
        address cfxOperator,
        address indexed cfxFrom,
        bytes20 indexed evmTo,
        uint256[] ids,
        uint256[] amounts
    );

    // emitted when withdraw NFT from eSpace (pegged) to core space (origin)
    event WithdrawFromEvm(
        address indexed cfxToken,
        bytes20 evmToken,
        address indexed cfxAccount,
        address indexed cfxRecipient,
        uint256[] ids,
        uint256[] amounts
    );

    // emitted when cross NFT from eSpace (origin) to core space (pegged)
    event CrossFromEvm(
        address indexed cfxToken,
        bytes20 evmToken,
        address indexed cfxAccount,
        address indexed cfxRecipient,
        uint256[] ids,
        uint256[] amounts
    );

    // emitted when withdraw NFT from core space (pegged) to eSpace (origin)
    event WithdrawToEvm(
        address indexed cfxToken,
        bytes20 evmToken,
        address cfxOperator,
        address indexed cfxFrom,
        bytes20 indexed evmTo,
        uint256[] ids,
        uint256[] amounts
    );

    /*=== functions === */

    function crossFromEvm(address cfxToken, uint256[] memory ids, uint256[] memory amounts, address recipient) external;

    function evmSide() external view returns (bytes20);

    function registry() external view returns (ICoreRegistry);

    function withdrawFromEvm(
        bytes20 evmToken,
        uint256[] memory ids,
        uint256[] memory amounts,
        address recipient
    ) external;
}
