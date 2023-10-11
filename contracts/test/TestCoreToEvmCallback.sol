// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@confluxfans/contracts/InternalContracts/InternalContractsLib.sol";

import "../interfaces/ICoreToEvmCallback.sol";
import "./TestToken.sol";

contract TestCoreToEvmCallback is ICoreToEvmCallback {
    address public coreSide;

    constructor(address _coreSide) {
        coreSide = _coreSide;
    }

    function onCoreToEvm(
        address,
        address,
        address,
        uint256[] memory ids,
        uint256[] memory,
        bytes20 evmToken,
        address recipient
    ) external returns (bytes4) {
        require(msg.sender == coreSide, "TestCoreToEvmCallback: forbid");
        InternalContracts.CROSS_SPACE_CALL.callEVM(
            evmToken,
            abi.encodeWithSelector(TestERC721.mint.selector, recipient, ids)
        );
        return ICoreToEvmCallback.onCoreToEvm.selector;
    }
}
