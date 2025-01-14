// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import {PathFinder} from "../base/PathFinder.sol";
import {StringUtils} from "../libs/StringUtils.sol";

import {stdJson} from "forge-std/StdJson.sol";

abstract contract DataReader is PathFinder {
    using stdJson for string;
    using StringUtils for *;

    // ════════════════════════════════════════════ GENERIC DATA READS ═════════════════════════════════════════════════

    /// @notice Reads a file from the filesystem and returns its content.
    /// @dev Returns an empty string or reverts if the file is not found based on the flag.
    function readFile(string memory path, bool revertIfNotFound) internal view returns (string memory) {
        try vm.readFile(path) returns (string memory content) {
            return content;
        } catch {
            if (revertIfNotFound) revert(StringUtils.concat("DataReader: failed to read file: ", path));
            return "";
        }
    }

    /// @notice Tries to read the full contract artifact JSON generated by forge.
    /// @dev Returns an empty string or reverts if the artifact is not found based on the flag.
    function readContractArtifact(
        string memory contractName,
        bool revertIfNotFound
    )
        internal
        view
        returns (string memory)
    {
        return readFile(getArtifactFN(contractName), revertIfNotFound);
    }

    /// @notice Returns the saved deployment artifact JSON for a contract.
    /// @dev Returns an empty string or reverts if the artifact is not found based on the flag.
    function readDeploymentArtifact(
        string memory chain,
        string memory contractName,
        bool revertIfNotFound
    )
        internal
        view
        returns (string memory artifact)
    {
        return readFile(getDeploymentFN(chain, contractName), revertIfNotFound);
    }

    /// @notice Returns the deployment configuration JSON for a contract.
    /// @dev Returns an empty string or reverts if the artifact is not found based on the flag.
    function readDeployConfig(
        string memory chain,
        string memory contractName,
        bool revertIfNotFound
    )
        internal
        view
        returns (string memory deployConfig)
    {
        return readFile(getDeployConfigFN(chain, contractName), revertIfNotFound);
    }

    /// @notice Returns the global deployment configuration JSON.
    /// @dev Returns an empty string or reverts if the artifact is not found based on the flag.
    function readGlobalDeployConfig(
        string memory contractName,
        string memory globalProperty,
        bool revertIfNotFound
    )
        internal
        view
        returns (string memory deployConfig)
    {
        return readFile(getGlobalDeployConfigFN(contractName, globalProperty), revertIfNotFound);
    }

    // ════════════════════════════════════════════ SPECIFIC DATA READS ════════════════════════════════════════════════

    /// @notice Returns the contract bytecode extracted from the artifact generated by forge.
    /// @dev Returns an empty string or reverts if the artifact is not found based on the flag.
    function getContractBytecode(
        string memory contractName,
        bool revertIfNotFound
    )
        internal
        view
        returns (bytes memory bytecode)
    {
        string memory artifact = readContractArtifact(contractName, revertIfNotFound);
        if (artifact.length() == 0) return "";
        return artifact.readBytes(".bytecode.object");
    }

    /// @notice Returns the deployment address for a contract on a given chain.
    /// @dev Returns address(0) or reverts if the artifact is not found based on the flag.
    function getDeploymentAddress(
        string memory chain,
        string memory contractName,
        bool revertIfNotFound
    )
        internal
        view
        returns (address)
    {
        // This will revert if the artifact is not found and flag is set to true
        string memory deploymentArtifact = readDeploymentArtifact(chain, contractName, revertIfNotFound);
        if (deploymentArtifact.length() == 0) return address(0);
        return deploymentArtifact.readAddress(".address");
    }

    /// @notice Checks if a contract is deployed on a given chain without reverting.
    function isDeployed(string memory chain, string memory contractName) internal view returns (bool) {
        return getDeploymentAddress(chain, contractName, false) != address(0);
    }
}
