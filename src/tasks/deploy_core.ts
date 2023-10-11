import "@nomiclabs/hardhat-ethers";
import "hardhat-conflux";
import { task, types } from "hardhat/config";
import { Conflux, PrivateKeyAccount } from "js-conflux-sdk";
import { CONTRACTS, getCoreContracts, getEvmContracts, toBytes } from "../utils/utils";
import * as fs from "fs";

async function deploy(
    conflux: Conflux,
    deployer: PrivateKeyAccount,
    name: string,
    contract: string,
    args: unknown[],
    contractAddress: { [key: string]: string },
    skip: boolean
) {
    if (skip && name in contractAddress) {
        console.log(`reusing ${name} contract at ${contractAddress[name]}..`);
        return;
    }
    const factory = await conflux.getContractFactory(contract);
    console.log(`deploying ${name}..`);
    const receipt = await factory
        .constructor(...args)
        .sendTransaction({
            from: deployer.address,
        })
        .executed();
    contractAddress[name] = receipt.contractCreated;
    console.log(`New deployed ${name} address: ${receipt.contractCreated}.`);
}

async function deployInProxy(
    conflux: Conflux,
    contract: string,
    deployer: PrivateKeyAccount,
    contractAddress: { [key: string]: string },
    skip: boolean,
    withProxy = true
) {
    // impl
    await deploy(conflux, deployer, `${contract}Impl`, contract, [], contractAddress, skip);
    // beacon
    await deploy(
        conflux,
        deployer,
        `${contract}Beacon`,
        CONTRACTS.UpgradeableBeacon,
        [contractAddress[`${contract}Impl`]],
        contractAddress,
        skip
    );
    if (withProxy) {
        // deploy proxy
        await deploy(
            conflux,
            deployer,
            contract,
            CONTRACTS.BeaconProxy,
            [contractAddress[`${contract}Beacon`], []],
            contractAddress,
            skip
        );
    }
}

task("deploy:core", "deploy core space contracts")
    .addParam("skip", "skip deployed", true, types.boolean, true)
    .setAction(async (taskArgs, hre) => {
        const conflux = hre.conflux;
        const signers = await conflux.getSigners();
        const deployer = signers[0];

        const contractAddress: { [key: string]: string } = getCoreContracts(hre.network.name);
        const evmContractAddress = getEvmContracts(hre.network.name);

        // pegged ERC721
        await deployInProxy(conflux, CONTRACTS.PeggedERC721, deployer, contractAddress, taskArgs.skip, false);
        // pegged ERC1155
        await deployInProxy(conflux, CONTRACTS.PeggedERC1155, deployer, contractAddress, taskArgs.skip, false);
        // deploy core registry
        await deployInProxy(conflux, CONTRACTS.CoreRegistry, deployer, contractAddress, taskArgs.skip);
        // initialize core registry
        console.log(`initializing core registry..`);
        const coreRegistry_ = await conflux.getContractAt(
            CONTRACTS.CoreRegistry,
            contractAddress[CONTRACTS.CoreRegistry]
        );
        if (!(await coreRegistry_.initialized())) {
            await coreRegistry_
                .initialize(
                    toBytes(evmContractAddress[CONTRACTS.EvmRegistry]),
                    contractAddress[`${CONTRACTS.PeggedERC721}Beacon`],
                    contractAddress[`${CONTRACTS.PeggedERC1155}Beacon`]
                )
                .sendTransaction({
                    from: deployer.address,
                })
                .executed();
        }
        // deploy core side
        await deployInProxy(conflux, CONTRACTS.CoreSide, deployer, contractAddress, taskArgs.skip);
        // initialize core side
        console.log(`initializing core side..`);
        const coreSide_ = await conflux.getContractAt(CONTRACTS.CoreSide, contractAddress[CONTRACTS.CoreSide]);
        if (!(await coreSide_.initialized())) {
            await coreSide_
                .initialize(contractAddress[CONTRACTS.CoreRegistry], toBytes(evmContractAddress[CONTRACTS.EvmSide]))
                .sendTransaction({
                    from: deployer.address,
                })
                .executed();
            await coreRegistry_.setBridge(coreSide_.address).sendTransaction({ from: deployer.address }).executed();
        }
        // deploy test token factory & callbacks
        if (hre.network.name == "ConfluxCoreTestnet") {
            await deploy(
                conflux,
                deployer,
                CONTRACTS.TestTokenFactory,
                CONTRACTS.TestTokenFactory,
                [],
                contractAddress,
                taskArgs.skip
            );
            await deploy(
                conflux,
                deployer,
                CONTRACTS.TestCoreToEvmCallback,
                CONTRACTS.TestCoreToEvmCallback,
                [coreSide_.address],
                contractAddress,
                taskArgs.skip
            );
            await deploy(
                conflux,
                deployer,
                CONTRACTS.TestEvmToCoreCallback,
                CONTRACTS.TestEvmToCoreCallback,
                [coreSide_.address],
                contractAddress,
                taskArgs.skip
            );
        }
        // write to file
        const outputFile = `${__dirname}/../../deployments/${hre.network.name}.json`;
        fs.writeFileSync(outputFile, JSON.stringify(contractAddress, null, 2));
    });
