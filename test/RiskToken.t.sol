// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {RiskToken} from "../src/RiskToken.sol";

/// forge-config: default.fuzz.runs = 1000
contract RiskTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    RiskToken private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new RiskToken();
    }

    function test_metadataAndInitialSupply() public view {
        assertEq(token.name(), "IMD RISK");
        assertEq(token.symbol(), "RISK");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_constructorEmitsExactlyOneMintEvent() public {
        vm.recordLogs();
        vm.prank(alice);
        RiskToken deployed = new RiskToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(deployed));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(deployed.balanceOf(alice), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
    }

    function test_transferEmitsEventAndDeliversExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 123 ether + 1);
        assertTrue(token.transfer(alice, 123 ether + 1));
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether - 1);
        assertEq(token.balanceOf(alice), 123 ether + 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_entireSupplyCanMoveAndReturn() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalanceAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountSucceedsAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_approveReplacesAllowanceAndEmitsEvent() public {
        assertTrue(token.approve(spender, 10 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, 3 ether);
        assertTrue(token.approve(spender, 3 ether));
        assertEq(token.allowance(address(this), spender), 3 ether);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approvalDoesNotRequireCurrentBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromDeliversExactlyAndConsumesFiniteAllowance() public {
        token.approve(spender, 7 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 5 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 5 ether));
        assertEq(token.allowance(address(this), spender), 2 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 5 ether);
        assertEq(token.balanceOf(alice), 5 ether);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 2 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 2 ether);
    }

    function test_transferFromPreservesInfiniteAllowance() public {
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 7 ether));
        assertTrue(token.transferFrom(address(this), bob, 3 ether));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 7 ether);
        assertEq(token.balanceOf(bob), 3 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 10 ether);
    }

    function test_transferFromSelfConsumesAllowanceWithoutChangingBalance() public {
        token.approve(spender, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 4 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 6 ether);
    }

    function test_zeroTransferFromNeedsNoAllowanceForValidAddresses() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_revokePreventsFurtherSpending() public {
        token.approve(spender, 10 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferRevertsWhenBalanceIsInsufficient() public {
        token.transfer(alice, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10, 11));
        vm.prank(alice);
        token.transfer(bob, 11);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferToZeroAddressRevertsEvenForZeroValue() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_transferFromZeroSourceReverts() public {
        // OpenZeppelin validates the approver while spending the zero allowance first.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromInsufficientAllowanceRevertsWithoutChanges() public {
        token.approve(spender, 3 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 3 ether, 4 ether)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 4 ether);
        assertEq(token.allowance(address(this), spender), 3 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferFromInsufficientBalanceRestoresAllowance() public {
        token.transfer(alice, 5 ether);
        vm.prank(alice);
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5 ether, 6 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 6 ether);
        assertEq(token.allowance(alice, spender), 10 ether);
        assertEq(token.balanceOf(alice), 5 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromInvalidRecipientRestoresAllowance() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 4 ether);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_deployerCannotSpendHoldersTokensWithoutApproval() public {
        token.transfer(alice, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1 ether)
        );
        token.transferFrom(alice, bob, 1 ether);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
    }

    function test_allowanceCannotBeUsedByAnotherSpender() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1 ether));
        vm.prank(bob);
        token.transferFrom(address(this), alice, 1 ether);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_nativeCurrencyIsRejected() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 amount) public {
        recipient = address(uint160(bound(uint256(uint160(recipient)), 1, type(uint160).max)));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        if (recipient == address(this)) {
            assertEq(token.balanceOf(address(this)), SUPPLY);
        } else {
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
            assertEq(token.balanceOf(recipient), amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function testFuzz_transferFromAccountsForAllowance(uint256 approved, uint256 amount) public {
        amount = bound(amount, 0, approved < SUPPLY ? approved : SUPPLY);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_overspendingBalanceAlwaysReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_overspendingAllowanceAlwaysReverts(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY - 1);
        amount = bound(amount, approved + 1, SUPPLY);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
