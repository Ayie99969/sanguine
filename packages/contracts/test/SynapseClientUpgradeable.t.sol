// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "forge-std/Test.sol";

import { SynapseClientUpgradeableHarness } from "./harnesses/SynapseClientUpgradeableHarness.sol";
import { HomeHarness } from "./harnesses/HomeHarness.sol";

import { SynapseTestWithUpdaterManager } from "./utils/SynapseTest.sol";

import { IUpdaterManager } from "../contracts/interfaces/IUpdaterManager.sol";
import { Message } from "../contracts/libs/Message.sol";

import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract SynapseClientTest is SynapseTestWithUpdaterManager {
    SynapseClientUpgradeableHarness public client;
    HomeHarness public home;

    address public constant replicaManager = address(1234567890);
    address public constant owner = address(9876543210);
    bytes32 public constant trustedSender = bytes32(uint256(1234554321));

    function setUp() public override {
        super.setUp();

        home = new HomeHarness(localDomain);
        home.initialize(IUpdaterManager(updaterManager));
        updaterManager.setHome(address(home));

        vm.label(replicaManager, "replica");
        vm.label(owner, "owner");

        SynapseClientUpgradeableHarness impl = new SynapseClientUpgradeableHarness(
            address(home),
            replicaManager
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(1337),
            bytes("")
        );
        client = SynapseClientUpgradeableHarness(address(proxy));
        client.initialize();
        client.transferOwnership(owner);
    }

    function test_constructor() public {
        assertEq(client.home(), address(home));
        assertEq(client.replicaManager(), replicaManager);
    }

    function test_cannotInitializeTwice() public {
        vm.expectRevert("Initializable: contract is already initialized");
        client.initialize();
    }

    function test_setTrustedSender() public {
        vm.prank(owner);
        client.setTrustedSender(remoteDomain, trustedSender);
        assertEq(client.trustedSender(remoteDomain), trustedSender);
    }

    function test_setTrustedSenderAsNotOwner(address _notOwner) public {
        vm.assume(_notOwner != owner);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(_notOwner);
        client.setTrustedSender(remoteDomain, trustedSender);
    }

    function test_setTrustedSenderEmptyDomain() public {
        vm.prank(owner);
        vm.expectRevert("!domain");
        client.setTrustedSender(0, trustedSender);
    }

    function test_setTrustedSenderEmptySender() public {
        vm.prank(owner);
        vm.expectRevert("!sender");
        client.setTrustedSender(remoteDomain, bytes32(0));
    }

    function test_setTrustedSenders() public {
        uint256 amount = 5;
        uint32[] memory domains = new uint32[](amount);
        bytes32[] memory senders = new bytes32[](amount);
        for (uint256 i = 0; i < amount; i++) {
            domains[i] = uint32(remoteDomain + i);
            senders[i] = bytes32(uint256(trustedSender) + i);
        }
        vm.prank(owner);
        client.setTrustedSenders(domains, senders);
        for (uint256 i = 0; i < amount; i++) {
            assertEq(client.trustedSender(domains[i]), senders[i]);
        }
    }

    function test_setTrustedSendersAsNotOwner(address _notOwner) public {
        vm.assume(_notOwner != owner);
        uint32[] memory domains = new uint32[](1);
        bytes32[] memory senders = new bytes32[](1);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(_notOwner);
        client.setTrustedSenders(domains, senders);
    }

    function test_setTrustedSendersBadArrays() public {
        uint32[] memory domains = new uint32[](1);
        bytes32[] memory senders = new bytes32[](2);
        vm.expectRevert("!arrays");
        vm.prank(owner);
        client.setTrustedSenders(domains, senders);
    }

    function test_handle() public {
        test_setTrustedSender();

        vm.prank(replicaManager);
        client.handle(remoteDomain, 0, trustedSender, bytes(""));
    }

    function test_handleNotReplica(address _notReplica) public {
        vm.assume(_notReplica != replicaManager);
        test_setTrustedSender();

        vm.prank(_notReplica);
        vm.expectRevert("!replica");
        client.handle(remoteDomain, 0, trustedSender, bytes(""));
    }

    function test_handleWrongDomain(uint32 _notRemote) public {
        vm.assume(_notRemote != remoteDomain);

        test_setTrustedSender();

        vm.prank(replicaManager);
        vm.expectRevert("!trustedSender");
        client.handle(_notRemote, 0, trustedSender, bytes(""));
    }

    function test_handleFakeDomainAndSender(uint32 _notRemote) public {
        vm.assume(_notRemote != remoteDomain);

        test_setTrustedSender();

        vm.prank(replicaManager);
        vm.expectRevert("!trustedSender");
        // trustedSender for unknown remote is bytes32(0),
        // but this still has to revert
        client.handle(_notRemote, 0, bytes32(0), bytes(""));
    }

    function test_handleWrongSender(bytes32 _notSender) public {
        vm.assume(_notSender != trustedSender);

        test_setTrustedSender();

        vm.prank(replicaManager);
        vm.expectRevert("!trustedSender");
        client.handle(remoteDomain, 0, _notSender, bytes(""));
    }

    event Dispatch(
        bytes32 indexed messageHash,
        uint256 indexed leafIndex,
        uint64 indexed destinationAndNonce,
        bytes32 committedRoot,
        bytes message
    );

    function test_send() public {
        test_setTrustedSender();
        bytes memory messageBody = hex"01030307";
        bytes memory message = Message.formatMessage(
            localDomain,
            bytes32(uint256(uint160(address(client)))),
            0,
            remoteDomain,
            trustedSender,
            messageBody
        );
        vm.expectEmit(true, true, true, true);
        emit Dispatch(keccak256(message), 0, uint64(remoteDomain) << 32, bytes32(0), message);
        client.send(remoteDomain, messageBody);
    }

    function test_sendNoRecipient() public {
        bytes memory messageBody = hex"01030307";
        vm.expectRevert("!recipient");
        client.send(remoteDomain, messageBody);
    }
}