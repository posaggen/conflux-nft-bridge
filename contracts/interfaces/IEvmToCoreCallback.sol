// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IEvmToCoreCallback {
    function onEvmToCore(
        bytes20 evmToken,
        address cfxToken,
        uint256[] memory ids,
        uint256[] memory amounts,
        address recipient
    ) external returns (bytes4);
}
