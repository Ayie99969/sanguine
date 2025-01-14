// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {InterchainClientV1} from "../../contracts/InterchainClientV1.sol";
import {InterchainDB} from "../../contracts/InterchainDB.sol";
import {ICAppV1} from "../../contracts/apps/ICAppV1.sol";
import {SynapseExecutionServiceV1} from "../../contracts/execution/SynapseExecutionServiceV1.sol";
import {SynapseModule} from "../../contracts/modules/SynapseModule.sol";
import {SynapseGasOracleV1, ISynapseGasOracleV1} from "../../contracts/oracles/SynapseGasOracleV1.sol";

import {TypeCasts} from "../../contracts/libs/TypeCasts.sol";

import {InterchainBatchLibHarness} from "../harnesses/InterchainBatchLibHarness.sol";
import {InterchainTransactionLibHarness} from "../harnesses/InterchainTransactionLibHarness.sol";
import {VersionedPayloadLibHarness} from "../harnesses/VersionedPayloadLibHarness.sol";
import {ProxyTest} from "../proxy/ProxyTest.t.sol";

// solhint-disable custom-errors
// solhint-disable ordering
abstract contract ICSetup is ProxyTest {
    using TypeCasts for address;

    uint64 public constant SRC_CHAIN_ID = 1337;
    uint64 public constant DST_CHAIN_ID = 7331;

    uint16 public constant DB_VERSION = 1;
    uint16 public constant CLIENT_VERSION = 1;

    uint64 public constant SRC_INITIAL_DB_NONCE = 10;
    uint64 public constant DST_INITIAL_DB_NONCE = 20;

    uint256 public constant APP_OPTIMISTIC_PERIOD = 10 minutes;

    uint256 public constant INITIAL_TS = 1_704_067_200; // 2024-01-01 00:00:00 UTC

    InterchainBatchLibHarness public batchLibHarness;
    InterchainTransactionLibHarness public txLibHarness;
    VersionedPayloadLibHarness public payloadLibHarness;

    address public executionServiceImpl;
    SynapseExecutionServiceV1 public executionService;
    InterchainClientV1 public icClient;
    InterchainDB public icDB;

    SynapseModule public module;
    SynapseGasOracleV1 public gasOracle;

    address public srcApp;
    address public dstApp;

    address public guard = makeAddr("Guard");
    address public executor = makeAddr("Executor");
    address public feeRecipient = makeAddr("FeeRecipient");
    // Signer public keys, sorted by their address:
    // 2000 -> 0x5793e629c061e7FD642ab6A1b4d552CeC0e2D606
    // 1000 -> 0x7F1d642DbfD62aD4A8fA9810eA619707d09825D0
    // 3000 -> 0xf6c0eB696e44d15E8dceb3B63A6535e469Be6C62
    uint256[3] public signerPKs = [2000, 1000, 3000];

    function setUp() public virtual {
        vm.chainId(localChainId());
        vm.warp(INITIAL_TS);
        deployLibraryHarnesses();
        deployInterchainContracts();
        srcApp = deployApp();
        vm.label(srcApp, "Src App");
        dstApp = deployApp();
        vm.label(dstApp, "Dst App");
        configureInterchainContracts();
        configureLocalApp();
        initDBNonce();
    }

    function deployLibraryHarnesses() internal virtual {
        batchLibHarness = new InterchainBatchLibHarness();
        txLibHarness = new InterchainTransactionLibHarness();
        payloadLibHarness = new VersionedPayloadLibHarness();
    }

    function deployInterchainContracts() internal virtual {
        executionServiceImpl = address(new SynapseExecutionServiceV1());
        executionService = SynapseExecutionServiceV1(deployProxy(executionServiceImpl));
        icDB = new InterchainDB();
        icClient = new InterchainClientV1({interchainDB: address(icDB), owner_: address(this)});
        module = new SynapseModule({interchainDB: address(icDB), owner_: address(this)});
        gasOracle = new SynapseGasOracleV1(address(this));
    }

    /// @dev Should deploy the tested app and return its address.
    function deployApp() internal virtual returns (address);

    function configureInterchainContracts() internal virtual {
        configureExecutionService();
        configureInterchainClient();
        configureSynapseModule();
        configureSynapseGasOracle();
    }

    function configureExecutionService() internal virtual {
        executionService.initialize(address(this));
        executionService.grantRole(executionService.GOVERNOR_ROLE(), address(this));
        executionService.setExecutorEOA(executor);
        executionService.setGasOracle(address(gasOracle));
        executionService.grantRole(executionService.IC_CLIENT_ROLE(), address(icClient));
    }

    function configureInterchainClient() internal virtual {
        // For simplicity, we assume that the clients are deployed to the same address on both chains.
        bytes32 linkedClient = address(icClient).addressToBytes32();
        icClient.setLinkedClient(remoteChainId(), linkedClient);
        icClient.setDefaultGuard(guard);
    }

    function configureSynapseModule() internal virtual {
        module.setClaimerFraction(0.01e18); // 1%
        module.setFeeRecipient(feeRecipient);
        module.setGasOracle(address(gasOracle));
        module.setThreshold(signerPKs.length);
        for (uint256 i = 0; i < signerPKs.length; i++) {
            module.addVerifier(vm.addr(signerPKs[i]));
        }
    }

    function configureSynapseGasOracle() internal virtual {
        gasOracle.setLocalNativePrice(getGasDataFixture(localChainId()).nativePrice);
        gasOracle.setRemoteGasData(remoteChainId(), getGasDataFixture(remoteChainId()));
    }

    function configureLocalApp() internal virtual {
        address app = localApp();
        // For simplicity, we assume that the apps are deployed to the same address on both chains.
        ICAppV1(app).linkRemoteAppEVM(remoteChainId(), remoteApp());
        ICAppV1(app).addTrustedModule(address(module));
        ICAppV1(app).setAppConfigV1({requiredResponses: 1, optimisticPeriod: APP_OPTIMISTIC_PERIOD});
        ICAppV1(app).setExecutionService(address(executionService));
        ICAppV1(app).addInterchainClient({client: address(icClient), updateLatest: true});
    }

    function initDBNonce() internal virtual {
        // Write some random data to the DB to increase the nonce.
        uint256 start = icDB.getDBNonce();
        uint256 end = isSourceChainTest() ? SRC_INITIAL_DB_NONCE : DST_INITIAL_DB_NONCE;
        for (uint256 i = start; i < end; i++) {
            address writer = makeAddr(string.concat("Writer ", vm.toString(localChainId()), "-", vm.toString(i)));
            bytes32 data = keccak256(abi.encode(localChainId(), i));
            vm.prank(writer);
            icDB.writeEntry(data);
        }
        // Sanity check
        require(icDB.getDBNonce() == end, "DB nonce not increased");
    }

    function getGasDataFixture(uint64 chainId)
        internal
        view
        virtual
        returns (ISynapseGasOracleV1.RemoteGasData memory gasFixture)
    {
        if (isSourceChain(chainId)) {
            gasFixture.calldataPrice = 100 gwei;
            gasFixture.gasPrice = 1 gwei;
            gasFixture.nativePrice = 0.1 ether;
        } else {
            gasFixture.calldataPrice = 0.1 gwei;
            gasFixture.gasPrice = 50 gwei;
            gasFixture.nativePrice = 1 ether;
        }
    }

    function isSourceChainTest() internal view returns (bool) {
        return isSourceChain(localChainId());
    }

    function isSourceChain(uint64 chainId) internal pure returns (bool) {
        if (chainId == SRC_CHAIN_ID) {
            return true;
        } else if (chainId == DST_CHAIN_ID) {
            return false;
        } else {
            revert("Invalid chainId");
        }
    }

    function localApp() internal view returns (address) {
        return isSourceChainTest() ? srcApp : dstApp;
    }

    function remoteApp() internal view returns (address) {
        return isSourceChainTest() ? dstApp : srcApp;
    }

    /// @notice Should return either `SRC_CHAIN_ID` or `DST_CHAIN_ID`.
    function localChainId() internal view virtual returns (uint64);
    /// @notice Should return either `SRC_CHAIN_ID` or `DST_CHAIN_ID`.
    function remoteChainId() internal view virtual returns (uint64);
}
