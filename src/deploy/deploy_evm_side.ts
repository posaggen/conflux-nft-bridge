import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { CONTRACTS, deployInBeaconProxy, getProxyContract } from "../utils/utils";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();

    await deployInBeaconProxy(hre, CONTRACTS.EvmSide);

    // initialize
    console.log(`initializing ${CONTRACTS.EvmSide}..`);
    const evmSide_ = await getProxyContract(hre, CONTRACTS.EvmSide, await hre.ethers.getSigner(deployer));
    if (!(await evmSide_.initialized())) {
        const registry_ = await getProxyContract(hre, CONTRACTS.EvmRegistry, await hre.ethers.getSigner(deployer));
        await (await registry_.setBridge(evmSide_.address)).wait();
        await (await evmSide_.initialize(registry_.address)).wait();
    }
};

deploy.tags = [CONTRACTS.EvmSide];
deploy.dependencies = [CONTRACTS.PeggedERC1155, CONTRACTS.PeggedERC721, CONTRACTS.EvmRegistry];
export default deploy;
