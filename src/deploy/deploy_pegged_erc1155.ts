import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { CONTRACTS, deployInBeaconProxy } from "../utils/utils";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    await deployInBeaconProxy(hre, CONTRACTS.PeggedERC1155, false);
};

deploy.tags = [CONTRACTS.PeggedERC1155, "prod"];
deploy.dependencies = [];
export default deploy;
