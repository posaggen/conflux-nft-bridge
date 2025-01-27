import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { task, types } from "hardhat/config";
import { Conflux, Contract, PrivateKeyAccount, format } from "js-conflux-sdk";
import { CONTRACTS, getCoreContracts, getEvmContracts, getProxyContract, toBytes } from "../utils/utils";
import * as fs from "fs";
import { ethers } from "ethers";

import dotenv from "dotenv";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { expect } from "chai";
dotenv.config();
const { DEPLOYER_KEY } = process.env;

let coreContractAddress: { [key: string]: string };
let evmNetwork: string;
let coreNetwork: string;
let coreDeployer: PrivateKeyAccount;
let coreSide: Contract;
let coreRegistry: Contract;
let coreTestTokenFactory: Contract;
let coreToEvmCallback: Contract;
let evmToCoreCallback: Contract;
let evmDeployer: string;
let evmSide: ethers.Contract;
let evmRegistry: ethers.Contract;
let evmTestTokenFactory: ethers.Contract;

const abiPath = `${__dirname}/../../build/artifacts/contracts`;

const conflux = new Conflux({
    url: "https://test.confluxrpc.com",
    networkId: 1,
});

function loadAbi(path: string) {
    const content = JSON.parse(fs.readFileSync(path).toString());
    return content.abi;
}

function mirrorAddress(addr: string) {
    const x = ethers.utils.keccak256(format.hexAddress(addr));
    return "0x" + x.slice(-40, x.length);
}

async function checkLocked(evmToken: string, cfxAccount: string, total: number, ids: number[], amounts: number[]) {
    const locked = await evmSide.lockedTokens(evmToken, cfxAccount, 0, 100);
    expect(locked.total).to.deep.eq(total);
    expect(locked.tokenIds).to.deep.eq(ids);
    expect(locked.amounts).to.deep.eq(amounts);
}

async function shouldFail(x: unknown, msg: string) {
    try {
        await x;
    } catch (e) {
        if (!e.toString().includes(msg)) {
            throw new Error(`unexpected error msg: ${e}, expected: ${msg}`);
        }
        return;
    }
    throw new Error(`no error occured. should throw: ${msg}`);
}

