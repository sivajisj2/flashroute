// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import "../src/DemoMarket.sol";

interface VmDeploy {
    function startBroadcast() external;
    function stopBroadcast() external;
    function serializeAddress(string calldata, string calldata, address) external returns (string memory);
    function writeJson(string calldata, string calldata) external;
}

contract DeployLocal {
    VmDeploy constant vm = VmDeploy(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run() external {
        require(block.chainid == 31337, "local only");
        vm.startBroadcast();
        DemoToken a = new DemoToken("Demo USD Coin", "dUSDC");
        DemoToken b = new DemoToken("Demo Dai", "dDAI");
        DemoPool pool = new DemoPool();
        DemoDex buy = new DemoDex(address(a), address(b));
        DemoDex sell = new DemoDex(address(a), address(b));
        address admin = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        FlashExecutor executor = new FlashExecutor(address(pool), admin, admin);
        executor.setAsset(address(a), true);
        executor.setAsset(address(b), true);
        executor.setRouter(address(buy), true);
        executor.setRouter(address(sell), true);
        a.mint(address(pool), 10_000_000e6);
        a.mint(address(buy), 5_000_000e6);
        b.mint(address(buy), 5_150_000e6);
        a.mint(address(sell), 5_000_000e6);
        b.mint(address(sell), 5_000_000e6);
        vm.stopBroadcast();
        vm.serializeAddress("deployment", "asset", address(a));
        vm.serializeAddress("deployment", "intermediate", address(b));
        vm.serializeAddress("deployment", "pool", address(pool));
        vm.serializeAddress("deployment", "buy_router", address(buy));
        vm.serializeAddress("deployment", "sell_router", address(sell));
        vm.serializeAddress("deployment", "operator", admin);
        string memory json = vm.serializeAddress("deployment", "executor", address(executor));
        vm.writeJson(json, "deployments/local.json");
    }
}
