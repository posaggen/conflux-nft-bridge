// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICoreRegistry {
    function cfxTokens(uint256 offset, uint256 limit) external view returns (uint256 total, address[] memory tokens);

    function core2EvmCallbacks(address) external view returns (address);

    function core2EvmTokens(address) external view returns (bytes20);

    function deployCfx(bytes20 evmToken) external;

    function evm2CoreCallbacks(address) external view returns (address);

    function evm2CoreTokens(bytes20) external view returns (address);

    function evmRegistry() external view returns (bytes20);

    function peggedCore2EvmTokens(address) external view returns (bytes20);

    function peggedEvm2CoreTokens(bytes20) external view returns (address);

    function registerCfx(bytes20 evmToken, address cfxToken) external;

    function registerDeployEvm(address cfxToken) external;

    function registerEvm(address cfxToken, bytes20 evmToken) external;

    function registeredCore2EvmTokens(address) external view returns (bytes20);

    function registeredEvm2CoreTokens(bytes20) external view returns (address);

    function setCore2EvmCallback(address cfxToken, address callback) external;

    function setEvm2CoreCallback(address cfxToken, address callback) external;

    function unregisterCfx(address cfxToken) external;

    function unregisterEvm(bytes20 evmToken) external;

    function updateDeployed(address cfxToken) external;
}
