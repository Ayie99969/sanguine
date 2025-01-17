// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ICAppV1} from "../ICAppV1.sol";

import {InterchainTxDescriptor} from "../../libs/InterchainTransaction.sol";
import {OptionsV1} from "../../libs/Options.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @notice A simple app that sends a message to the remote PingPongApp, which will respond with a message back.
/// This app can be loaded with a native asset, which will be used to pay for the messages sent.
contract PingPongApp is ICAppV1 {
    uint256 internal constant DEFAULT_GAS_LIMIT = 500_000;
    uint256 public gasLimit;

    event GasLimitSet(uint256 gasLimit);
    event PingDisrupted(uint256 counter);
    event PingReceived(uint256 counter, uint64 dbNonce, uint64 entryIndex);
    event PingSent(uint256 counter, uint64 dbNonce, uint64 entryIndex);

    constructor(address admin) ICAppV1(admin) {
        _grantRole(IC_GOVERNOR_ROLE, admin);
        _setGasLimit(DEFAULT_GAS_LIMIT);
    }

    /// @notice Enables the contract to accept native asset.
    receive() external payable {}

    /// @notice Allows the Interchain Governor to set the gas limit for the interchain messages.
    function setGasLimit(uint256 gasLimit_) external onlyRole(IC_GOVERNOR_ROLE) {
        _setGasLimit(gasLimit_);
    }

    /// @notice Allows the Admin to withdraw the native asset from the contract.
    function withdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        Address.sendValue(payable(msg.sender), address(this).balance);
    }

    /// @notice Starts the ping-pong message exchange with the remote PingPongApp.
    function startPingPong(uint64 dstChainId, uint256 counter) external {
        // Revert if the balance is lower than the message fee.
        _sendPingPongMessage(dstChainId, counter, true);
    }

    /// @notice Returns the fee to send a single ping message to the remote PingPongApp.
    function getPingFee(uint64 dstChainId) external view returns (uint256) {
        OptionsV1 memory options = OptionsV1({gasLimit: gasLimit, gasAirdrop: 0});
        bytes memory message = abi.encode(uint256(0));
        return _getInterchainFee(dstChainId, options.encodeOptionsV1(), message.length);
    }

    /// @dev Internal logic for receiving messages. At this point the validity of the message is already checked.
    function _receiveMessage(
        uint64 srcChainId,
        bytes32, // sender
        uint64 dbNonce,
        uint64 entryIndex,
        bytes calldata message
    )
        internal
        override
    {
        uint256 counter = abi.decode(message, (uint256));
        emit PingReceived(counter, dbNonce, entryIndex);
        if (counter > 0) {
            // Don't revert if the balance is low, just stop sending messages.
            _sendPingPongMessage({dstChainId: srcChainId, counter: counter - 1, lowBalanceRevert: false});
        }
    }

    /// @dev Sends a message to the PingPongApp on the remote chain.
    /// If `counter > 0`, the remote app will respond with a message to this app, decrementing the counter.
    /// Once the counter reaches 0, the remote app will not respond.
    function _sendPingPongMessage(uint64 dstChainId, uint256 counter, bool lowBalanceRevert) internal {
        OptionsV1 memory options = OptionsV1({gasLimit: gasLimit, gasAirdrop: 0});
        bytes memory message = abi.encode(counter);
        uint256 messageFee = _getMessageFee(dstChainId, options, message.length);
        if (address(this).balance < messageFee && !lowBalanceRevert) {
            emit PingDisrupted(counter);
            return;
        }
        InterchainTxDescriptor memory desc = _sendToLinkedApp(dstChainId, messageFee, options, message);
        emit PingSent(counter, desc.dbNonce, desc.entryIndex);
    }

    /// @dev Sets the gas limit for the interchain messages.
    function _setGasLimit(uint256 gasLimit_) internal {
        gasLimit = gasLimit_;
        emit GasLimitSet(gasLimit_);
    }
}
