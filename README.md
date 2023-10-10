# Conflux NFT Bridge
Allow users to cross NFT between core space and eSpace on Conflux network.

# Install

```bash
yarn
```

# Build

```bash
yarn build
```

## Deployment

- Deploy EVM space contracts:
```bash
yarn deploy <network_name>
```
- Deploy core space contracts:
```bash
yarn hardhat deploy:core --network <network_name>
```

## Deploy Pegged ERC721 Contracts
Generally, use factory method to deploy pegged NFT contracts. Note, deployer could specify both `name` and `symbol` to override the value in origin NFT contract.

- Pegged on eSpace: `CoreSide.deployEvm(address cfxToken, string memory name, string memory symbol)`.
- Pegged on core space: `CoreSide.deployCfx(bytes20 evmToken, string memory name, string memory symbol)`.
