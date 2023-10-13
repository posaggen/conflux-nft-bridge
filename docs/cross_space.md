- [Initiate Cross Space Transfer](#initiate-cross-space-transfer)
  - [Single Transfer](#single-transfer)
  - [Batch Transfer](#batch-transfer)
    - [ERC1155](#erc1155)
    - [ERC721](#erc721)
- [Transfer Original Core Space NFT to eSpace](#transfer-original-core-space-nft-to-espace)
- [Transfer Original Core Space NFT from eSpace Back to Core Space](#transfer-original-core-space-nft-from-espace-back-to-core-space)
- [Transfer Original eSpace NFT to Core Space](#transfer-original-espace-nft-to-core-space)
- [Transfer Original eSpace NFT from Core Space Back to eSpace](#transfer-original-espace-nft-from-core-space-back-to-espace)

# Initiate Cross Space Transfer

To transfer NFT between spaces, users need to transfer their nfts to bridge contract on different spaces, i.e. `CoreSide` contract on core space and `EvmSide` on eSpace.

When users want to initiate a cross space transfer, they just need to send their NFTs to the bridge contract on the source space, and the NFT must follow `ERC721` or `ERC1155` standard.

## Single Transfer

Call `safeTransferFrom` of `ERC721` or `ERC1155` contract, fill the destination space recipient address(in 20-bytes hex format) in the `data` field.

## Batch Transfer

### ERC1155

Call `safeBatchTransferFrom`, fill the destination space recipient address(in 20-bytes hex format) in the `data` field.

### ERC721

1. Give approval to the bridge contract through `approve` or `setApprovalForAll`.
2. Call `safeBatchTransferFrom` of the bridge contract, fill the destination space recipient address(in 20-bytes hex format) in the `data` field.

# Transfer Original Core Space NFT to eSpace

Initiate the cross space transfer on core space, the cross space transfer is done in the same transaction.

# Transfer Original Core Space NFT from eSpace Back to Core Space

Initiate the cross space transfer on eSpace, then use the recipient account to call `withdrawFromEvm` function of `CoreSide` contract on core space. 

# Transfer Original eSpace NFT to Core Space

Initiate the cross space transfer on eSpace, then use the recipient account to call `crossFromEvm` function of `CoreSide` contract on core space. 


# Transfer Original eSpace NFT from Core Space Back to eSpace

Initiate the cross space transfer on core space, the cross space transfer is done in the same transaction.


