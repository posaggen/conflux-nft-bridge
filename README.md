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

# Deployment

- Deploy EVM space contracts:
```bash
yarn deploy <network_name>
```
- Deploy core space contracts:
```bash
yarn hardhat deploy:core --network <network_name>
```

# Developer Docs

- [Transfer NFT between conflux core space and eSpace](docs/cross_space.md)

- [Cross Space Token Mappings](docs/token_mapping.md)
