// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
}

interface IPool {
    function flashLoanSimple(address, address, uint256, bytes calldata, uint16) external;
}

interface IV2Router {
    function getAmountsOut(uint256, address[] calldata) external view returns (uint256[] memory);
    function swapExactTokensForTokens(uint256, uint256, address[] calldata, address, uint256)
        external
        returns (uint256[] memory);
}

/// @notice Restricted Aave V3 flash-loan receiver for two V2-compatible swaps.
/// @dev Supports standard ERC20 tokens only. Requires independently vetted routers.
contract FlashExecutor {
    struct Plan {
        address asset;
        address intermediate;
        address buyRouter;
        address sellRouter;
        uint256 amount;
        uint256 minIntermediate;
        uint256 minReturn;
        uint256 minProfit;
        uint256 deadline;
    }
    address public owner;
    address public pendingOwner;
    address public operator;
    address public immutable POOL;
    bool public paused;
    mapping(address => bool) public allowedRouters;
    mapping(address => bool) public allowedAssets;
    bytes32 private activePlan;
    uint256 private startingBalance;
    bool private callbackEntered;
    error Unauthorized();
    error InvalidPlan();
    error InvalidCallback();
    error InsufficientProfit();
    error TokenOperationFailed();
    event Executed(bytes32 indexed planHash, address indexed asset, uint256 amount, uint256 premium, uint256 profit);
    event ConfigurationChanged(bytes32 indexed kind, address indexed target, bool enabled);
    event Paused(bool value);

    constructor(address pool, address admin, address executor) {
        if (pool.code.length == 0 || admin == address(0) || executor == address(0)) revert InvalidPlan();
        POOL = pool;
        owner = admin;
        operator = executor;
    }
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    modifier idle() {
        if (activePlan != bytes32(0)) revert InvalidCallback();
        _;
    }

    function setRouter(address router, bool enabled) external onlyOwner idle {
        if (enabled && router.code.length == 0) revert InvalidPlan();
        allowedRouters[router] = enabled;
        emit ConfigurationChanged("router", router, enabled);
    }

    function setAsset(address asset, bool enabled) external onlyOwner idle {
        if (enabled && asset.code.length == 0) revert InvalidPlan();
        allowedAssets[asset] = enabled;
        emit ConfigurationChanged("asset", asset, enabled);
    }

    function setOperator(address next) external onlyOwner idle {
        if (next == address(0)) revert InvalidPlan();
        operator = next;
        emit ConfigurationChanged("operator", next, true);
    }

    function setPaused(bool value) external onlyOwner idle {
        paused = value;
        emit Paused(value);
    }

    function transferOwnership(address next) external onlyOwner idle {
        if (next == address(0)) revert InvalidPlan();
        pendingOwner = next;
    }

    function acceptOwnership() external idle {
        if (msg.sender != pendingOwner) revert Unauthorized();
        owner = msg.sender;
        pendingOwner = address(0);
        emit ConfigurationChanged("owner", msg.sender, true);
    }

    function rescue(address asset, uint256 amount) external onlyOwner idle {
        _transfer(asset, owner, amount);
    }

    function execute(Plan calldata p) external idle {
        if (msg.sender != operator) revert Unauthorized();
        if (
            paused || p.deadline < block.timestamp || p.deadline > block.timestamp + 5 minutes || p.amount == 0
                || p.minProfit == 0 || p.asset == p.intermediate || p.buyRouter == p.sellRouter
                || !allowedAssets[p.asset] || !allowedAssets[p.intermediate] || !allowedRouters[p.buyRouter]
                || !allowedRouters[p.sellRouter]
        ) revert InvalidPlan();
        activePlan = keccak256(abi.encode(p));
        startingBalance = IERC20(p.asset).balanceOf(address(this));
        IPool(POOL).flashLoanSimple(address(this), p.asset, p.amount, abi.encode(p), 0);
        uint256 balance = IERC20(p.asset).balanceOf(address(this));
        if (!callbackEntered || balance < startingBalance + p.minProfit) revert InsufficientProfit();
        uint256 profit = balance - startingBalance;
        activePlan = bytes32(0);
        callbackEntered = false;
        _approve(p.asset, POOL, 0);
        _transfer(p.asset, owner, profit);
    }

    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        returns (bool)
    {
        if (
            msg.sender != POOL || initiator != address(this) || activePlan == bytes32(0) || callbackEntered
                || keccak256(params) != activePlan
        ) revert InvalidCallback();
        Plan memory p = abi.decode(params, (Plan));
        if (asset != p.asset || amount != p.amount || block.timestamp > p.deadline) revert InvalidCallback();
        callbackEntered = true;
        uint256 beforeIntermediate = IERC20(p.intermediate).balanceOf(address(this));
        _swap(asset, p.intermediate, p.buyRouter, amount, p.minIntermediate, p.deadline);
        uint256 acquired = IERC20(p.intermediate).balanceOf(address(this)) - beforeIntermediate;
        _swap(p.intermediate, asset, p.sellRouter, acquired, p.minReturn, p.deadline);
        uint256 balance = IERC20(asset).balanceOf(address(this));
        if (balance < startingBalance + amount + premium + p.minProfit) revert InsufficientProfit();
        _approve(asset, POOL, amount + premium);
        emit Executed(activePlan, asset, amount, premium, balance - startingBalance - amount - premium);
        return true;
    }

    function _swap(address a, address b, address router, uint256 amount, uint256 minOut, uint256 deadline) private {
        address[] memory path = new address[](2);
        path[0] = a;
        path[1] = b;
        _approve(a, router, amount);
        IV2Router(router).swapExactTokensForTokens(amount, minOut, path, address(this), deadline);
        _approve(a, router, 0);
    }

    function _approve(address token, address spender, uint256 amount) private {
        _call(token, abi.encodeCall(IERC20.approve, (spender, 0)));
        if (amount > 0) _call(token, abi.encodeCall(IERC20.approve, (spender, amount)));
    }

    function _transfer(address token, address to, uint256 amount) private {
        _call(token, abi.encodeCall(IERC20.transfer, (to, amount)));
    }

    function _call(address token, bytes memory data) private {
        (bool ok, bytes memory result) = token.call(data);
        if (!ok || (result.length != 0 && !abi.decode(result, (bool)))) revert TokenOperationFailed();
    }
}
