import { HardhatRuntimeEnvironment } from "hardhat/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { ethers } from "ethers";
import * as fs from "fs";
import { Conflux } from "js-conflux-sdk";

export const CONTRACTS = {
    UpgradeableBeacon: "UpgradeableBeacon",
    BeaconProxy: "BeaconProxy",

    PeggedERC721: "PeggedERC721",
    PeggedERC1155: "PeggedERC1155",

    EvmSide: "EvmSide",
    EvmRegistry: "EvmRegistry",

    CoreSide: "CoreSide",
    CoreRegistry: "CoreRegistry",
};

export async function deployInBeaconProxy(hre: HardhatRuntimeEnvironment, contract: string, withProxy = true) {
    const { deployments, getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();
    const { deploy } = deployments;
    // deploy implementation
    await deploy(`${contract}Impl`, {
        from: deployer,
        contract: contract,
        args: [],
        log: true,
    });
    const implementation_ = await hre.ethers.getContract(`${contract}Impl`);
    // deploy beacon
    await deploy(`${contract}Beacon`, {
        from: deployer,
        contract: CONTRACTS.UpgradeableBeacon,
        args: [implementation_.address],
        log: true,
    });
    const beacon_ = await hre.ethers.getContract(`${contract}Beacon`);
    if (withProxy) {
        // deploy proxy
        await deploy(contract, {
            from: deployer,
            contract: CONTRACTS.BeaconProxy,
            args: [beacon_.address, []],
            log: true,
        });
    }
}

export async function getProxyContract(
    hre: HardhatRuntimeEnvironment,
    contract: string,
    signer: ethers.Signer | string
) {
    const address = (await hre.ethers.getContract(contract)).address;
    return hre.ethers.getContractAt(contract, address, signer);
}

export function toBytes(x: string) {
    if (x.startsWith("0x")) {
        x = x.substring(2);
    }
    return Buffer.from(x, "hex");
}

export function getCoreContracts(network: string, mustGet = false) {
    const path = `${__dirname}/../../deployments/${network}.json`;
    if (fs.existsSync(path)) {
        return JSON.parse(fs.readFileSync(path).toString());
    } else if (mustGet) {
        throw new Error(`no core space deployment found`);
    } else {
        return {};
    }
}

export function getEvmContracts(network: string) {
    let evmNetwork = "";
    if (network === "ConfluxCoreTestnet") {
        evmNetwork = "ConfluxEvmTestnet";
    } else if (network === "ConfluxCore") {
        evmNetwork = "ConfluxEvm";
    } else {
        throw new Error("no corresponding espace network found");
    }
    const path = `${__dirname}/../../deployments/${evmNetwork}`;
    const contractAddress: { [key: string]: string } = {};
    if (fs.existsSync(path)) {
        const files = fs.readdirSync(path);
        for (const file of files) {
            if (file.endsWith(".json")) {
                const name = file.slice(0, -5);
                const content = JSON.parse(fs.readFileSync(`${path}/${file}`).toString());
                if ("address" in content) {
                    contractAddress[name] = content.address;
                }
            }
        }
    } else {
        throw new Error("espace deployments not found");
    }
    return contractAddress;
}