async function erc721FromCoreToEvm(hre: HardhatRuntimeEnvironment) {
    console.log("running erc721FromCoreToEvm:");
    // deploy ERC721 token on core space
    await coreTestTokenFactory
        .deploy721("Core721", "Core721", "TEST 721 TOKEN ON CORE SPACE")
        .sendTransaction({
            from: coreDeployer,
        })
        .executed();
    const core721 = conflux.Contract({
        abi: loadAbi(`${abiPath}/test/TestToken.sol/TestERC721.json`),
        address: await coreTestTokenFactory.latestDeployed(),
    });
    console.log(`core ERC721 deployed: ${core721.address}.`);
    // deploy pegged token on eSpace
    await coreRegistry.registerDeployEvm(core721.address).sendTransaction({ from: coreDeployer }).executed();
    await (await evmRegistry.deploy(format.hexAddress(core721.address))).wait();
    await coreRegistry.updateDeployed(core721.address).sendTransaction({ from: coreDeployer }).executed();
    const deployments = await evmRegistry.deployments(format.hexAddress(core721.address));
    const peggedAddress = (await coreRegistry.core2EvmTokens(core721.address)).toString("hex");
    expect(deployments.deployed.substring(2).toLowerCase()).to.deep.eq(peggedAddress);
    const evmPegged721 = await hre.ethers.getContractAt(CONTRACTS.PeggedERC721, deployments.deployed, evmDeployer);
    console.log(`espace pegged ERC721 deployed: ${deployments.deployed}.`);
    // mint 5 nft to deployer
    await core721.mint(coreDeployer.address, [0, 1, 2, 3, 4, 5]).sendTransaction({ from: coreDeployer }).executed();
    console.log(`core721 minted.`);
    // cross nft #0 to eSpace
    await core721
        .safeTransferFrom(coreDeployer.address, coreSide.address, 0, toBytes(evmDeployer))
        .sendTransaction({ from: coreDeployer })
        .executed();
    expect(await core721.ownerOf(0)).to.deep.eq(coreSide.address);
    expect(await evmPegged721.ownerOf(0)).to.deep.eq(evmDeployer);
    console.log(`NFT #0 transferred to eSpace.`);
    // cross nft #0 to core space
    await (
        await evmPegged721["safeTransferFrom(address,address,uint256,bytes)"](
            evmDeployer,
            evmSide.address,
            0,
            format.hexAddress(coreDeployer.address)
        )
    ).wait();
    await checkLocked(evmPegged721.address, format.hexAddress(coreDeployer.address), 1, [0], [1]);
    await coreSide
        .withdrawFromEvm(toBytes(evmPegged721.address), [0], [1], coreDeployer.address)
        .sendTransaction({ from: coreDeployer })
        .executed();
    await checkLocked(evmPegged721.address, format.hexAddress(coreDeployer.address), 0, [], []);
    expect(await core721.ownerOf(0)).to.deep.eq(coreDeployer.address);
    await expect(evmPegged721.ownerOf(0)).to.eventually.be.rejectedWith("ERC721: invalid token ID");
    console.log(`NFT #0 transferred to core space.`);
    // batch cross nft #1,#2,#3 to eSpace
    await core721.setApprovalForAll(coreSide.address, true).sendTransaction({ from: coreDeployer }).executed();
    await coreSide
        .safeBatchTransferFrom(core721.address, [1, 2, 3], toBytes(evmDeployer))
        .sendTransaction({ from: coreDeployer })
        .executed();
    for (let i = 1; i <= 3; ++i) {
        expect(await core721.ownerOf(i)).to.deep.eq(coreSide.address);
        expect(await evmPegged721.ownerOf(i)).to.deep.eq(evmDeployer);
    }
    console.log(`NFT #1,2,3 batch transferred to eSpace.`);
    // batch cross nft #1,#2 to core space
    await (await evmPegged721.setApprovalForAll(evmSide.address, true)).wait();
    await (
        await evmSide.safeBatchTransferFrom(evmPegged721.address, [1, 2], format.hexAddress(coreDeployer.address))
    ).wait();
    await checkLocked(evmPegged721.address, format.hexAddress(coreDeployer.address), 2, [1, 2], [1, 1]);
    await coreSide
        .withdrawFromEvm(toBytes(evmPegged721.address), [1, 2], [1, 1], coreDeployer.address)
        .sendTransaction({ from: coreDeployer })
        .executed();
    await checkLocked(evmPegged721.address, format.hexAddress(coreDeployer.address), 0, [], []);
    for (let i = 1; i <= 2; ++i) {
        expect(await core721.ownerOf(i)).to.deep.eq(coreDeployer.address);
        await expect(evmPegged721.ownerOf(i)).to.eventually.be.rejectedWith("ERC721: invalid token ID");
    }
    console.log(`NFT #1,2 batch transferred to core space.`);
    // deploy evm721
    await (await evmTestTokenFactory.deploy721("Core721", "Core721", "TEST 721 TOKEN ON CORE SPACE")).wait();
    const evm721 = await hre.ethers.getContractAt(
        CONTRACTS.TestERC721,
        await evmTestTokenFactory.latestDeployed(),
        evmDeployer
    );
    await (await evm721.transferOwnership(mirrorAddress(coreToEvmCallback.address))).wait();
    console.log(`evm ERC721 deployed: ${evm721.address}.`);
    // register evm721
    await coreRegistry
        .registerEvm(core721.address, toBytes(evm721.address))
        .sendTransaction({ from: coreDeployer })
        .executed();
    // cross nft #3 to core space
    await (
        await evmPegged721["safeTransferFrom(address,address,uint256,bytes)"](
            evmDeployer,
            evmSide.address,
            3,
            format.hexAddress(coreDeployer.address)
        )
    ).wait();
    await checkLocked(evmPegged721.address, format.hexAddress(coreDeployer.address), 1, [3], [1]);
    await coreSide
        .withdrawFromEvm(toBytes(evmPegged721.address), [3], [1], coreDeployer.address)
        .sendTransaction({ from: coreDeployer })
        .executed();
    await checkLocked(evmPegged721.address, format.hexAddress(coreDeployer.address), 0, [], []);
    expect(await core721.ownerOf(3)).to.deep.eq(coreDeployer.address);
    await expect(evmPegged721.ownerOf(3)).to.eventually.be.rejectedWith("ERC721: invalid token ID");
    console.log(`NFT #3 transferred to core space.`);
    // unregister evmPegged721
    await coreRegistry.unregisterEvm(toBytes(evmPegged721.address)).sendTransaction({ from: coreDeployer }).executed();
    console.log(`evm pegged 721 unregistered.`);
    // set callback
    await coreRegistry
        .setCore2EvmCallback(core721.address, coreToEvmCallback.address)
        .sendTransaction({ from: coreDeployer })
        .executed();
    console.log(`core to evm callback set.`);
    // cross nft #4 to eSpace
    await core721
        .safeTransferFrom(coreDeployer.address, coreSide.address, 4, toBytes(evmDeployer))
        .sendTransaction({ from: coreDeployer })
        .executed();
    expect(await core721.ownerOf(4)).to.deep.eq(coreSide.address);
    expect(await evm721.ownerOf(4)).to.deep.eq(evmDeployer);
    console.log(`NFT #4 transferred to eSpace.`);
    // cross nft #4 to core space
    await (
        await evm721["safeTransferFrom(address,address,uint256,bytes)"](
            evmDeployer,
            evmSide.address,
            4,
            format.hexAddress(coreDeployer.address)
        )
    ).wait();
    await checkLocked(evm721.address, format.hexAddress(coreDeployer.address), 1, [4], [1]);
    await coreSide
        .withdrawFromEvm(toBytes(evm721.address), [4], [1], coreDeployer.address)
        .sendTransaction({ from: coreDeployer })
        .executed();
    await checkLocked(evm721.address, format.hexAddress(coreDeployer.address), 0, [], []);
    expect(await core721.ownerOf(4)).to.deep.eq(coreDeployer.address);
    await expect(evm721.ownerOf(4)).to.eventually.be.rejectedWith("ERC721: invalid token ID");
    console.log(`NFT #4 transferred to core space.`);
}

