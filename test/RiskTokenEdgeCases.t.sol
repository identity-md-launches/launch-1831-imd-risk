// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {RiskToken} from "../src/RiskToken.sol";

/// @dev Regression cases for allowance transitions, aliased callers and arithmetic
/// boundaries. All amounts below are minor units, including the one-wei cases.
/// forge-config: default.fuzz.runs = 1000
contract RiskTokenEdgeCasesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    RiskToken private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        token = new RiskToken();
        alice = makeAddr("edge alice");
        bob = makeAddr("edge bob");
        spender = makeAddr("edge spender");
    }

    function test_oneWeiCanMoveThroughDirectAndDelegatedTransfers() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, spender), 0);

        vm.prank(bob);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_fullSupplyDelegatedTransferCannotBeReplayed() public {
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(address(this), spender), 0);

        // Replenish the owner: the second spend must fail because the allowance
        // was consumed, independently of the owner's balance.
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumFiniteAllowanceIsNotTreatedAsInfinite() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumAmountRevertsWithoutOverflowOrStateChanges() public {
        uint256 maximum = type(uint256).max;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, maximum)
        );
        token.transfer(alice, maximum);

        assertTrue(token.approve(spender, maximum - 1));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, maximum - 1, maximum)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, maximum);
        assertEq(token.allowance(address(this), spender), maximum - 1);

        assertTrue(token.approve(spender, maximum));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, maximum)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, maximum);
        assertEq(token.allowance(address(this), spender), maximum);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_unlimitedApprovalCanBeRevokedThenReplacedWithFiniteApproval() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 1);

        assertTrue(token.approve(spender, 3));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 3));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 4);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ownerMustApproveItselfToUseTransferFrom() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);

        assertTrue(token.approve(address(this), 2));
        assertTrue(token.transferFrom(address(this), address(this), 1));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), address(this)), 1);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(address(this), address(this)), 0);
    }

    function test_spendingAuthorityUsesCallerNotTransactionOrigin() public {
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob, spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);

        vm.prank(spender, bob);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_zeroDelegatedTransferToZeroRevertsWithUnlimitedAllowance() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveZeroSpenderRejectsZeroAndMaximumAmounts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), type(uint256).max);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_tokensSentToTokenContractRemainPartOfFixedSupply() public {
        assertTrue(token.transfer(address(token), 1));
        assertTrue(token.approve(spender, SUPPLY - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(token), SUPPLY - 1));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedBalanceSpendPreservesApprovalAndCanBeRetried(
        uint256 balance,
        uint256 requested,
        bool infinite
    ) public {
        balance = bound(balance, 1, SUPPLY - 1);
        requested = bound(requested, balance + 1, SUPPLY);
        uint256 approval = infinite ? type(uint256).max : requested;
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approval));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, requested)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, requested);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.allowance(alice, spender), approval);

        // Funding changes only the balance. The approval from before the failed
        // call must still authorize the exact same requested spend.
        assertTrue(token.transfer(alice, requested - balance));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, requested));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), requested);
        assertEq(token.balanceOf(address(this)), SUPPLY - requested);
        assertEq(token.allowance(alice, spender), infinite ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_reducingApprovalImmediatelyLimitsSpending(uint256 oldApproval, uint256 newApproval) public {
        oldApproval = bound(oldApproval, 1, SUPPLY);
        newApproval = bound(newApproval, 0, oldApproval - 1);
        assertTrue(token.approve(spender, oldApproval));
        assertTrue(token.approve(spender, newApproval));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, newApproval, newApproval + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, newApproval + 1);
        assertEq(token.allowance(address(this), spender), newApproval);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, newApproval));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), newApproval);
        assertEq(token.balanceOf(address(this)), SUPPLY - newApproval);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_directTransfersDoNotConsumeOrMoveApprovals(uint256 amount, uint256 approval) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.approve(spender, approval));
        assertTrue(token.transfer(alice, amount));
        assertEq(token.allowance(address(this), spender), approval);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedTransferCanPayTheSpender(uint256 amount, uint256 approval) public {
        amount = bound(amount, 1, SUPPLY);
        approval = bound(approval, amount, type(uint256).max);
        assertTrue(token.approve(spender, approval));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), spender, amount));
        assertEq(token.balanceOf(spender), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), approval == type(uint256).max ? approval : approval - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitDelegatedTransfersAndRoundTripConserveEveryUnit(uint256 amount, uint256 firstPart) public {
        amount = bound(amount, 1, SUPPLY);
        firstPart = bound(firstPart, 0, amount);
        assertTrue(token.approve(spender, amount));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, firstPart));
        assertTrue(token.transferFrom(address(this), bob, amount - firstPart));
        vm.stopPrank();
        assertEq(token.balanceOf(alice), firstPart);
        assertEq(token.balanceOf(bob), amount - firstPart);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), 0);

        vm.prank(alice);
        assertTrue(token.transfer(address(this), firstPart));
        vm.prank(bob);
        assertTrue(token.transfer(address(this), amount - firstPart));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
