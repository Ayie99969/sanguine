// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ByteString } from "./ByteString.sol";
import { SynapseTypes } from "./SynapseTypes.sol";
import { TypedMemView } from "./TypedMemView.sol";

library SystemCall {
    using ByteString for bytes29;
    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    /**
     * @dev Custom address, used for sending and receiving system messages.
     *      Origin is supposed to dispatch messages from SystemRouter
     *      as if they were sent by this address.
     *      Destination is supposed to reroute messages for this address to SystemRouter.
     *
     *      Note: all bits except for lower 20 bytes are set to 1.
     *      Note: TypeCasts.bytes32ToAddress(SYSTEM_ROUTER) == address(0)
     */
    bytes32 internal constant SYSTEM_ROUTER = bytes32(type(uint256).max << 160);

    /**
     * @dev SystemCall memory layout
     * [000 .. 001): recipient      uint8   1 bytes
     * [001 .. END]: payload        bytes   ? bytes
     */

    uint256 internal constant OFFSET_CALL_RECIPIENT = 0;
    uint256 internal constant OFFSET_CALL_PAYLOAD = 1;

    /**
     * @dev System Router is supposed to append (origin, caller) to the given payload,
     * meaning for a valid system call payload there have to exist at least two arguments,
     * occupying at least two words in total.
     */
    uint256 internal constant PAYLOAD_MIN_ARGUMENT_WORDS = 2;

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                              MODIFIERS                               ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    modifier onlyType(bytes29 _view, uint40 _type) {
        _view.assertType(_type);
        _;
    }

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                              FORMATTERS                              ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    /**
     * @notice Returns a properly typed bytes29 pointer for a system call payload.
     */
    function castToSystemCall(bytes memory _payload) internal pure returns (bytes29) {
        return _payload.ref(SynapseTypes.SYSTEM_CALL);
    }

    /**
     * @notice Returns a formatted System Call payload with provided fields
     * @param _systemRecipient  System Contract to receive message
     *                          (see ISystemRouter.SystemEntity)
     * @param _payload          Payload for call on destination chain
     * @return Formatted System Call
     **/
    function formatSystemCall(uint8 _systemRecipient, bytes memory _payload)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(_systemRecipient, _payload);
    }

    /**
     * @notice Checks that a payload is a formatted System Call.
     */
    function isSystemCall(bytes29 _view) internal pure returns (bool) {
        // Payload needs to exist (system calls are never done via fallback function)
        if (_view.len() < OFFSET_CALL_PAYLOAD) return false;
        bytes29 payload = _callPayload(_view);
        // Payload needs to be a proper call payload
        if (!payload.isCallPayload()) return false;
        // Payload needs to have at least this amount of argument words
        return payload.argumentWords() >= PAYLOAD_MIN_ARGUMENT_WORDS;
    }

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                         SYSTEM CALL SLICING                          ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    /**
     * @notice Returns int value of System Call's recipient (see ISystemRouter.SystemEntity).
     */
    function callRecipient(bytes29 _view)
        internal
        pure
        onlyType(_view, SynapseTypes.SYSTEM_CALL)
        returns (uint8)
    {
        return uint8(_view.indexUint({ _index: OFFSET_CALL_RECIPIENT, _bytes: 1 }));
    }

    /**
     * @notice Returns System Call's payload.
     */
    function callPayload(bytes29 _view)
        internal
        pure
        onlyType(_view, SynapseTypes.SYSTEM_CALL)
        returns (bytes29)
    {
        return _callPayload(_view);
    }

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                          PRIVATE FUNCTIONS                           ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    /**
     * @notice Returns System Call's payload WITHOUT checking the view type.
     * To be used in `isSystemCall`, where type check is not necessary.
     */
    function _callPayload(bytes29 _view) private pure returns (bytes29) {
        return _view.sliceFrom({ _index: OFFSET_CALL_PAYLOAD, newType: SynapseTypes.CALL_PAYLOAD });
    }
}