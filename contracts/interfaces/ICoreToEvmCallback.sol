// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title NFT crossing from core to EVM space callback interface
 * @dev Interface for the NFT contract owner of orignal core space NFT to customize the NFT cross space
 * function.
 *
 * In this function, contract owners should implement the mint logic of NFT token on EVM space
 * by interaction with CrossSpaceCall internal contract.
 */

interface ICoreToEvmCallback {
    /**
     * @param cfxToken core space NFT token address
     * @param operator core space NFT token transfer operator
     * @param from cross chain from address
     * @param ids token ids
     * @param amounts token amounts, always 1 for ERC721
     * @param evmToken EVM space token address
     * @param recipient EVM space recipient
     * @dev It must return its Solidity selector to confirm the callback process.
     * If any other value is returned or the interface is not implemented by the recipient, the callback will be reverted.
     *
     * The selector can be obtained in Solidity with `ICoreToEvmCallback.onCoreToEvm.selector`.
     */
    function onCoreToEvm(
        address cfxToken,
        address operator,
        address from,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes20 evmToken,
        address recipient
    ) external returns (bytes4);
}
