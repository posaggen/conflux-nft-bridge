import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { CONTRACTS, deployInBeaconProxy, getProxyContract } from "../utils/utils";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();

    await deployInBeaconProxy(hre, CONTRACTS.EvmRegistry);

    // initialize
    console.log(`initializing ${CONTRACTS.EvmRegistry}..`);
    const registry_ = await getProxyContract(hre, CONTRACTS.EvmRegistry, await hre.ethers.getSigner(deployer));
    if (!(await registry_.initialized())) {
        const beaconERC721 = (await hre.ethers.getContract(`${CONTRACTS.PeggedERC721}Beacon`)).address;
        const beaconERC1155 = (await hre.ethers.getContract(`${CONTRACTS.PeggedERC1155}Beacon`)).address;
        await (await registry_.initialize(beaconERC721, beaconERC1155)).wait();
    }
};

deploy.tags = [CONTRACTS.EvmRegistry];
deploy.dependencies = [CONTRACTS.PeggedERC1155, CONTRACTS.PeggedERC721];
export default deploy;
