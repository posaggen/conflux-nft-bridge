// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IEvmToCoreCallback.sol";
import "./TestToken.sol";

contract TestEvmToCoreCallback is IEvmToCoreCallback {
    address public coreSide;

    constructor(address _coreSide) {
        coreSide = _coreSide;
    }

    function onEvmToCore(
        bytes20,
        address cfxToken,
        uint256[] memory ids,
        uint256[] memory,
        address recipient
    ) external returns (bytes4) {
        require(msg.sender == coreSide, "TestEvmToCoreCallback: forbid");
        TestERC721(cfxToken).mint(recipient, ids);
        return IEvmToCoreCallback.onEvmToCore.selector;
    }
}
