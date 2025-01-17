// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {InterchainClientV1Events} from "./events/InterchainClientV1Events.sol";

import {IExecutionService} from "./interfaces/IExecutionService.sol";
import {IInterchainApp} from "./interfaces/IInterchainApp.sol";
import {IInterchainClientV1} from "./interfaces/IInterchainClientV1.sol";
import {IInterchainDB} from "./interfaces/IInterchainDB.sol";

import {AppConfigV1, AppConfigLib, APP_CONFIG_GUARD_DISABLED, APP_CONFIG_GUARD_DEFAULT} from "./libs/AppConfig.sol";
import {BatchingV1Lib} from "./libs/BatchingV1.sol";
import {InterchainBatch, BATCH_UNVERIFIED, BATCH_CONFLICT} from "./libs/InterchainBatch.sol";
import {
    InterchainTransaction, InterchainTxDescriptor, InterchainTransactionLib
} from "./libs/InterchainTransaction.sol";
import {OptionsLib, OptionsV1} from "./libs/Options.sol";
import {TypeCasts} from "./libs/TypeCasts.sol";
import {VersionedPayloadLib} from "./libs/VersionedPayload.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title InterchainClientV1
 * @dev Implements the operations of the Interchain Execution Layer.
 */
contract InterchainClientV1 is Ownable, InterchainClientV1Events, IInterchainClientV1 {
    using AppConfigLib for bytes;
    using OptionsLib for bytes;
    using TypeCasts for address;
    using TypeCasts for bytes32;
    using VersionedPayloadLib for bytes;

    /// @notice Version of the InterchainClient contract. Sent and received transactions must have the same version.
    uint16 public constant CLIENT_VERSION = 1;

    /// @notice Address of the InterchainDB contract, set at the time of deployment.
    address public immutable INTERCHAIN_DB;

    /// @notice Address of the Guard module used to verify the validity of batches.
    /// Note: batches marked as invalid by the Guard could not be used for message execution,
    /// if the app opts in to use the Guard.
    address public defaultGuard;

    /// @dev Address of the InterchainClient contract on the remote chain
    mapping(uint64 chainId => bytes32 remoteClient) internal _linkedClient;
    /// @dev Executor address that completed the transaction. Address(0) if not executed yet.
    mapping(bytes32 transactionId => address executor) internal _txExecutor;

    constructor(address interchainDB, address owner_) Ownable(owner_) {
        INTERCHAIN_DB = interchainDB;
    }

    // @inheritdoc IInterchainClientV1
    function setDefaultGuard(address guard) external onlyOwner {
        if (guard == address(0)) {
            revert InterchainClientV1__GuardZeroAddress();
        }
        defaultGuard = guard;
        emit DefaultGuardSet(guard);
    }

    // @inheritdoc IInterchainClientV1
    function setLinkedClient(uint64 chainId, bytes32 client) external onlyOwner {
        _linkedClient[chainId] = client;
        emit LinkedClientSet(chainId, client);
    }

    // @inheritdoc IInterchainClientV1
    function interchainSend(
        uint64 dstChainId,
        bytes32 receiver,
        address srcExecutionService,
        address[] calldata srcModules,
        bytes calldata options,
        bytes calldata message
    )
        external
        payable
        returns (InterchainTxDescriptor memory desc)
    {
        return _interchainSend(dstChainId, receiver, srcExecutionService, srcModules, options, message);
    }

    // @inheritdoc IInterchainClientV1
    function interchainSendEVM(
        uint64 dstChainId,
        address receiver,
        address srcExecutionService,
        address[] calldata srcModules,
        bytes calldata options,
        bytes calldata message
    )
        external
        payable
        returns (InterchainTxDescriptor memory desc)
    {
        bytes32 receiverBytes32 = receiver.addressToBytes32();
        return _interchainSend(dstChainId, receiverBytes32, srcExecutionService, srcModules, options, message);
    }

    // @inheritdoc IInterchainClientV1
    function interchainExecute(
        uint256 gasLimit,
        bytes calldata transaction,
        bytes32[] calldata proof
    )
        external
        payable
    {
        InterchainTransaction memory icTx = _assertCorrectTransaction(transaction);
        bytes32 transactionId = keccak256(transaction);
        _assertExecutable(icTx, transactionId, proof);
        _txExecutor[transactionId] = msg.sender;

        OptionsV1 memory decodedOptions = icTx.options.decodeOptionsV1();
        if (msg.value != decodedOptions.gasAirdrop) {
            revert InterchainClientV1__MsgValueMismatch(msg.value, decodedOptions.gasAirdrop);
        }
        // We should always use at least as much as the requested gas limit.
        // The executor can specify a higher gas limit if they wanted.
        if (decodedOptions.gasLimit > gasLimit) gasLimit = decodedOptions.gasLimit;
        // Check the the Executor has provided big enough gas limit for the whole transaction.
        uint256 gasLeft = gasleft();
        if (gasLeft <= gasLimit) {
            revert InterchainClientV1__GasLeftBelowMin(gasLeft, gasLimit);
        }
        // Pass the full msg.value to the app: we have already checked that it matches the requested gas airdrop.
        IInterchainApp(icTx.dstReceiver.bytes32ToAddress()).appReceive{gas: gasLimit, value: msg.value}({
            srcChainId: icTx.srcChainId,
            sender: icTx.srcSender,
            dbNonce: icTx.dbNonce,
            entryIndex: icTx.entryIndex,
            message: icTx.message
        });
        emit InterchainTransactionReceived(
            transactionId, icTx.dbNonce, icTx.entryIndex, icTx.srcChainId, icTx.srcSender, icTx.dstReceiver
        );
    }

    /// @inheritdoc IInterchainClientV1
    function writeExecutionProof(bytes32 transactionId) external returns (uint64 dbNonce, uint64 entryIndex) {
        address executor = _txExecutor[transactionId];
        if (executor == address(0)) {
            revert InterchainClientV1__TxNotExecuted(transactionId);
        }
        bytes memory proof = abi.encode(transactionId, executor);
        (dbNonce, entryIndex) = IInterchainDB(INTERCHAIN_DB).writeEntry(keccak256(proof));
        emit ExecutionProofWritten(transactionId, dbNonce, entryIndex, executor);
    }

    // ═══════════════════════════════════════════════════ VIEWS ═══════════════════════════════════════════════════════

    // @inheritdoc IInterchainClientV1
    function isExecutable(bytes calldata encodedTx, bytes32[] calldata proof) external view returns (bool) {
        InterchainTransaction memory icTx = _assertCorrectTransaction(encodedTx);
        // Check that options could be decoded
        icTx.options.decodeOptionsV1();
        bytes32 transactionId = keccak256(encodedTx);
        _assertExecutable(icTx, transactionId, proof);
        return true;
    }

    // @inheritdoc IInterchainClientV1
    // solhint-disable-next-line code-complexity
    function getTxReadinessV1(
        InterchainTransaction memory icTx,
        bytes32[] calldata proof
    )
        external
        view
        returns (TxReadiness status, bytes32 firstArg, bytes32 secondArg)
    {
        bytes memory encodedTx = encodeTransaction(icTx);
        try this.isExecutable(encodedTx, proof) returns (bool) {
            return (TxReadiness.Ready, 0, 0);
        } catch (bytes memory errorData) {
            bytes4 selector;
            (selector, firstArg, secondArg) = _decodeRevertData(errorData);
            if (selector == InterchainClientV1__TxAlreadyExecuted.selector) {
                status = TxReadiness.AlreadyExecuted;
            } else if (selector == InterchainClientV1__ResponsesAmountBelowMin.selector) {
                status = TxReadiness.BatchAwaitingResponses;
            } else if (selector == InterchainClientV1__BatchConflict.selector) {
                status = TxReadiness.BatchConflict;
            } else if (selector == InterchainClientV1__ReceiverNotICApp.selector) {
                status = TxReadiness.ReceiverNotICApp;
            } else if (selector == InterchainClientV1__ReceiverZeroRequiredResponses.selector) {
                status = TxReadiness.ReceiverZeroRequiredResponses;
            } else if (selector == InterchainClientV1__DstChainIdNotLocal.selector) {
                status = TxReadiness.TxWrongDstChainId;
            } else {
                status = TxReadiness.UndeterminedRevert;
                firstArg = 0;
                secondArg = 0;
            }
        }
    }

    // @inheritdoc IInterchainClientV1
    function getExecutor(bytes calldata encodedTx) external view returns (address) {
        return _txExecutor[keccak256(encodedTx)];
    }

    // @inheritdoc IInterchainClientV1
    function getExecutorById(bytes32 transactionId) external view returns (address) {
        return _txExecutor[transactionId];
    }

    // @inheritdoc IInterchainClientV1
    function getInterchainFee(
        uint64 dstChainId,
        address srcExecutionService,
        address[] calldata srcModules,
        bytes calldata options,
        uint256 messageLen
    )
        external
        view
        returns (uint256 fee)
    {
        _assertLinkedClient(dstChainId);
        if (srcExecutionService == address(0)) {
            revert InterchainClientV1__ExecutionServiceZeroAddress();
        }
        // Check that options could be decoded on destination chain
        options.decodeOptionsV1();
        // Verification fee from InterchainDB
        fee = IInterchainDB(INTERCHAIN_DB).getInterchainFee(dstChainId, srcModules);
        // Add execution fee from ExecutionService
        uint256 payloadSize = InterchainTransactionLib.payloadSize(options.length, messageLen);
        fee += IExecutionService(srcExecutionService).getExecutionFee(dstChainId, payloadSize, options);
    }

    /// @inheritdoc IInterchainClientV1
    function getLinkedClient(uint64 chainId) external view returns (bytes32) {
        if (chainId == block.chainid) {
            revert InterchainClientV1__ChainIdNotRemote(chainId);
        }
        return _linkedClient[chainId];
    }

    /// @inheritdoc IInterchainClientV1
    function getLinkedClientEVM(uint64 chainId) external view returns (address linkedClientEVM) {
        if (chainId == block.chainid) {
            revert InterchainClientV1__ChainIdNotRemote(chainId);
        }
        bytes32 linkedClient = _linkedClient[chainId];
        linkedClientEVM = linkedClient.bytes32ToAddress();
        // Check that the linked client address fits into the EVM address space
        if (linkedClientEVM.addressToBytes32() != linkedClient) {
            revert InterchainClientV1__LinkedClientNotEVM(linkedClient);
        }
    }

    /// @notice Decodes the encoded options data into a OptionsV1 struct.
    function decodeOptions(bytes memory encodedOptions) external view returns (OptionsV1 memory) {
        return encodedOptions.decodeOptionsV1();
    }

    /// @notice Gets the V1 app config and trusted modules for the receiving app.
    function getAppReceivingConfigV1(address receiver)
        public
        view
        returns (AppConfigV1 memory config, address[] memory modules)
    {
        // First, check that receiver is a contract
        if (receiver.code.length == 0) {
            revert InterchainClientV1__ReceiverNotICApp(receiver);
        }
        // Then, use a low-level static call to get the config and modules
        (bool success, bytes memory returnData) =
            receiver.staticcall(abi.encodeCall(IInterchainApp.getReceivingConfig, ()));
        if (!success || returnData.length == 0) {
            revert InterchainClientV1__ReceiverNotICApp(receiver);
        }
        bytes memory encodedConfig;
        (encodedConfig, modules) = abi.decode(returnData, (bytes, address[]));
        config = encodedConfig.decodeAppConfigV1();
    }

    /// @notice Encodes the transaction data into a bytes format.
    function encodeTransaction(InterchainTransaction memory icTx) public pure returns (bytes memory) {
        return VersionedPayloadLib.encodeVersionedPayload({
            version: CLIENT_VERSION,
            payload: InterchainTransactionLib.encodeTransaction(icTx)
        });
    }

    // ═════════════════════════════════════════════════ INTERNAL ══════════════════════════════════════════════════════

    /// @dev Internal logic for sending a message to another chain.
    function _interchainSend(
        uint64 dstChainId,
        bytes32 receiver,
        address srcExecutionService,
        address[] calldata srcModules,
        bytes calldata options,
        bytes calldata message
    )
        internal
        returns (InterchainTxDescriptor memory desc)
    {
        _assertLinkedClient(dstChainId);
        if (receiver == 0) {
            revert InterchainClientV1__ReceiverZeroAddress();
        }
        if (srcExecutionService == address(0)) {
            revert InterchainClientV1__ExecutionServiceZeroAddress();
        }
        // Check that options could be decoded on destination chain
        options.decodeOptionsV1();
        uint256 verificationFee = IInterchainDB(INTERCHAIN_DB).getInterchainFee(dstChainId, srcModules);
        if (msg.value < verificationFee) {
            revert InterchainClientV1__FeeAmountBelowMin(msg.value, verificationFee);
        }
        (desc.dbNonce, desc.entryIndex) = IInterchainDB(INTERCHAIN_DB).getNextEntryIndex();
        InterchainTransaction memory icTx = InterchainTransactionLib.constructLocalTransaction({
            srcSender: msg.sender,
            dstReceiver: receiver,
            dstChainId: dstChainId,
            dbNonce: desc.dbNonce,
            entryIndex: desc.entryIndex,
            options: options,
            message: message
        });
        desc.transactionId = keccak256(encodeTransaction(icTx));
        // Sanity check: nonce returned from DB should match the nonce used to construct the transaction
        {
            (uint64 dbNonce, uint64 entryIndex) = IInterchainDB(INTERCHAIN_DB).writeEntryWithVerification{
                value: verificationFee
            }(icTx.dstChainId, desc.transactionId, srcModules);
            assert(dbNonce == desc.dbNonce && entryIndex == desc.entryIndex);
        }
        uint256 executionFee;
        unchecked {
            executionFee = msg.value - verificationFee;
        }
        IExecutionService(srcExecutionService).requestTxExecution{value: executionFee}({
            dstChainId: icTx.dstChainId,
            txPayloadSize: InterchainTransactionLib.payloadSize(options.length, message.length),
            transactionId: desc.transactionId,
            options: options
        });
        emit InterchainTransactionSent(
            desc.transactionId,
            icTx.dbNonce,
            icTx.entryIndex,
            icTx.dstChainId,
            icTx.srcSender,
            icTx.dstReceiver,
            verificationFee,
            executionFee,
            icTx.options,
            icTx.message
        );
    }

    // ══════════════════════════════════════════════ INTERNAL VIEWS ═══════════════════════════════════════════════════

    /// @dev Asserts that the transaction is executable.
    function _assertExecutable(
        InterchainTransaction memory icTx,
        bytes32 transactionId,
        bytes32[] calldata proof
    )
        internal
        view
    {
        bytes32 linkedClient = _assertLinkedClient(icTx.srcChainId);
        if (_txExecutor[transactionId] != address(0)) {
            revert InterchainClientV1__TxAlreadyExecuted(transactionId);
        }
        // Construct expected batch based on interchain transaction data
        InterchainBatch memory batch = InterchainBatch({
            srcChainId: icTx.srcChainId,
            dbNonce: icTx.dbNonce,
            batchRoot: BatchingV1Lib.getBatchRoot({
                srcWriter: linkedClient,
                dataHash: transactionId,
                entryIndex: icTx.entryIndex,
                proof: proof
            })
        });
        address receiver = icTx.dstReceiver.bytes32ToAddress();
        (AppConfigV1 memory appConfig, address[] memory approvedModules) = getAppReceivingConfigV1(receiver);
        if (appConfig.requiredResponses == 0) {
            revert InterchainClientV1__ReceiverZeroRequiredResponses(receiver);
        }
        // Verify against the Guard if the app opts in to use it
        _assertNoGuardConflict(_getGuard(appConfig), batch);
        uint256 finalizedResponses = _getFinalizedResponsesCount(approvedModules, batch, appConfig.optimisticPeriod);
        if (finalizedResponses < appConfig.requiredResponses) {
            revert InterchainClientV1__ResponsesAmountBelowMin(finalizedResponses, appConfig.requiredResponses);
        }
    }

    /// @dev Asserts that the chain is linked and returns the linked client address.
    function _assertLinkedClient(uint64 chainId) internal view returns (bytes32 linkedClient) {
        if (chainId == block.chainid) {
            revert InterchainClientV1__ChainIdNotRemote(chainId);
        }
        linkedClient = _linkedClient[chainId];
        if (linkedClient == 0) {
            revert InterchainClientV1__ChainIdNotLinked(chainId);
        }
    }

    /// @dev Asserts that the Guard has not submitted a conflicting batch.
    function _assertNoGuardConflict(address guard, InterchainBatch memory batch) internal view {
        if (guard != address(0)) {
            uint256 confirmedAt = IInterchainDB(INTERCHAIN_DB).checkBatchVerification(guard, batch);
            if (confirmedAt == BATCH_CONFLICT) {
                revert InterchainClientV1__BatchConflict(guard);
            }
        }
    }

    /// @dev Returns the Guard address to use for the given app config.
    function _getGuard(AppConfigV1 memory appConfig) internal view returns (address) {
        if (appConfig.guardFlag == APP_CONFIG_GUARD_DISABLED) {
            return address(0);
        }
        if (appConfig.guardFlag == APP_CONFIG_GUARD_DEFAULT) {
            return defaultGuard;
        }
        return appConfig.guard;
    }

    /// @dev Counts the number of finalized responses for the given batch.
    /// Note: Reverts if a conflicting batch has been verified by any of the approved modules.
    function _getFinalizedResponsesCount(
        address[] memory approvedModules,
        InterchainBatch memory batch,
        uint256 optimisticPeriod
    )
        internal
        view
        returns (uint256 finalizedResponses)
    {
        for (uint256 i = 0; i < approvedModules.length; ++i) {
            address module = approvedModules[i];
            uint256 confirmedAt = IInterchainDB(INTERCHAIN_DB).checkBatchVerification(module, batch);
            // No-op if the module has not verified anything with the same batch key
            if (confirmedAt == BATCH_UNVERIFIED) {
                continue;
            }
            // Revert if the module has verified a conflicting batch with the same batch key
            if (confirmedAt == BATCH_CONFLICT) {
                revert InterchainClientV1__BatchConflict(module);
            }
            // The module has verified this exact batch, check if optimistic period has passed
            if (confirmedAt + optimisticPeriod < block.timestamp) {
                unchecked {
                    ++finalizedResponses;
                }
            }
        }
    }

    /// @dev Asserts that the transaction version is correct and that the transaction is for the current chain.
    /// Note: returns the decoded transaction for chaining purposes.
    function _assertCorrectTransaction(bytes calldata versionedTx)
        internal
        view
        returns (InterchainTransaction memory icTx)
    {
        uint16 version = versionedTx.getVersion();
        if (version != CLIENT_VERSION) {
            revert InterchainClientV1__TxVersionMismatch(version, CLIENT_VERSION);
        }
        icTx = InterchainTransactionLib.decodeTransaction(versionedTx.getPayload());
        if (icTx.dstChainId != block.chainid) {
            revert InterchainClientV1__DstChainIdNotLocal(icTx.dstChainId);
        }
    }

    // solhint-disable no-inline-assembly
    /// @dev Decodes the revert data into a selector and two arguments.
    /// Zero values are returned if the revert data is not long enough.
    /// Note: this is only used in `getTxReadinessV1` to decode the revert data,
    /// so usage of assembly is not a security risk.
    function _decodeRevertData(bytes memory revertData)
        internal
        pure
        returns (bytes4 selector, bytes32 firstArg, bytes32 secondArg)
    {
        // The easiest way to load the bytes chunks onto the stack is to use assembly.
        // Each time we try to load a value, we check if the revert data is long enough.
        // We add 0x20 to skip the length field of the revert data.
        if (revertData.length >= 4) {
            // Load the first 32 bytes, then apply the mask that has only the 4 highest bytes set.
            // There is no need to shift, as `bytesN` variables are right-aligned.
            // https://github.com/ProjectOpenSea/seaport/blob/2ff6ea37/contracts/helpers/SeaportRouter.sol#L161-L175
            selector = bytes4(0xFFFFFFFF);
            assembly {
                selector := and(mload(add(revertData, 0x20)), selector)
            }
        }
        if (revertData.length >= 36) {
            // Skip the length field + selector to get the 32 bytes of the first argument.
            assembly {
                firstArg := mload(add(revertData, 0x24))
            }
        }
        if (revertData.length >= 68) {
            // Skip the length field + selector + first argument to get the 32 bytes of the second argument.
            assembly {
                secondArg := mload(add(revertData, 0x44))
            }
        }
    }
}