async function erc721FromEvmToCore(hre: HardhatRuntimeEnvironment) {
    // deploy evm721
    await (await evmTestTokenFactory.deploy721("Evm721", "Evm721", "TEST 721 TOKEN ON EVM SPACE")).wait();
    const evm721 = await hre.ethers.getContractAt(
        CONTRACTS.TestERC721,
        await evmTestTokenFactory.latestDeployed(),
        evmDeployer
    );
    console.log(`evm ERC721 deployed: ${evm721.address}.`);
    // deploy pegged token on core space
    await coreRegistry.deployCfx(toBytes(evm721.address)).sendTransaction({ from: coreDeployer }).executed();
    const corePegged721 = conflux.Contract({
        abi: loadAbi(`${abiPath}/tokens/PeggedERC721.sol/PeggedERC721.json`),
        address: await coreRegistry.evm2CoreTokens(toBytes(evm721.address)),
    });
    console.log(`pegged core ERC721 deployed: ${corePegged721.address}`);
    // mint 5 nft to deployer
    await (await evm721.mint(evmDeployer, [0, 1, 2, 3, 4, 5])).wait();
    console.log(`evm721 minted.`);
    // cross nft #0 to core space
    await (
        await evm721["safeTransferFrom(address,address,uint256,bytes)"](
            evmDeployer,
            evmSide.address,
            0,
            format.hexAddress(coreDeployer.address)
        )
    ).wait();
    await checkLocked(evm721.address, format.hexAddress(coreDeployer.address), 1, [0], [1]);
    await coreSide
        .crossFromEvm(corePegged721.address, [0], [1], coreDeployer.address)
        .sendTransaction({ from: coreDeployer })
        .executed();
    await checkLocked(evm721.address, format.hexAddress(coreDeployer.address), 0, [], []);
    expect(await evm721.ownerOf(0)).to.deep.eq(evmSide.address);
    expect(await corePegged721.ownerOf(0)).to.deep.eq(coreDeployer.address);
    console.log(`NFT #0 transferred to core space.`);
    // cross nft #0 to eSpace
    await corePegged721
        .safeTransferFrom(coreDeployer.address, coreSide.address, 0, toBytes(evmDeployer))
        .sendTransaction({ from: coreDeployer })
        .executed();
    await shouldFail(corePegged721.ownerOf(0), "ERC721: invalid token ID");
    expect(await evm721.ownerOf(0)).to.deep.eq(evmDeployer);
    console.log(`NFT #0 transferred to eSpace.`);
    // batch cross nft #1,#2,#3 to core space
    await (await evm721.setApprovalForAll(evmSide.address, true)).wait();
    await (
        await evmSide.safeBatchTransferFrom(evm721.address, [1, 2, 3], format.hexAddress(coreDeployer.address))
    ).wait();
    await coreSide
        .crossFromEvm(corePegged721.address, [1, 2, 3], [1, 1, 1], coreDeployer.address)
        .sendTransaction({ from: coreDeployer })
        .executed();
    for (let i = 1; i <= 3; ++i) {
        expect(await evm721.ownerOf(i)).to.deep.eq(evmSide.address);
        expect(await corePegged721.ownerOf(i)).to.deep.eq(coreDeployer.address);
    }
    console.log(`NFT #1,2,3 batch transferred to core space.`);
    // batch cross nft #1,#2 to evm space
    await corePegged721.setApprovalForAll(coreSide.address, true).sendTransaction({ from: coreDeployer }).executed();
    await coreSide
        .safeBatchTransferFrom(corePegged721.address, [1, 2], toBytes(evmDeployer))
        .sendTransaction({ from: coreDeployer })
        .executed();
    for (let i = 1; i <= 2; ++i) {
        expect(await evm721.ownerOf(i)).to.deep.eq(evmDeployer);
        await shouldFail(corePegged721.ownerOf(i), "ERC721: invalid token ID");
    }
    console.log(`NFT #1,2 batch transferred to eSpace.`);
    // deploy core721
    await coreTestTokenFactory
        .deploy721("Evm721", "Evm721", "TEST 721 TOKEN ON EVM SPACE")
        .sendTransaction({
            from: coreDeployer,
        })
        .executed();
    const core721 = conflux.Contract({
        abi: loadAbi(`${abiPath}/test/TestToken.sol/TestERC721.json`),
        address: await coreTestTokenFactory.latestDeployed(),
    });
    await core721.transferOwnership(evmToCoreCallback.address).sendTransaction({ from: coreDeployer }).executed();
    console.log(`core ERC721 deployed: ${core721.address}.`);
    // register core721
    await coreRegistry
        .registerCfx(toBytes(evm721.address), core721.address)
        .sendTransaction({ from: coreDeployer })
        .executed();
    // cross nft #3 to eSpace
    await corePegged721
        .safeTransferFrom(coreDeployer.address, coreSide.address, 3, toBytes(evmDeployer))
        .sendTransaction({ from: coreDeployer })
        .executed();
    await shouldFail(corePegged721.ownerOf(3), "ERC721: invalid token ID");
    expect(await evm721.ownerOf(3)).to.deep.eq(evmDeployer);
    console.log(`NFT #3 transferred to eSpace.`);
    // unregister corePegged721
    await coreRegistry.unregisterCfx(corePegged721.address).sendTransaction({ from: coreDeployer }).executed();
    console.log(`core pegged 721 unregistered.`);
    // set callback
    await coreRegistry
        .setEvm2CoreCallback(core721.address, evmToCoreCallback.address)
        .sendTransaction({ from: coreDeployer })
        .executed();
    console.log(`evm to core callback set.`);
    // cross nft #4 to core space
    await (
        await evm721["safeTransferFrom(address,address,uint256,bytes)"](
            evmDeployer,
            evmSide.address,
            4,
            format.hexAddress(coreDeployer.address)
        )
    ).wait();
    await checkLocked(evm721.address, format.hexAddress(coreDeployer.address), 1, [4], [1]);
    await coreSide
        .crossFromEvm(core721.address, [4], [1], coreDeployer.address)
        .sendTransaction({ from: coreDeployer })
        .executed();
    await checkLocked(evm721.address, format.hexAddress(coreDeployer.address), 0, [], []);
    expect(await evm721.ownerOf(4)).to.deep.eq(evmSide.address);
    expect(await core721.ownerOf(4)).to.deep.eq(coreDeployer.address);
    console.log(`NFT #4 transferred to core space.`);
    // cross nft #4 to eSpace
    await core721
        .safeTransferFrom(coreDeployer.address, coreSide.address, 4, toBytes(evmDeployer))
        .sendTransaction({ from: coreDeployer })
        .executed();
    await shouldFail(core721.ownerOf(4), "ERC721: invalid token ID");
    expect(await evm721.ownerOf(4)).to.deep.eq(evmDeployer);
    console.log(`NFT #4 transferred to eSpace.`);
}

