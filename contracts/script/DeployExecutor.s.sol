// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import "../src/FlashExecutor.sol";

interface VmConfig {
    function envAddress(string calldata) external returns (address);
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploy only the receiver. Configure verified allowlists separately through the owner.
contract DeployExecutor {
    VmConfig constant vm = VmConfig(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run() external returns (FlashExecutor receiver) {
        address pool = vm.envAddress("AAVE_POOL");
        address owner = vm.envAddress("OWNER");
        address operator = vm.envAddress("OPERATOR");
        vm.startBroadcast();
        receiver = new FlashExecutor(pool, owner, operator);
        vm.stopBroadcast();
    }
}
