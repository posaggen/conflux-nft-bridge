# Conflux NFT Bridge
Allow users to cross NFT between core space and eSpace on Conflux network.

## Deployment
Deploy following contracts in sequence:

- Deploy `PeggedERC721` with `beacon` on **eSpace**.
- Deploy `EvmSide` with `beacon & proxy` on **eSpace**, and **initialize** with PeggedERC721 beacon.
- Deploy `CoreSide` with `beacon & proxy` on **core space**, and **initialize** with `EvmSide` and PeggedERC721 beacon.

## Deploy Pegged ERC721 Contracts
Generally, use factory method to deploy pegged NFT contracts. Note, deployer could specify both `name` and `symbol` to override the value in origin NFT contract.

- Pegged on eSpace: `CoreSide.deployEvm(address cfxToken, string memory name, string memory symbol)`.
- Pegged on core space: `CoreSide.deployCfx(bytes20 evmToken, string memory name, string memory symbol)`.
