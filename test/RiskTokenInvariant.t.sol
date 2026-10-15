// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {RiskToken} from "../src/RiskToken.sol";

/// @dev Exercises successful and rejected ERC-20 calls among a closed set of holders.
/// The model starts from the requested supply and changes only for successful actions;
/// rejected actions must leave every modeled balance and allowance unchanged.
contract RiskTokenHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    RiskToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(RiskToken token_, address initialHolder) {
        token = token_;
        actors[0] = initialHolder;
        actors[1] = makeAddr("invariant alice");
        actors[2] = makeAddr("invariant bob");
        actors[3] = makeAddr("invariant spender");
        expectedBalance[initialHolder] = SUPPLY;
    }

    function transfer(uint256 fromIndex, uint256 toIndex, uint256 amount) external {
        address from = actors[fromIndex % actors.length];
        address to = actors[toIndex % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerIndex, uint256 spenderIndex, uint256 amount) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        _approve(owner, spender, amount);
    }

    function approveInfinite(uint256 ownerIndex, uint256 spenderIndex) external {
        _approve(actors[ownerIndex % actors.length], actors[spenderIndex % actors.length], type(uint256).max);
    }

    function revoke(uint256 ownerIndex, uint256 spenderIndex) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
    }

    function transferFrom(uint256 ownerIndex, uint256 spenderIndex, uint256 toIndex, uint256 amount) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, 0, allowed < balance ? allowed : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }

    function transferEntireBalance(uint256 fromIndex, uint256 toIndex) external {
        address from = actors[fromIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function transferAboveBalance(uint256 fromIndex, uint256 toIndex, uint256 amount) external {
        address from = actors[fromIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        _reject(
            from,
            abi.encodeCall(token.transfer, (to, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function transferFromAboveBalance(
        uint256 ownerIndex,
        uint256 spenderIndex,
        uint256 toIndex,
        uint256 amount,
        bool infinite
    ) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, balance + 1, type(uint256).max);
        // Reach the balance check with both finite and unlimited approvals. The
        // model retains this approval even though the delegated transfer fails.
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, to, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
        );
    }

    function transferFromAboveAllowance(
        uint256 ownerIndex,
        uint256 spenderIndex,
        uint256 toIndex,
        uint256 approved,
        uint256 amount
    ) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        address to = actors[toIndex % actors.length];
        approved = bound(approved, 0, SUPPLY - 1);
        amount = bound(amount, approved + 1, SUPPLY);
        _approve(owner, spender, approved);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, to, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
    }

    function transferToZero(uint256 ownerIndex, uint256 spenderIndex, uint256 amount, bool delegated) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        uint256 limit = expectedBalance[owner];
        if (delegated && expectedAllowance[owner][spender] < limit) {
            limit = expectedAllowance[owner][spender];
        }
        amount = bound(amount, 0, limit);
        bytes memory callData = delegated
            ? abi.encodeCall(token.transferFrom, (owner, address(0), amount))
            : abi.encodeCall(token.transfer, (address(0), amount));
        _reject(
            delegated ? spender : owner,
            callData,
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function approveZeroSpender(uint256 ownerIndex, uint256 amount) external {
        _reject(
            actors[ownerIndex % actors.length],
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _reject(address caller, bytes memory callData, bytes memory expectedError) private {
        vm.prank(caller);
        (bool success, bytes memory reason) = address(token).call(callData);
        assertFalse(success, "invalid operation succeeded");
        assertEq(reason, expectedError, "unexpected failure reason");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract RiskTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    RiskToken private token;
    RiskTokenHandler private handler;

    function setUp() public {
        token = new RiskToken();
        handler = new RiskTokenHandler(token, address(this));
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = RiskTokenHandler.transfer.selector;
        selectors[1] = RiskTokenHandler.approve.selector;
        selectors[2] = RiskTokenHandler.revoke.selector;
        selectors[3] = RiskTokenHandler.transferFrom.selector;
        selectors[4] = RiskTokenHandler.approveInfinite.selector;
        selectors[5] = RiskTokenHandler.transferEntireBalance.selector;
        selectors[6] = RiskTokenHandler.transferAboveBalance.selector;
        selectors[7] = RiskTokenHandler.transferFromAboveBalance.selector;
        selectors[8] = RiskTokenHandler.transferFromAboveAllowance.selector;
        selectors[9] = RiskTokenHandler.transferToZero.selector;
        selectors[10] = RiskTokenHandler.approveZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyBalancesAndAllowancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            assertEq(token.allowance(actor, address(0)), 0);
            assertEq(token.allowance(address(0), actor), 0);
            sum += balance;
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(actor, spender), handler.expectedAllowance(actor, spender));
            }
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    /// @dev Pin a nonzero campaign through the same handler used by the fuzzer.
    /// This checks that delegated actions and failure recovery are reachable,
    /// without imposing a probabilistic coverage threshold on random sequences.
    function test_handlerSupportsNonzeroSpendsAndFailureRecovery() public {
        handler.transfer(0, 1, 20);
        handler.approve(1, 2, 10);
        handler.transferFrom(1, 2, 3, 7);
        invariant_supplyBalancesAndAllowancesMatchModel();
        assertEq(token.balanceOf(handler.actors(3)), 7);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), 3);

        handler.transferAboveBalance(1, 3, 14);
        handler.transferFromAboveAllowance(1, 2, 3, 3, 4);
        handler.transferFromAboveBalance(1, 2, 3, 14, false);
        handler.transferToZero(1, 2, 1, true);
        handler.transferToZero(1, 2, 0, false);
        handler.approveZeroSpender(1, type(uint256).max);
        invariant_supplyBalancesAndAllowancesMatchModel();

        handler.approveInfinite(1, 2);
        handler.transferFrom(1, 2, 3, 13);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), type(uint256).max);
        handler.revoke(1, 2);
        handler.transferEntireBalance(3, 1);
        invariant_supplyBalancesAndAllowancesMatchModel();
        assertEq(token.balanceOf(handler.actors(1)), 20);
        assertEq(token.balanceOf(handler.actors(3)), 0);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), 0);
    }
}