async function erc1155FromCoreToEvm(hre: HardhatRuntimeEnvironment) {
    console.log("running erc1155FromCoreToEvm:");
    // deploy ERC1155 token on core space
    await coreTestTokenFactory
        .deploy1155("Core1155", "Core1155", "TEST 1155 TOKEN ON CORE SPACE")
        .sendTransaction({
            from: coreDeployer,
        })
        .executed();
    const core1155 = conflux.Contract({
        abi: loadAbi(`${abiPath}/test/TestToken.sol/TestERC1155.json`),
        address: await coreTestTokenFactory.latestDeployed(),
    });
    console.log(`core ERC1155 deployed: ${core1155.address}.`);
    // deploy pegged token on eSpace
    await coreRegistry.registerDeployEvm(core1155.address).sendTransaction({ from: coreDeployer }).executed();
    await (await evmRegistry.deploy(format.hexAddress(core1155.address))).wait();
    await coreRegistry.updateDeployed(core1155.address).sendTransaction({ from: coreDeployer }).executed();
    const deployments = await evmRegistry.deployments(format.hexAddress(core1155.address));
    const peggedAddress = (await coreRegistry.core2EvmTokens(core1155.address)).toString("hex");
    expect(deployments.deployed.substring(2).toLowerCase()).to.deep.eq(peggedAddress);
    const evmPegged1155 = await hre.ethers.getContractAt(CONTRACTS.PeggedERC1155, deployments.deployed, evmDeployer);
    console.log(`espace pegged ERC1155 deployed: ${deployments.deployed}.`);
    // mint 5 nft to deployer
    await core1155
        .mint(coreDeployer.address, [0, 1, 2, 3, 4, 5], [1, 2, 3, 4, 5, 6])
        .sendTransaction({ from: coreDeployer })
        .executed();
    console.log(`core1155 minted.`);
    // cross nft #0 to eSpace
    await core1155
        .safeTransferFrom(coreDeployer.address, coreSide.address, 0, 1, toBytes(evmDeployer))
        .sendTransaction({ from: coreDeployer })
        .executed();
    expect(await core1155.balanceOf(coreSide.address, 0)).to.deep.eq(1);
    expect(await evmPegged1155.balanceOf(evmDeployer, 0)).to.deep.eq(1);
    console.log(`NFT #0 transferred to eSpace.`);
    // cross nft #0 to core space
    await (
        await evmPegged1155["safeTransferFrom(address,address,uint256,uint256,bytes)"](
            evmDeployer,
            evmSide.address,
            0,
            1,
            format.hexAddress(coreDeployer.address)
        )
    ).wait();
    await checkLocked(evmPegged1155.address, format.hexAddress(coreDeployer.address), 1, [0], [1]);
    await coreSide
        .withdrawFromEvm(toBytes(evmPegged1155.address), [0], [1], coreDeployer.address)
        .sendTransaction({ from: coreDeployer })
        .executed();
    await checkLocked(evmPegged1155.address, format.hexAddress(coreDeployer.address), 0, [], []);
    expect(await core1155.balanceOf(coreDeployer.address, 0)).to.deep.eq(1);
    expect(await evmPegged1155.balanceOf(evmSide.address, 0)).to.deep.eq(0);
    console.log(`NFT #0 transferred to core space.`);
    // batch cross nft #1,#2,#3 to eSpace
    await core1155
        .safeBatchTransferFrom(coreDeployer.address, coreSide.address, [1, 2, 3], [2, 3, 4], toBytes(evmDeployer))
        .sendTransaction({ from: coreDeployer })
        .executed();
    for (let i = 1; i <= 3; ++i) {
        expect(await core1155.balanceOf(coreSide.address, i)).to.deep.eq(i + 1);
        expect(await evmPegged1155.balanceOf(evmDeployer, i)).to.deep.eq(i + 1);
    }
    console.log(`NFT #1,2,3 batch transferred to eSpace.`);
    // batch cross nft #1,#2 to core space
    await (
        await evmPegged1155.safeBatchTransferFrom(
            evmDeployer,
            evmSide.address,
            [1, 2],
            [2, 3],
            format.hexAddress(coreDeployer.address)
        )
    ).wait();
    await checkLocked(evmPegged1155.address, format.hexAddress(coreDeployer.address), 2, [1, 2], [2, 3]);
    await coreSide
        .withdrawFromEvm(toBytes(evmPegged1155.address), [1, 2], [1, 2], coreDeployer.address)
        .sendTransaction({ from: coreDeployer })
        .executed();
    await checkLocked(evmPegged1155.address, format.hexAddress(coreDeployer.address), 2, [1, 2], [1, 1]);
    for (let i = 1; i <= 2; ++i) {
        expect(await core1155.balanceOf(coreDeployer.address, i)).to.deep.eq(i);
        expect(await evmPegged1155.balanceOf(evmSide.address, i)).to.deep.eq(1);
    }
    console.log(`NFT #1,2 batch transferred to core space.`);
}

