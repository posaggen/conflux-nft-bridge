import type { HardhatUserConfig, HttpNetworkUserConfig } from "hardhat/types";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import "@openzeppelin/hardhat-upgrades";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "hardhat-interface-generator";
import "hardhat-abi-exporter";

// environment configs
import dotenv from "dotenv";
dotenv.config();
const { NODE_URL, DEPLOYER_KEY, ETHERSCAN_API_KEY } = process.env;

// 0x0739857bc8892cdeba5f6d51cf095f25549c7554
const DEFAULT_DEPLOYER = "21c1db3dc75c2398838b1588f35403fd025cd15fcd27a785ba2c2aa5ea8e8069";

const userConfig: HttpNetworkUserConfig = {
    accounts: [DEPLOYER_KEY ? DEPLOYER_KEY : DEFAULT_DEPLOYER],
};

// tasks
import "./src/tasks/codesize";
import "./src/tasks/deploy_core";
import "./src/tasks/benchmark";

const config: HardhatUserConfig = {
    paths: {
        artifacts: "build/artifacts",
        cache: "build/cache",
        sources: "contracts",
        deploy: "src/deploy",
    },
    solidity: {
        compilers: [
            {
                version: "0.8.16",
                settings: {
                    evmVersion: "istanbul",
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        ],
    },
    networks: {
        hardhat: {
            allowUnlimitedContractSize: true,
            blockGasLimit: 100000000,
            gas: 100000000,
        },
        ConfluxCoreTestnet: {
            ...userConfig,
            url: "https://test.confluxrpc.com",
            chainId: 1,
        },
        ConfluxEvmTestnet: {
            ...userConfig,
            url: "https://evmtestnet.confluxrpc.com",
        },
        ConfluxCore: {
            ...userConfig,
            url: "https://main.confluxrpc.com",
            chainId: 1029,
        },
        ConfluxEvm: {
            ...userConfig,
            url: "https://evm.confluxrpc.com",
        },
    },
    namedAccounts: {
        deployer: 0,
    },
    mocha: {
        timeout: 2000000,
    },
    etherscan: {
        apiKey: ETHERSCAN_API_KEY,
    },
    gasReporter: {
        enabled: process.env.REPORT_GAS ? true : false,
    },
    abiExporter: {
        path: "./abis",
        runOnCompile: true,
        clear: true,
        flat: true,
        format: "json",
    },
};
if (NODE_URL && config.networks) {
    config.networks.custom = {
        ...userConfig,
        url: NODE_URL,
    };
}
export default config;
