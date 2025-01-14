// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {InterchainEntry, InterchainEntryLibHarness} from "../harnesses/InterchainEntryLibHarness.sol";

import {Test} from "forge-std/Test.sol";

// solhint-disable func-name-mixedcase
// solhint-disable ordering
contract InterchainEntryLibTest is Test {
    InterchainEntryLibHarness public libHarness;

    InterchainEntry public mockEntry = InterchainEntry({
        srcChainId: 1,
        dbNonce: 2,
        entryIndex: 3,
        srcWriter: bytes32(uint256(4)),
        dataHash: bytes32(uint256(5))
    });

    function setUp() public {
        libHarness = new InterchainEntryLibHarness();
    }

    function assertEq(InterchainEntry memory actual, InterchainEntry memory expected) public pure {
        assertEq(actual.srcChainId, expected.srcChainId, "!srcChainId");
        assertEq(actual.dbNonce, expected.dbNonce, "!dbNonce");
        assertEq(actual.entryIndex, expected.entryIndex, "!entryIndex");
        assertEq(actual.srcWriter, expected.srcWriter, "!srcWriter");
        assertEq(actual.dataHash, expected.dataHash, "!dataHash");
    }

    function test_constructLocalEntry() public {
        vm.chainId(1);
        uint64 dbNonce = 2;
        uint64 entryIndex = 3;
        address srcWriter = address(4);
        bytes32 dataHash = bytes32(uint256(5));
        InterchainEntry memory actual = libHarness.constructLocalEntry(dbNonce, entryIndex, srcWriter, dataHash);
        assertEq(actual, mockEntry);
    }

    function test_constructLocalEntry(
        uint64 chainId,
        uint64 dbNonce,
        uint64 entryIndex,
        address srcWriter,
        bytes32 dataHash
    )
        public
    {
        vm.chainId(chainId);
        InterchainEntry memory expected = InterchainEntry({
            srcChainId: chainId,
            dbNonce: dbNonce,
            entryIndex: entryIndex,
            srcWriter: bytes32(uint256(uint160(srcWriter))),
            dataHash: dataHash
        });
        InterchainEntry memory actual = libHarness.constructLocalEntry(dbNonce, entryIndex, srcWriter, dataHash);
        assertEq(actual, expected);
    }

    function test_entryValue() public view {
        bytes32 expected = keccak256(abi.encode(4, 5));
        assertEq(libHarness.entryValue(mockEntry), expected);
    }

    function test_entryValue(InterchainEntry memory entry) public view {
        bytes32 expected = keccak256(abi.encode(entry.srcWriter, entry.dataHash));
        assertEq(libHarness.entryValue(entry), expected);
    }

    function test_getEntryValue() public view {
        bytes32 srcWriter = bytes32(uint256(4));
        bytes32 dataHash = bytes32(uint256(5));
        bytes32 expected = keccak256(abi.encode(srcWriter, dataHash));
        assertEq(libHarness.getEntryValue(srcWriter, dataHash), expected);
    }

    function test_getEntryValue(bytes32 srcWriter, bytes32 dataHash) public view {
        bytes32 expected = keccak256(abi.encode(srcWriter, dataHash));
        assertEq(libHarness.getEntryValue(srcWriter, dataHash), expected);
    }
}
