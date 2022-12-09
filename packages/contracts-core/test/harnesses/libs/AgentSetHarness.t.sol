// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import { AgentSet } from "../../../contracts/libs/AgentSet.sol";

contract AgentSetHarness {
    using AgentSet for AgentSet.DomainAddressSet;

    AgentSet.DomainAddressSet internal set;

    function add(uint32 domain, address account) external returns (bool) {
        bool value = AgentSet.add(set, domain, account);
        return value;
    }

    function remove(uint32 domain, address account) external returns (bool) {
        bool value = AgentSet.remove(set, domain, account);
        return value;
    }

    function contains(address account) external view returns (bool) {
        bool value = AgentSet.contains(set, account);
        return value;
    }

    function contains(uint32 domain, address account) external view returns (bool) {
        bool value = AgentSet.contains(set, domain, account);
        return value;
    }

    function length(uint32 domain) external view returns (uint256) {
        uint256 value = AgentSet.length(set, domain);
        return value;
    }

    function at(uint32 domain, uint256 index) external view returns (address) {
        address value = AgentSet.at(set, domain, index);
        return value;
    }

    function values(uint32 domain) external view returns (address[] memory) {
        address[] memory value = AgentSet.values(set, domain);
        return value;
    }
}