async function erc1155FromEvmToCore(hre: HardhatRuntimeEnvironment) {
    // deploy evm1155
    await (await evmTestTokenFactory.deploy1155("Evm1155", "Evm1155", "TEST 1155 TOKEN ON EVM SPACE")).wait();
    const evm1155 = await hre.ethers.getContractAt(
        CONTRACTS.TestERC1155,
        await evmTestTokenFactory.latestDeployed(),
        evmDeployer
    );
    console.log(`evm ERC1155 deployed: ${evm1155.address}.`);
    // deploy pegged token on core space
    await coreRegistry.deployCfx(toBytes(evm1155.address)).sendTransaction({ from: coreDeployer }).executed();
    const corePegged1155 = conflux.Contract({
        abi: loadAbi(`${abiPath}/tokens/PeggedERC1155.sol/PeggedERC1155.json`),
        address: await coreRegistry.evm2CoreTokens(toBytes(evm1155.address)),
    });
    console.log(`pegged core ERC1155 deployed: ${corePegged1155.address}`);
    // mint 5 nft to deployer
    await (await evm1155.mint(evmDeployer, [0, 1, 2, 3, 4, 5], [1, 2, 3, 4, 5, 6])).wait();
    console.log(`evm1155 minted.`);
    // cross nft #0 to core space
    await (
        await evm1155["safeTransferFrom(address,address,uint256,uint256,bytes)"](
            evmDeployer,
            evmSide.address,
            0,
            1,
            format.hexAddress(coreDeployer.address)
        )
    ).wait();
    await checkLocked(evm1155.address, format.hexAddress(coreDeployer.address), 1, [0], [1]);
    await coreSide
        .crossFromEvm(corePegged1155.address, [0], [1], coreDeployer.address)
        .sendTransaction({ from: coreDeployer })
        .executed();
    await checkLocked(evm1155.address, format.hexAddress(coreDeployer.address), 0, [], []);
    expect(await evm1155.balanceOf(evmSide.address, 0)).to.deep.eq(1);
    expect(await corePegged1155.balanceOf(coreDeployer.address, 0)).to.deep.eq(1);
    console.log(`NFT #0 transferred to core space.`);
    // cross nft #0 to eSpace
    await corePegged1155
        .safeTransferFrom(coreDeployer.address, coreSide.address, 0, 1, toBytes(evmDeployer))
        .sendTransaction({ from: coreDeployer })
        .executed();
    expect(await corePegged1155.balanceOf(coreSide.address, 0)).to.deep.eq(0);
    expect(await evm1155.balanceOf(evmDeployer, 0)).to.deep.eq(1);
    console.log(`NFT #0 transferred to eSpace.`);
    // batch cross nft #1,#2,#3 to core space
    await (
        await evm1155.safeBatchTransferFrom(
            evmDeployer,
            evmSide.address,
            [1, 2, 3],
            [2, 3, 4],
            format.hexAddress(coreDeployer.address)
        )
    ).wait();
    await coreSide
        .crossFromEvm(corePegged1155.address, [1, 2, 3], [2, 3, 4], coreDeployer.address)
        .sendTransaction({ from: coreDeployer })
        .executed();
    for (let i = 1; i <= 3; ++i) {
        expect(await evm1155.balanceOf(evmSide.address, i)).to.deep.eq(i + 1);
        expect(await corePegged1155.balanceOf(coreDeployer.address, i)).to.deep.eq(i + 1);
    }
    console.log(`NFT #1,2,3 batch transferred to core space.`);
    // batch cross nft #1,#2 to evm space
    await corePegged1155
        .safeBatchTransferFrom(coreDeployer.address, coreSide.address, [1, 2], [1, 2], toBytes(evmDeployer))
        .sendTransaction({ from: coreDeployer })
        .executed();
    for (let i = 1; i <= 2; ++i) {
        expect(await evm1155.balanceOf(evmDeployer, i)).to.deep.eq(i);
        expect(await corePegged1155.balanceOf(coreDeployer.address, i)).to.deep.eq(1);
    }
    console.log(`NFT #1,2 batch transferred to eSpace.`);
}

