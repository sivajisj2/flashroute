// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import "../src/DemoMarket.sol";

interface Vm {
    function prank(address) external;
    function expectRevert(bytes4) external;
    function warp(uint256) external;
}

contract FlashExecutorTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    DemoToken a;
    DemoToken b;
    DemoPool pool;
    DemoDex buy;
    DemoDex sell;
    FlashExecutor executor;

    function setUp() public {
        a = new DemoToken("USD", "USD");
        b = new DemoToken("DAI", "DAI");
        pool = new DemoPool();
        buy = new DemoDex(address(a), address(b));
        sell = new DemoDex(address(a), address(b));
        executor = new FlashExecutor(address(pool), address(this), address(this));
        executor.setRouter(address(buy), true);
        executor.setRouter(address(sell), true);
        executor.setAsset(address(a), true);
        executor.setAsset(address(b), true);
        a.mint(address(pool), 10_000_000e6);
        a.mint(address(buy), 5_000_000e6);
        b.mint(address(buy), 5_150_000e6);
        a.mint(address(sell), 5_000_000e6);
        b.mint(address(sell), 5_000_000e6);
    }

    function plan() internal view returns (FlashExecutor.Plan memory) {
        return FlashExecutor.Plan(
            address(a), address(b), address(buy), address(sell), 10_000e6, 1, 10_001e6, 1e6, block.timestamp + 60
        );
    }

    function testProfitableLoanRepaysAndDistributes() public {
        uint256 lender = a.balanceOf(address(pool));
        executor.execute(plan());
        require(a.balanceOf(address(this)) > 1e6, "profit");
        require(a.balanceOf(address(pool)) == lender + 5e6, "premium");
        require(a.balanceOf(address(executor)) == 0, "residue");
        require(a.allowance(address(executor), address(buy)) == 0, "router approval");
        require(a.allowance(address(executor), address(pool)) == 0, "pool approval");
    }

    function testUnauthorized() public {
        vm.prank(address(42));
        vm.expectRevert(FlashExecutor.Unauthorized.selector);
        executor.execute(plan());
    }

    function testForgedCallback() public {
        vm.expectRevert(FlashExecutor.InvalidCallback.selector);
        executor.executeOperation(address(a), 1, 0, address(executor), abi.encode(plan()));
    }

    function testCallbackWithoutLoan() public {
        vm.prank(address(pool));
        vm.expectRevert(FlashExecutor.InvalidCallback.selector);
        executor.executeOperation(address(a), 1, 0, address(executor), abi.encode(plan()));
    }

    function testPaused() public {
        executor.setPaused(true);
        vm.expectRevert(FlashExecutor.InvalidPlan.selector);
        executor.execute(plan());
    }

    function testUnapprovedRouter() public {
        executor.setRouter(address(buy), false);
        vm.expectRevert(FlashExecutor.InvalidPlan.selector);
        executor.execute(plan());
    }

    function testUnapprovedAsset() public {
        executor.setAsset(address(b), false);
        vm.expectRevert(FlashExecutor.InvalidPlan.selector);
        executor.execute(plan());
    }

    function testExpired() public {
        FlashExecutor.Plan memory p = plan();
        vm.warp(p.deadline + 1);
        vm.expectRevert(FlashExecutor.InvalidPlan.selector);
        executor.execute(p);
    }

    function testLongDeadline() public {
        FlashExecutor.Plan memory p = plan();
        p.deadline = block.timestamp + 301;
        vm.expectRevert(FlashExecutor.InvalidPlan.selector);
        executor.execute(p);
    }

    function testUnprofitableAtomicRollback() public {
        FlashExecutor.Plan memory p = plan();
        p.minProfit = 1000e6;
        uint256 reserve = a.balanceOf(address(buy));
        uint256 lender = a.balanceOf(address(pool));
        vm.expectRevert(FlashExecutor.InsufficientProfit.selector);
        executor.execute(p);
        require(a.balanceOf(address(buy)) == reserve && a.balanceOf(address(pool)) == lender, "rollback");
    }

    function testDonationsCannotSubsidizeLoss() public {
        a.mint(address(executor), 1_000_000e6);
        FlashExecutor.Plan memory p = plan();
        p.buyRouter = address(sell);
        p.sellRouter = address(buy);
        p.minReturn = 1;
        vm.expectRevert(FlashExecutor.InsufficientProfit.selector);
        executor.execute(p);
        require(a.balanceOf(address(executor)) == 1_000_000e6, "donation consumed");
    }

    function testTwoStepOwnership() public {
        executor.transferOwnership(address(42));
        require(executor.owner() == address(this));
        vm.prank(address(42));
        executor.acceptOwnership();
        require(executor.owner() == address(42));
    }

    function testFuzzProfitFloor(uint96 raw) public {
        FlashExecutor.Plan memory p = plan();
        p.amount = 100e6 + uint256(raw) % 10_000e6;
        p.minReturn = 1;
        uint256 beforeBalance = a.balanceOf(address(this));
        executor.execute(p);
        require(a.balanceOf(address(this)) >= beforeBalance + p.minProfit, "profit floor");
    }
}
