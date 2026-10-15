// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {RiskToken} from "../src/RiskToken.sol";

/// @dev Local deployment/transfer fixture, never a production application contract.
contract TokenFactoryHarness {
    function deploy(bytes32 salt) external returns (RiskToken) {
        return new RiskToken{salt: salt}();
    }

    function move(RiskToken token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

/// @dev ERC-20 recipients must not need a callback or special receiving interface.
contract RejectsCallbacks {
    fallback() external {
        revert("no callbacks accepted");
    }
}

contract RiskTokenLaunchTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    TokenFactoryHarness private factory;
    RiskToken private token;
    address private requester;
    address private operator;

    function setUp() public {
        requester = makeAddr("requester");
        operator = makeAddr("operator");
        factory = new TokenFactoryHarness();
        vm.prank(requester, operator);
        token = factory.deploy(keccak256("risk launch test"));
    }

    function test_create2MintsEverythingToImmediateFactory() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(requester), 0);
        assertEq(token.balanceOf(operator), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function test_launchTransfersAndClaimArriveWhole() public {
        address distributor = address(new RejectsCallbacks());
        address poolRecipient = address(new RejectsCallbacks());
        address claimant = makeAddr("claimant");
        uint256 swarm = SUPPLY * 1_000 / 10_000;
        uint256 pool = SUPPLY * 8_800 / 10_000;
        uint256 remainder = SUPPLY * 200 / 10_000;

        assertTrue(factory.move(token, distributor, swarm));
        assertTrue(factory.move(token, poolRecipient, pool));
        assertTrue(factory.move(token, requester, remainder));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), swarm);
        assertEq(token.balanceOf(poolRecipient), pool);
        assertEq(token.balanceOf(requester), remainder);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarm));
        assertEq(token.balanceOf(claimant), swarm);
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_contractAndOrdinaryHolderCanTransferInBothDirections() public {
        address recipientContract = address(new RejectsCallbacks());
        address trader = makeAddr("trader");
        factory.move(token, recipientContract, 1_000 ether);
        vm.prank(recipientContract);
        assertTrue(token.transfer(trader, 123 ether));
        assertEq(token.balanceOf(trader), 123 ether);
        vm.prank(trader);
        assertTrue(token.transfer(recipientContract, 123 ether));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(recipientContract), 1_000 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_noMintBurnFreezeOrUpgradeEntryPointsForFactoryOrStranger() public {
        address holder = makeAddr("holder");
        address recipient = makeAddr("recipient");
        factory.move(token, holder, 1_000 ether);
        bytes[] memory calls = new bytes[](26);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", holder, 1 ether);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", 1 ether);
        calls[4] = abi.encodeWithSignature("setOwner(address)", recipient);
        calls[5] = abi.encodeWithSignature("transferOwnership(address)", recipient);
        calls[6] = abi.encodeWithSignature("upgradeTo(address)", recipient);
        calls[7] = abi.encodeWithSignature("initialize(address)", recipient);
        calls[8] = abi.encodeWithSignature("unpause()");
        calls[9] = abi.encodeWithSignature("setMinter(address)", recipient);
        calls[10] = abi.encodeWithSignature("pause()");
        calls[11] = abi.encodeWithSignature("blacklist(address)", holder);
        calls[12] = abi.encodeWithSignature("blocklist(address)", holder);
        calls[13] = abi.encodeWithSignature("freeze(address)", holder);
        calls[14] = abi.encodeWithSignature("freezeAccount(address)", holder);
        calls[15] = abi.encodeWithSignature("setBlacklist(address,bool)", holder, true);
        calls[16] = abi.encodeWithSignature("setBlocked(address,bool)", holder, true);
        calls[17] = abi.encodeWithSignature("lock(address)", holder);
        calls[18] = abi.encodeWithSignature("disableTransfers()");
        calls[19] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[20] = abi.encodeWithSignature("burnFrom(address,uint256)", holder, 1 ether);
        calls[21] = abi.encodeWithSignature("seize(address)", holder);
        calls[22] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[23] = abi.encodeWithSignature("setName(string)", "different");
        calls[24] = abi.encodeWithSignature("setSymbol(string)", "OTHER");
        calls[25] = abi.encodeWithSignature("setDecimals(uint8)", 6);

        address[3] memory callers = [address(factory), recipient, holder];
        for (uint256 i; i < callers.length; ++i) {
            for (uint256 j; j < calls.length; ++j) {
                vm.prank(callers[i]);
                (bool success,) = address(token).call(calls[j]);
                assertFalse(success, "unexpected administrative entry point");
                assertEq(token.totalSupply(), SUPPLY);
                assertEq(token.balanceOf(holder), 1_000 ether);
                assertEq(token.balanceOf(recipient), 0);
            }
        }
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 1_000 ether));
        assertEq(token.balanceOf(recipient), 1_000 ether);
        assertEq(token.name(), "IMD RISK");
        assertEq(token.symbol(), "RISK");
        assertEq(token.decimals(), 18);
    }

    function test_runtimeHasNoForbiddenOpcodesAndFitsDeploymentLimit() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4, "DELEGATECALL");
            assertTrue(op != 0xf2, "CALLCODE");
            assertTrue(op != 0xff, "SELFDESTRUCT");
        }
    }
}
