// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IEvmRegistry {
    /*=== structs ===*/

    struct Deployment {
        string name;
        string symbol;
        uint256 nftType;
        address deployed;
    }

    /*=== functions ===*/

    function approve(address evmToken, address cfxOperator) external;

    function approvedOperators(address) external view returns (address);

    function cfxRegistry() external view returns (address);

    function deploy(address cfxToken) external;

    function deployments(
        address
    ) external view returns (string memory name, string memory symbol, uint256 nftType, address deployed);

    function evmTokens(uint256 offset, uint256 limit) external view returns (uint256 total, address[] memory tokens);

    function getDeployed(address nft) external view returns (address deployed);

    function preDeployCfx(
        address evmToken
    ) external returns (uint256 nftType, string memory name, string memory symbol);

    function registerCfx(address evmToken) external;

    function registerDeploy(address cfxToken, uint256 nftType, string memory name, string memory symbol) external;

    function registerEvm(address evmToken) external;

    function setCfxRegistry() external;

    function unregisterCfx(address evmToken) external;

    function unregisterEvm(address evmToken) external;

    function validateToken(address nft) external view;
}
