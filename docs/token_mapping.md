- [Create Cross Space Token Mapping](#create-cross-space-token-mapping)
  - [Create Pegged Token by Template](#create-pegged-token-by-template)
    - [Original Core Space NFT](#original-core-space-nft)
    - [Original eSpace NFT](#original-espace-nft)
  - [Create Pegged Token by Contract Owner or Bridge Admin](#create-pegged-token-by-contract-owner-or-bridge-admin)
    - [Set/Unset Pegged Token of Original Core Space NFT](#setunset-pegged-token-of-original-core-space-nft)
    - [Set/UnsetPegged Token of Original eSpace NFT](#setunsetpegged-token-of-original-espace-nft)
  - [Customize Cross Space Transfer](#customize-cross-space-transfer)
    - [Set Callback For Original Core Space NFT](#set-callback-for-original-core-space-nft)
    - [Set Callback For Original eSpace NFT](#set-callback-for-original-espace-nft)
- [Read Token Mapping from Bridge Contract](#read-token-mapping-from-bridge-contract)
  - [Original Core Space Tokens](#original-core-space-tokens)
  - [Pegged Tokens of Original Core Space Tokens](#pegged-tokens-of-original-core-space-tokens)
  - [Original Evm Space Tokens](#original-evm-space-tokens)
  - [Pegged Tokens of Original eSpace Tokens](#pegged-tokens-of-original-espace-tokens)


# Create Cross Space Token Mapping

For an original NFT contract deployed on a space, it must have another NFT contract on the other space which is established a 1:1 mapping with it. We call this mapped NFT **pegged token** and the original NFT **original token**. If a token is already a pegged token of another token, it can't be an original token.

The nft cross space bridge provides two options to create pegged token for an original token.

All NFT should follow `ERC721` or `ERC1155` standard and implements [ERC721Burnable](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.8.0/contracts/token/ERC721/extensions/ERC721Burnable.sol) or [ERC1155Burnable](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.8.0/contracts/token/ERC1155/extensions/ERC1155Burnable.sol) to make the bridge work properly.

## Create Pegged Token by Template

For convenience, if an original token does not have any pegged token yet, **anyone** is able to deploy a pegged token for it on the other space.

Pegged tokens deployed in this way will use given template: [PeggedERC721](/contracts/tokens/PeggedERC721.sol) and [PeggedERC1155](/contracts/tokens/PeggedERC1155.sol). These template contract uses beacon-proxy upgradeable pattern.

### Original Core Space NFT

To create a template pegged token for an original token on core space:
1. Register the deployment of pegged token, pass the original token metadata to eSpace by calling `registerDeployEvm` of `CoreRegistry`.
2. Call `deploy` of `EvmSide` to deploy the pegged token on eSpace.
3. Call `updateDeployed` of `CoreRegistry` to load the deployed pegged token information to core space.

### Original eSpace NFT

To create a template pegged token for an original token on eSpace: call `deployCfx` of `CoreRegistry`.

## Create Pegged Token by Contract Owner or Bridge Admin

In case some NFT contract owner want have their own pegged token implementation on the other space, the NFT contract owner and the bridge admin are able to set the pegged token for an original token, even if there is already a template pegged token deployed. They are also able to unset the token mapping.

If an orignial token has both a template pegged token and a pegged token set by owner, the latter always has higher priority at cross space transfer, i.e. the template pegged token will be deprecated.

### Set/Unset Pegged Token of Original Core Space NFT 

Call `registerEvm` or `unregisterEvm` of `CoreRegistry`, the sender should be the owner of NFT or bridge admin.

### Set/UnsetPegged Token of Original eSpace NFT 

Call `registerCfx` or `unregisterCfx` of `CoreRegistry`, the sender should be the core space operator of original NFT or bridge admin.

To set a core space address to the operator of an eSpace NFT, call `approve` of `EvmSide`, the sender should be the owner of NFT or bridge admin.

## Customize Cross Space Transfer

In cross transfer of an original NFT to the other space, the pegged token will be minted with default mint functions:

ERC721:
```solidity
function mint(address to, uint256 tokenId, string memory tokenURI_)
```
ERC1155:
```solidity
function mint(address to, uint256 id, uint256 amount, string memory uri_)

function mintBatch(
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    string[] memory uris
) 
```

However, this logic may not sufficient. The bridge contract allows NFT contract owner use a callback contract which implements their own cross space mint function. The callback functions must implement [ICoreToEvmcallback](/contracts/interfaces/ICoreToEvmCallback.sol) or [IEvmToCoreCallback](/contracts/interfaces/IEvmToCoreCallback.sol). At the time bridge mint the pegged token, if a callback contract is set, the bridge will trigger the callback instead of the default mint function.

### Set Callback For Original Core Space NFT

Call `setCore2EvmCallback` of `CoreRegistry`, the sender should be the owner of NFT or bridge admin.

### Set Callback For Original eSpace NFT

Call `setEvm2CoreCallback` of `CoreRegistry`, the sender should be the core space operator of original NFT or bridge admin.

# Read Token Mapping from Bridge Contract

All the token mappings are stored in `CoreRegistry` and `EvmRegistry` contract.

## Original Core Space Tokens

`CoreRegistry` provides a paginable interface:
```solidity
function cfxTokens(uint256 offset, uint256 limit) public view returns (uint256 total, address[] memory tokens)
```

## Pegged Tokens of Original Core Space Tokens

In `CoreRegistry` contract:

Template pegged tokens:
```solidity
mapping(address => bytes20) public core2EvmTokens;
```

Pegged tokens set by owner:
```solidity
mapping(address => bytes20) public registeredCore2EvmTokens;
```

Original token of a pegged token:
```solidity
mapping(bytes20 => address) public peggedEvm2CoreTokens;
```

## Original Evm Space Tokens

`EvmRegistry` provides a paginable interface:
```solidity
function evmTokens(uint256 offset, uint256 limit) public view returns (uint256 total, address[] memory tokens)
```

## Pegged Tokens of Original eSpace Tokens

In `CoreRegistry` contract:

Template pegged tokens:
```solidity
mapping(address => bytes20) public core2EvmTokens;
```

Pegged tokens set by owner:
```solidity
mapping(address => bytes20) public registeredCore2EvmTokens;
```

Original token of a pegged token:
```solidity
mapping(bytes20 => address) public evm2CoreTokens;
```

Pegged tokens set by owner:
```solidity
mapping(bytes20 => address) public registeredEvm2CoreTokens;
```

Original token of a pegged token:
```solidity
mapping(address => bytes20) public peggedCore2EvmTokens;
```