task("benchmark", "benchmark test").setAction(async (_taskArgs, hre) => {
    evmNetwork = hre.network.name;
    if (evmNetwork === "ConfluxEvmTestnet") {
        coreNetwork = "ConfluxCoreTestnet";
        coreContractAddress = getCoreContracts(coreNetwork, true);
    } else {
        throw new Error("invalid network: should use ConfluxEvmTestnet");
    }
    const { getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();
    evmDeployer = deployer;
    evmSide = await getProxyContract(hre, CONTRACTS.EvmSide, evmDeployer);
    evmRegistry = await getProxyContract(hre, CONTRACTS.EvmRegistry, evmDeployer);
    evmTestTokenFactory = await hre.ethers.getContract(CONTRACTS.TestTokenFactory, evmDeployer);

    coreDeployer = conflux.wallet.addPrivateKey(DEPLOYER_KEY);
    coreSide = conflux.Contract({
        abi: loadAbi(`${abiPath}/CoreSide.sol/CoreSide.json`),
        address: coreContractAddress[CONTRACTS.CoreSide],
    });
    coreRegistry = conflux.Contract({
        abi: loadAbi(`${abiPath}/CoreRegistry.sol/CoreRegistry.json`),
        address: coreContractAddress[CONTRACTS.CoreRegistry],
    });
    coreTestTokenFactory = conflux.Contract({
        abi: loadAbi(`${abiPath}/test/TestToken.sol/TestTokenFactory.json`),
        address: coreContractAddress[CONTRACTS.TestTokenFactory],
    });
    coreToEvmCallback = conflux.Contract({
        abi: loadAbi(`${abiPath}/test/TestCoreToEvmCallback.sol/TestCoreToEvmCallback.json`),
        address: coreContractAddress[CONTRACTS.TestCoreToEvmCallback],
    });
    evmToCoreCallback = conflux.Contract({
        abi: loadAbi(`${abiPath}/test/TestEvmToCoreCallback.sol/TestEvmToCoreCallback.json`),
        address: coreContractAddress[CONTRACTS.TestEvmToCoreCallback],
    });
    // benchmarks
    await erc721FromCoreToEvm(hre);
    await erc721FromEvmToCore(hre);
    await erc1155FromCoreToEvm(hre);
    await erc1155FromEvmToCore(hre);
});
