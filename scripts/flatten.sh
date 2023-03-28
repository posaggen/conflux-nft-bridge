#!/bin/bash

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/.. && pwd )"

cd $ROOT_DIR

mkdir -p flatten

npx hardhat flatten ./contracts/PeggedERC721.sol > flatten/PeggedERC721.sol
npx hardhat flatten ./contracts/PeggedERC1155.sol > flatten/PeggedERC1155.sol
npx hardhat flatten ./contracts/EvmSide.sol > flatten/EvmSide.sol
npx hardhat flatten ./contracts/CoreSide.sol > flatten/CoreSide.sol
npx hardhat flatten ./contracts/TestToken.sol > flatten/TestToken.sol
