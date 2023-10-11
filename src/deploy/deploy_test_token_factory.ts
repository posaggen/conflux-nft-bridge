import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { CONTRACTS } from "../utils/utils";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    if (hre.network.name !== "ConfluxEvmTestnet") {
        return;
    }

    const { deployments, getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();
    const { deploy } = deployments;

    await deploy(CONTRACTS.TestTokenFactory, {
        from: deployer,
        contract: CONTRACTS.TestTokenFactory,
        args: [],
        log: true,
    });
};

deploy.tags = [CONTRACTS.TestTokenFactory];
deploy.dependencies = [];
export default deploy;
