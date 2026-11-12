// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import "../src/FlashExecutor.sol";

interface VmFork {
    function envOr(string calldata, string calldata) external returns (string memory);
    function createSelectFork(string calldata, uint256) external returns (uint256);
    function skip(bool) external;
    function expectRevert(bytes4) external;
}

interface IPremium {
    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128);
}

/// @notice Optional pinned-block archive RPC integration; skipped without MAINNET_RPC_URL.
contract EthereumForkTest {
    VmFork constant vm = VmFork(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant UNI = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    function testForkAaveAndV2QuoteAndProfitRollback() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        vm.skip(bytes(rpc).length == 0);
        vm.createSelectFork(rpc, 21_000_000);
        require(POOL.code.length > 0 && UNI.code.length > 0, "deployments missing");
        require(IPremium(POOL).FLASHLOAN_PREMIUM_TOTAL() < 100, "premium sanity");
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = WETH;
        uint256[] memory q = IV2Router(UNI).getAmountsOut(1000e6, path);
        require(q[1] > 0, "quote missing");
        // Use a second, local router-shaped contract forwarding to the same real Uniswap market.
        // The round trip pays two swap fees and must fail the profit floor atomically.
        V2Forwarder second = new V2Forwarder();
        FlashExecutor executor = new FlashExecutor(POOL, address(this), address(this));
        executor.setRouter(UNI, true);
        executor.setRouter(address(second), true);
        executor.setAsset(USDC, true);
        executor.setAsset(WETH, true);
        uint256 poolBalance = IERC20(USDC).balanceOf(POOL);
        FlashExecutor.Plan memory p =
            FlashExecutor.Plan(USDC, WETH, UNI, address(second), 1000e6, 1, 1, 1e6, block.timestamp + 60);
        vm.expectRevert(FlashExecutor.InsufficientProfit.selector);
        executor.execute(p);
        require(IERC20(USDC).balanceOf(POOL) == poolBalance, "atomic rollback");
        require(IV2Router(UNI).getAmountsOut(1000e6, path)[1] == q[1], "reserves restored");
    }
}

/// @dev Test-only adapter to exercise actual Uniswap swaps twice without a second venue dependency.
contract V2Forwarder {
    address constant UNI = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    function swapExactTokensForTokens(
        uint256 amount,
        uint256 minOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory) {
        require(IERC20(path[0]).transferFrom(msg.sender, address(this), amount));
        require(IERC20(path[0]).approve(UNI, amount));
        return IV2Router(UNI).swapExactTokensForTokens(amount, minOut, path, to, deadline);
    }
}
