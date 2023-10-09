// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title NFT crossing from EVM to core space callback interface
 * @dev Interface for the NFT contract owner of orignal EVM space NFT to customize the NFT cross space
 * function.
 *
 * In this function, contract owners should implement the mint logic of NFT token on core space.
 */

interface IEvmToCoreCallback {
    /**
     * @param evmToken EVM space token address
     * @param cfxToken core space token address
     * @param ids token ids
     * @param amounts token amounts, always 1 for ERC721
     * @param recipient core space recipient
     * @dev It must return its Solidity selector to confirm the callback process.
     * If any other value is returned or the interface is not implemented by the recipient, the callback will be reverted.
     *
     * The selector can be obtained in Solidity with `IEvmToCoreCallback.onEvmToCore.selector`.
     */
    function onEvmToCore(
        bytes20 evmToken,
        address cfxToken,
        uint256[] memory ids,
        uint256[] memory amounts,
        address recipient
    ) external returns (bytes4);
}
