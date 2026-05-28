# Veera Token

This repository contains the smart contracts for the Veera token. It is built using [Foundry](https://getfoundry.sh/) and [OpenZeppelin](https://www.openzeppelin.com/) standards.

The architecture is designed with **security** and **future interoperability** (native bridging) in mind.

## 0. Deployments

The token is deployed to the following chains:

### Base
| Network | Address |
| :--- | :--- |
| **Base Mainnet** | [0xf9cc3c5ca95cc4d034216b41328ae0d6136053d6](https://basescan.org/address/0xf9cc3c5ca95cc4d034216b41328ae0d6136053d6) |
| **Base Sepolia** | [0xb8df343bb4b648732c2c90df3276f97e46ee0bea](https://sepolia.basescan.org/address/0xb8df343bb4b648732c2c90df3276f97e46ee0bea) |

### BNB Smart Chain (BSC)
| Network | Address |
| :--- | :--- |
| **BSC Mainnet** | *Not yet deployed* |
| **BSC Testnet** | *Not yet deployed* |

**Note:** On Base, the full initial supply (1B tokens) is minted at deployment. On BSC, the initial supply is **0**

## 1. Architecture & Design Decisions

### Core Standards
* **ERC20:** Standard fungible token implementation.
* **ERC20Burnable:** Allows supply to be managed. This is **critical** for future cross-chain bridging (Lock-and-Mint / Burn-and-Mint).
* **ERC20Permit:** Enables gasless approvals (EIP-2612), enabling sponsored gas fees for a seamless UX.
* **ERC20Pausable:** *Not in use.* Emergency stop mechanism to freeze transfers in the event of a critical security incident. **Note:** Pausing only affects token transfers; minting and burning operations continue to function normally.

### Access Control Strategy

We use `AccessControl` instead of `Ownable` to prevent "Vendor Lock-in" with bridge providers. This decoupling allows us to grant specific permissions to external protocols without surrendering admin control.

| Role | Intended Holder | Capabilities |
| :--- | :--- | :--- |
| **DEFAULT_ADMIN_ROLE** | **Gnosis Safe** | Can grant/revoke roles. The supreme authority. |
| **MINTER_ROLE** | **Gnosis Safe** | Can mint new tokens. |
| **MINTER_ROLE** (Future) | **Bridge Adapter** | Future bridges will be granted this role to burn/mint tokens when bridging to/from other chains. |
| **PAUSER_ROLE** (Disabled) | **Gnosis Safe** | Can pause/unpause all token transfers. |

---

## 2. Configuration

### Environment Variables
Copy `.env.example` to `.env` and set the following:

* `BASE_RPC_URL`: RPC endpoint for the target network (Base or BSC — see [Supported Networks](#supported-networks) below).
* `ETHERSCAN_API_KEY`: API key used to verify source code on the block explorer (BaseScan or BscScan, depending on the target chain). See [Creating an Explorer API Key](#creating-an-explorer-api-key) for setup instructions.

### Supported Networks

The contract auto-detects the target chain via `block.chainid`. The same `BASE_RPC_URL` environment variable is used regardless of the target network — point it at the appropriate RPC endpoint.

| Chain | Chain ID | RPC Endpoint (example) | Explorer |
| :--- | :--- | :--- | :--- |
| Base Mainnet | 8453 | `https://mainnet.base.org` | [basescan.org](https://basescan.org) |
| Base Sepolia | 84532 | `https://sepolia.base.org` | [sepolia.basescan.org](https://sepolia.basescan.org) |
| BSC Mainnet | 56 | `https://bsc-dataseed.binance.org` | [bscscan.com](https://bscscan.com) |
| BSC Testnet | 97 | `https://data-seed-prebsc-1-s1.binance.org:8545` | [testnet.bscscan.com](https://testnet.bscscan.com) |

### Creating an Explorer API Key

An API key is required for automatic source code verification during deployment. You need a key from the explorer matching your target chain.


1. Go to [etherscan.io](https://https://etherscan.io/) and create an account (or sign in).
2. Navigate to **My Account** → **API Keys** (or go directly to [basescan.org/myapikey](https://basescan.org/myapikey)).
3. Click **Add** to create a new API key.
4. Copy the key and set it as `ETHERSCAN_API_KEY` in your `.env` file.


### Hardcoded Parameters

The following immutable values are defined in `script/HelperConfig.s.sol`:
* **Name:** `Veera Token`
* **Symbol:** `VEERA`
* **Initial Supply:** `1,000,000,000` on Base (minted to the Admin immediately) / `0` on BSC
* **Maximum Supply Cap:** `1,000,000,000` (Same as initial supply, prevents unlimited inflation, [enforced by ERC20Capped](src/Veera.sol#L36))
* **Initial Admin:** Chain-specific address (see table below). Must be a Gnosis Safe for Mainnet. **Must be checksummed.**

| Chain | Admin Address |
| :--- | :--- |
| Base Mainnet | `0xd2b8875b840D3BD574E1e6b440888e110632A0FD` |
| Base Sepolia | `0xfEDB58C317d347e265990888919879a5d392a12c` |
| BSC Mainnet | `0xd2b8875b840D3BD574E1e6b440888e110632A0FD` (same as Base Mainnet) |
| BSC Testnet | `0x9FF0FB8e246ac58b17Acf9b7D43B76E2D2e6Bf03` |

*NOTE:* Ensure all addresses are in EIP-55 format to avoid compiler errors.
---

## 3. Deployment Process (Production)

**Security Strategy:** "Sealed Script"  
We utilize a hardcoded configuration in [script/HelperConfig.s.sol](script/HelperConfig.s.sol) rather than environment variables. This ensures that the deployed bytecode contains the **exact** admin address and token parameters agreed upon during the audit, with zero risk of "fat-finger" errors during the deployment command.

### Prerequisites
* **Hardware Wallet:** A Ledger or Trezor initialized and connected.
* **Gnosis Safe:** A Safe deployed on the target chain's mainnet to act as the Admin.
* **Gas Funds:** Native gas token on the target chain (ETH for Base, BNB for BSC) on the **Hardware Wallet** address. The Safe does *not* need funds to receive the role.
* **API Keys:** A valid explorer API key for verification (BaseScan for Base, BscScan for BSC). See [Creating an Explorer API Key](#creating-an-explorer-api-key).

---

### Phase 1: Code Freeze & Audit (The "Seal")
**Actor:** Verifier (Person B) & Deployer (Person A)

Before running any commands, both parties must verify the "Truth" source in the code.

1.  **Pull the Release Candidate:**
    ```bash
    git checkout main
    git pull
    ```
2.  **Audit the Config File:** Open `script/HelperConfig.s.sol` and verify the section for the target chain:
    * **Admin Address:** Ensure `adminAddress` for the target chain ID matches the **Production Gnosis Safe** exactly.
    * **Constants:** Verify `NAME`, `SYMBOL`, and `INITIAL_SUPPLY` match the product spec.
    * **BSC Note:** Verify that `initialSupply` is set to `0 ether` for BSC chains (tokens are bridged, not minted at deploy).
3.  **Lock the Release:**
    If the config is correct, create a git tag to mark this specific version of the bytecode.
    ```bash
    git tag v1.0.0
    git push origin v1.0.0
    ```

---

### Phase 2: Execution (The Deployment)
**Actor:** Deployer (Person A)

This step deploys the contract using a hardware wallet. The hardware wallet pays the gas fees but **will not** receive any admin permissions.

1.  **Connect Hardware Wallet:**
    * Plug in your hardware wallet.
    * Unlock the device with your PIN.
    * Open the **Ethereum App** on the device.
    * Ensure "Blind Signing" is enabled in the Ethereum App settings (required for smart contract deployment).

2.  **Set Environment Variables:**

    **For Base:**
    ```bash
    export BASE_RPC_URL=https://mainnet.base.org
    export ETHERSCAN_API_KEY=<your BaseScan API key>
    export HARDWARE=--ledger
    export DEPLOYER_ADDRESS=0x000...
    ```

    **For BSC:**
    ```bash
    export BASE_RPC_URL=https://bsc-dataseed.binance.org
    export ETHERSCAN_API_KEY=<your BscScan API key>
    export HARDWARE=--ledger
    export DEPLOYER_ADDRESS=0x000...
    ```

    **Notes:**
    1. For testnet deployments, set `BASE_RPC_URL` to the testnet RPC (e.g., `https://sepolia.base.org` for Base Sepolia, `https://data-seed-prebsc-1-s1.binance.org:8545` for BSC Testnet).
    2. Set `HARDWARE` to either `--ledger` or `--trezor`.
    3. Set `DEPLOYER_ADDRESS` to the address of the connected hardware wallet.
    4. Set `ETHERSCAN_API_KEY` to the API key from the matching block explorer (BaseScan or BscScan).

3.  **Run the Deployment Command:**
    ```bash
    forge script script/DeployVeera.s.sol \
      --rpc-url ${BASE_RPC_URL} \
      --sig "run()" \
      --sender ${DEPLOYER_ADDRESS} \
      --broadcast \
      --verify \
      --etherscan-api-key ${ETHERSCAN_API_KEY} \
      ${HARDWARE}
    ```

    **Flag Explanations:**
    * `--ledger` / `--trezor`: Tells Foundry to sign using the USB device.
    * `--broadcast`: Actually sends the transaction to the network (costs real gas).
    * `--verify`: Uploads the source code to the block explorer immediately.

4.  **Sign on Device:**
    * Foundry will compile the code and simulate the transaction.
    * Your device will prompt to `Review Transaction`.
    * **Verify Chain ID:** Ensure the screen shows the correct chain ID for your target network (`8453` for Base, `56` for BSC).
    * **Approve:** detailed transaction data will likely be blind, but you are confirming the deployment cost.

---

### Phase 3: Ratification (The Check)
**Actor:** Verifier (Person B)

Do not consider the token "Live" until this step is complete.

1.  **Locate Contract:**
    * Copy the `Contract Address` from the terminal output of Phase 2.
    * Go to the target chain's block explorer ([basescan.org](https://basescan.org) for Base, [bscscan.com](https://bscscan.com) for BSC) and paste the address.
2.  **Verify Source Code:**
    * Click the **Contract** tab.
    * Ensure it has a Green Checkmark (Verified).
    * *Critical:* Click "Read Contract" -> `DEFAULT_ADMIN_ROLE`. Copy the output hash.
3.  **Verify Permissions:**
    * In "Read Contract", look for `hasRole`.
    * **Test 1 (Success):** Enter `DEFAULT_ADMIN_ROLE` hash and the **Gnosis Safe Address**. Result must be `true`.
    * **Test 2 (Failure):** Enter `DEFAULT_ADMIN_ROLE` hash and the **Deployer (Ledger) Address**. Result must be `false`.

**Status:** If Phase 3 passes, the token is secure and considered deployed.

---

### Phase 4: Automated Verification (Optional)

**Actor:** Verifier (Person B) or Deployer (Person A)

For additional verification, you can use the automated verification script:

```bash
./scripts/verify-deployment.sh <CONTRACT_ADDRESS> <EXPECTED_ADMIN_ADDRESS>
```

This script will:
- Verify token metadata (name, symbol, supply, cap)
- Check that the expected admin has `DEFAULT_ADMIN_ROLE`
- Confirm the deployer does NOT have admin role
- Check pause status
- Validate all role assignments

**Note:** The script requires `cast` (part of Foundry) and the `BASE_RPC_URL` environment variable (pointed at the correct chain's RPC endpoint).

---

## 4. Gas Considerations

The Veera token contract uses multiple OpenZeppelin extensions, which affects gas costs. Approximate gas costs for common operations:

| Operation | Estimated Gas | Notes |
| :--- | :--- | :--- |
| **Transfer** | ~51,000 | Standard ERC20 transfer with pause check |
| **Mint** | ~60,000 | Includes role check and cap validation |
| **Burn** | ~30,000 | Standard burn operation |
| **Approve** | ~46,000 | Standard ERC20 approval |
| **Permit** | ~80,000 | Gasless approval via EIP-2612 |
| **Pause/Unpause** | ~45,000 | Role-checked pause operation |

**Note:** Actual gas costs may vary based on network conditions and contract state. These estimates are for reference only.

---

## 5. Contract Size Monitoring

The Veera contract uses multiple OpenZeppelin extensions, which increases contract size. The current configuration uses:

- **Optimizer:** Enabled with 200 runs
- **Target EVM Version:** Prague
- **Via IR:** Disabled

**Contract Size Limit:** Ethereum has a 24KB (24,576 bytes) contract size limit for runtime bytecode. Monitor the compiled contract size using:

```bash
forge build --sizes
```

### Current Contract Sizes

As of the latest build:

| Metric | Size | Margin |
| :--- | :--- | :--- |
| **Runtime Bytecode** | 5,622 bytes | 18,954 bytes |
| **Initcode** | 7,929 bytes | 41,223 bytes |

---

## 6. Role Management

After deployment, the Gnosis Safe (admin) can manage roles using the standard AccessControl functions.

### Granting Roles

To grant the `MINTER_ROLE` to a bridge adapter or other contract:

```solidity
// Using Gnosis Safe interface or cast command
token.grantRole(MINTER_ROLE, bridgeAdapterAddress);
```

### Revoking Roles

To revoke a role:

```solidity
token.revokeRole(MINTER_ROLE, bridgeAdapterAddress);
```

### Best Practices

1. **Use Gnosis Safe:** Always perform role management through the Gnosis Safe multisig, never from an EOA.
2. **Verify Addresses:** Double-check addresses before granting roles to prevent mistakes.
3. **Document Changes:** Keep a record of all role grants/revocations for audit purposes.
4. **Test First:** Test role changes on testnet before applying to mainnet.
5. **Time-Lock Consideration:** For critical roles, consider implementing a time-lock (future enhancement).

### Role Identifiers

- `DEFAULT_ADMIN_ROLE`: `0x0000000000000000000000000000000000000000000000000000000000000000`
- `MINTER_ROLE`: `keccak256("MINTER_ROLE")`
- `PAUSER_ROLE`: `keccak256("PAUSER_ROLE")`

You can query role identifiers using:
```bash
cast call <TOKEN_ADDRESS> "MINTER_ROLE()(bytes32)" --rpc-url $BASE_RPC_URL  # BASE_RPC_URL pointed at the target chain
```

---

## 7. Upgradeability

**Important:** The Veera token contract is **not upgradeable**. It uses standard constructors and cannot be modified after deployment.

### Implications

- **Immutable Logic:** Contract logic cannot be changed after deployment
- **No Proxy Pattern:** The contract does not use a proxy pattern (e.g., UUPS, Transparent, Beacon)
- **Permanent Configuration:** Token parameters (name, symbol, cap) are set at deployment and cannot be changed

### Why Non-Upgradeable?

1. **Security:** Reduces attack surface by eliminating proxy-related vulnerabilities
2. **Simplicity:** Simpler architecture reduces complexity and potential bugs
3. **Trust:** Users can verify the contract code will never change
4. **Gas Efficiency:** No proxy overhead means lower gas costs

---

## 8. Gas Cost Explanations

The gas costs listed in Section 4 are influenced by several factors:

| Operation | Gas Cost Factors |
| :--- | :--- |
| **Transfer** | Base ERC20 (~21k) + Pausable check (~5k) + Storage updates (~25k) |
| **Mint** | Transfer gas + Role check (~10k) + Cap validation (~5k) |
| **Burn** | Base ERC20 (~21k) + Storage updates (~9k) |
| **Approve** | Base ERC20 (~21k) + Storage updates (~25k) |
| **Permit** | EIP-712 signature verification (~45k) + Storage updates (~35k) |
| **Pause/Unpause** | Role check (~10k) + State change (~35k) |

**Note:** These are approximate values. Actual costs depend on:
- Current storage slot state (cold vs warm access)
- Network congestion
- EIP-1559 base fee
- Contract state (paused/unpaused)

---

## 9. Integration Testing

After deploying the contract, you can run comprehensive integration tests to verify all functionality on the deployed instance.

### Overview

The integration test suite is a TypeScript-based testing framework that validates:

- ERC20 standard operations (transfer, approve, allowance, transferFrom)
- ERC20Permit (gasless approvals with EIP-712 signatures)
- Minting operations (success, cap enforcement, zero address checks)
- Burning operations (burn, burnFrom, insufficient balance handling)
- Pausing operations (pause/unpause, verify operations are blocked/resumed)
- Access control (role management, permission verification)
- Edge cases (zero address, insufficient balance/allowance, boundary conditions)

### Quick Start

1. **Navigate to integration tests directory:**

   ```bash
   cd integration-tests
   ```

2. **Install dependencies:**

   ```bash
   npm install
   ```

3. **Configure environment variables:**

   Add the following to your `.env` file (in the project root):

   ```bash
   # Required
   BASE_RPC_URL=https://sepolia.base.org
   CONTRACT_ADDRESS=0x...  # Your deployed contract address
   ADMIN_ADDRESS=0x...     # Admin address (has all roles)
   ADMIN_PRIVATE_KEY=0x... # Admin private key
   TEST_USER_ADDRESS=0x... # Test user address
   TEST_USER_PRIVATE_KEY=0x... # Test user private key

   # Optional (for role testing)
   MINTER_ADDRESS=0x...
   MINTER_PRIVATE_KEY=0x...
   PAUSER_ADDRESS=0x...
   PAUSER_PRIVATE_KEY=0x...
   ```

4. **Run tests:**

   ```bash
   npm test
   ```

### Prerequisites

- Node.js v18 or higher
- npm or yarn
- Test accounts with sufficient ETH for gas fees
- Deployed contract address

### Test Account Setup

You'll need at least two test accounts:

1. **Admin Account**: Must have `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE`, and `PAUSER_ROLE`
   - Used for minting, pausing, and role management
   - Must have sufficient ETH for gas

2. **Test User Account**: Regular user account
   - Used for transfers, approvals, receiving tokens
   - Must have sufficient ETH for gas

Optional accounts (for comprehensive role testing):
- **Minter Account**: Will be granted `MINTER_ROLE` during tests
- **Pauser Account**: Will be granted `PAUSER_ROLE` during tests

### Test Output

The test suite provides detailed output showing:
- Individual test results (✓ pass, ✗ fail)
- Transaction hashes for on-chain verification
- Per-suite summary
- Overall summary with pass/fail counts

### Documentation

For detailed documentation, see [integration-tests/README.md](integration-tests/README.md).

### Security Notes

- **Never commit private keys**: Use environment variables or secure key management
- **Test on testnet first**: Always test on testnet before mainnet
- **Verify contract address**: Double-check the contract address before running tests
- **Use separate accounts**: Don't use production accounts for testing
