// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICoreToEvmCallback {
    function onCoreToEvm(
        address cfxToken,
        address operator,
        address from,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes20 evmToken,
        address evmAccount
    ) external returns (bytes4);
}
