// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import "./FlashExecutor.sol";

/// @notice Unrestricted minting; LOCAL DEVELOPMENT ONLY.
contract DemoToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(string memory n, string memory s) {
        name = n;
        symbol = s;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address to, uint256 amount) external returns (bool) {
        allowance[msg.sender][to] = amount;
        emit Approval(msg.sender, to, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) allowance[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

/// @notice Aave-shaped test lender; 5 bps premium, rounded half-up like Aave PercentageMath.
contract DemoPool {
    function FLASHLOAN_PREMIUM_TOTAL() external pure returns (uint128) {
        return 5;
    }

    function flashLoanSimple(address receiver, address asset, uint256 amount, bytes calldata params, uint16) external {
        uint256 beforeBalance = IERC20(asset).balanceOf(address(this));
        uint256 premium = (amount * 5 + 5000) / 10000;
        require(IERC20(asset).transfer(receiver, amount));
        require(FlashExecutor(receiver).executeOperation(asset, amount, premium, msg.sender, params));
        require(IERC20(asset).transferFrom(receiver, address(this), amount + premium));
        require(IERC20(asset).balanceOf(address(this)) >= beforeBalance + premium, "repayment");
    }
}

/// @notice Two-token constant-product market with 0.30% fee and V2 router-shaped interface.
contract DemoDex {
    address public immutable token0;
    address public immutable token1;

    constructor(address a, address b) {
        token0 = a;
        token1 = b;
    }

    function getAmountsOut(uint256 amount, address[] calldata path) public view returns (uint256[] memory amounts) {
        require(
            path.length == 2 && ((path[0] == token0 && path[1] == token1) || (path[0] == token1 && path[1] == token0)),
            "path"
        );
        uint256 rIn = IERC20(path[0]).balanceOf(address(this));
        uint256 rOut = IERC20(path[1]).balanceOf(address(this));
        amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = amount * 997 * rOut / (rIn * 1000 + amount * 997);
    }

    function swapExactTokensForTokens(
        uint256 amount,
        uint256 minOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "expired");
        amounts = getAmountsOut(amount, path);
        require(amounts[1] >= minOut, "slippage");
        require(IERC20(path[0]).transferFrom(msg.sender, address(this), amount));
        require(IERC20(path[1]).transfer(to, amounts[1]));
    }
}
