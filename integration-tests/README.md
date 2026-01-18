# Veera Token Integration Tests

Comprehensive TypeScript-based integration test suite for the Veera token contract deployed on testnet or mainnet.

## Overview

This test suite validates all contract functionality on a deployed instance, including:

- **ERC20 Standard Operations**: Transfer, approve, allowance, transferFrom (tested from both admin and regular user perspectives)
- **ERC20Permit**: Gasless approvals with EIP-712 signatures
- **Minting Operations**: Success cases, cap enforcement, zero address checks
- **Burning Operations**: Burn, burnFrom, insufficient balance handling
- **Pausing Operations**: Pause/unpause, verify operations are blocked/resumed
- **Access Control**: Role management (grant/revoke), permission verification
- **Edge Cases**: Zero address, insufficient balance/allowance, boundary conditions

**Test Accounts**: The suite uses two main accounts:
- **Admin Account**: Has all roles (admin, minter, pauser) - tests privileged operations
- **Test User Account**: Regular user with no special roles - tests standard ERC20 operations and verifies access restrictions

## Prerequisites

- **Node.js**: v18 or higher
- **npm** or **yarn**: Package manager
- **Foundry**: For contract compilation (ABI generation)
- **Test Accounts**: Accounts with sufficient ETH for gas fees
- **Deployed Contract**: A deployed Veera token contract address

## Setup

1. **Install Dependencies**

   ```bash
   cd integration-tests
   npm install
   ```

2. **Build Contract ABI**

   Ensure the contract is compiled to generate the ABI:

   ```bash
   cd ..
   forge build
   ```

   This generates the ABI at `out/Veera.sol/Veera.json`, which is automatically copied to `integration-tests/src/veera-abi.json`.

3. **Configure Test Parameters**

   You can provide configuration via command-line arguments or environment variables. Command-line arguments take priority.

   **Account Authentication: Keystores vs Private Keys**

   For each account (admin, test-user, minter, pauser), you can use either:
   - **Keystore files** (encrypted, password-protected) - Recommended for security
   - **Raw private keys** (plain text) - Simpler but less secure

   **Using Keystores (Recommended)**

   ```bash
   npm test -- \
     --rpc-url=https://sepolia.base.org \
     --contract-address=0x1234... \
     --admin-address=0xabcd... \
     --admin-keystore=keystores/testnet-admin-1 \
     --admin-keystore-password=mypassword \
     --test-user-address=0xefgh... \
     --test-user-keystore=keystores/testnet-user-1 \
     --test-user-keystore-password=mypassword
   ```

   **Note**: The test user account (`TEST_USER_ADDRESS`) is a regular user account with no special roles. It's used to:
   - Receive tokens via transfers and mints (from admin)
   - Test standard ERC20 operations like `approve()` and `transferFrom()`
   - Test `permit()` (gasless approvals)
   - Verify that non-admin accounts cannot perform privileged operations (e.g., minting without MINTER_ROLE)
   - Test `burnFrom()` with approvals

   **Using Private Keys**

   ```bash
   npm test -- \
     --rpc-url=https://sepolia.base.org \
     --contract-address=0x1234... \
     --admin-address=0xabcd... \
     --admin-private-key=0x... \
     --test-user-address=0xefgh... \
     --test-user-private-key=0x...
   ```

   **Password Handling**

   Passwords can be provided in multiple ways (in order of priority):
   1. Account-specific password: `--admin-keystore-password=<password or file>`
   2. Global password: `--keystore-password=<password or file>` (applies to all keystores)
   3. Environment variable: `KEYSTORE_PASSWORD` or `ADMIN_KEYSTORE_PASSWORD`
   4. Interactive prompt (if none of the above)

   Passwords can be:
   - Direct password string: `--keystore-password=mypassword`
   - File containing password: `--keystore-password=/path/to/password.txt`

   **Environment Variables (`.env` file)**

   ```bash
   # Required
   BASE_RPC_URL=https://sepolia.base.org
   CONTRACT_ADDRESS=0x...
   ADMIN_ADDRESS=0x...
   
   # Use keystores
   ADMIN_KEYSTORE=keystores/testnet-admin-1
   ADMIN_KEYSTORE_PASSWORD=mypassword
   
   # Or use private keys
   ADMIN_PRIVATE_KEY=0x...
   
   TEST_USER_ADDRESS=0x...
   TEST_USER_KEYSTORE=keystores/testnet-user-1
   TEST_USER_KEYSTORE_PASSWORD=mypassword
   
   # Optional (for role testing)
   MINTER_ADDRESS=0x...
   MINTER_KEYSTORE=keystores/testnet-minter-1
   MINTER_KEYSTORE_PASSWORD=mypassword
   
   # Global password (applies to all keystores)
   KEYSTORE_PASSWORD=mypassword
   ```

   **Security Note**: Never commit private keys or keystore passwords to version control. Use environment variables or secure key management.

## Running Tests

### Run All Tests

**With command-line arguments:**
```bash
cd integration-tests
npm test -- \
  --rpc-url=https://sepolia.base.org \
  --contract-address=0x1234... \
  --admin-address=0xabcd... \
  --admin-private-key=0x... \
  --test-user-address=0xefgh... \
  --test-user-private-key=0x...
```

**With environment variables:**
```bash
cd integration-tests
npm test
```

**Using tsx directly:**
```bash
npx tsx src/index.ts --rpc-url=https://sepolia.base.org --contract-address=0x1234...
```

### Run Pre-Flight Checks

To quickly check gas estimates and account balances without running the full test suite:

```bash
cd integration-tests
npm run preflight -- --rpc-url=https://sepolia.base.org --contract-address=0x1234...
```

Or with environment variables:
```bash
npm run preflight
```

**Debug Mode**: Add `--debug` to see detailed error information when gas estimation fails:

```bash
npm run preflight -- --debug --rpc-url=https://sepolia.base.org --contract-address=0x1234...
```

This is useful for:
- Verifying accounts have sufficient balance before running tests
- Getting cost estimates for the test suite
- Quick validation before committing to running all tests
- Debugging why gas estimation fails (with `--debug` flag)

### Command-Line Arguments

All configuration can be provided via command-line arguments. Use `--help` to see all options:

```bash
npm test -- --help
```

**Available Arguments:**
- `--rpc-url=<url>` - RPC endpoint URL
- `--contract-address=<addr>` - Deployed contract address

**Account Configuration (for each account, use either keystore OR private key):**
- `--admin-address=<addr>` - Admin address
- `--admin-private-key=<key>` - Admin private key (alternative to keystore)
- `--admin-keystore=<path>` - Admin keystore file path (alternative to private key)
- `--admin-keystore-password=<pwd>` - Admin keystore password or file path

- `--test-user-address=<addr>` - Test user address
- `--test-user-private-key=<key>` - Test user private key (alternative to keystore)
- `--test-user-keystore=<path>` - Test user keystore file path (alternative to private key)
- `--test-user-keystore-password=<pwd>` - Test user keystore password or file path

- `--minter-address=<addr>` - Minter address (optional)
- `--minter-private-key=<key>` - Minter private key (optional, alternative to keystore)
- `--minter-keystore=<path>` - Minter keystore file path (optional, alternative to private key)
- `--minter-keystore-password=<pwd>` - Minter keystore password or file path (optional)

- `--pauser-address=<addr>` - Pauser address (optional)
- `--pauser-private-key=<key>` - Pauser private key (optional, alternative to keystore)
- `--pauser-keystore=<path>` - Pauser keystore file path (optional, alternative to private key)
- `--pauser-keystore-password=<pwd>` - Pauser keystore password or file path (optional)

**Global Options:**
- `--keystore-password=<pwd>` - Global keystore password or file (applies to all keystores)
- `--debug` - Enable debug mode (prints full error details for gas estimation failures)

**Examples:**
```bash
# Using keystores
npm test -- \
  --rpc-url=https://sepolia.base.org \
  --contract-address=0x1234... \
  --admin-address=0xabcd... \
  --admin-keystore=keystores/testnet-admin-1 \
  --keystore-password=mypassword

# Using private keys
npm test -- \
  --rpc-url=https://sepolia.base.org \
  --contract-address=0x1234... \
  --admin-address=0xabcd... \
  --admin-private-key=0x...

# Mixed (keystore for admin, private key for user)
npm test -- \
  --admin-keystore=keystores/testnet-admin-1 \
  --admin-keystore-password=/path/to/password.txt \
  --test-user-private-key=0x... \
  --test-user-address=0x...

# Run pre-flight checks with keystores
npm run preflight -- \
  --contract-address=0x1234... \
  --admin-address=0xabcd... \
  --admin-keystore=keystores/testnet-admin-1
```

### Pre-Flight Checks

Before running tests, the suite automatically performs pre-flight checks:

1. **Gas Estimation**: Estimates gas costs for all write operations
2. **Balance Verification**: Checks that all accounts have sufficient ETH

The pre-flight checks will:
- Display estimated gas costs per account
- Show total estimated cost for the entire test suite
- Verify each account has sufficient balance (with 50% safety buffer)
- Exit early if any account is insufficient (unless `FORCE_CONTINUE=true`)

**Example Output:**
```
PRE-FLIGHT CHECKS
============================================================

Gas Cost Estimates:

  Admin (0x1234...5678):
    Operations: 15
    Total Gas: 1,250,000
    Estimated Cost: 0.025 ETH

  Test User (0xabcd...efgh):
    Operations: 8
    Total Gas: 400,000
    Estimated Cost: 0.008 ETH

Overall Totals:
  Total Operations: 23
  Total Gas: 1,650,000
  Total Estimated Cost: 0.033 ETH

Account Balance Check:

✓ Admin (0x1234...5678):
  Balance: 0.1 ETH
  Required: 0.0375 ETH (with 50% buffer)
  ✓ Sufficient (0.0625 ETH remaining)

✓ Test User (0xabcd...efgh):
  Balance: 0.05 ETH
  Required: 0.012 ETH (with 50% buffer)
  ✓ Sufficient (0.038 ETH remaining)

✓ All pre-flight checks passed!
```

**Environment Variables:**
- `SKIP_PREFLIGHT=true`: Skip pre-flight checks entirely
- `FORCE_CONTINUE=true`: Continue with tests even if pre-flight checks fail
- `DEBUG=true`: Enable debug mode (prints full error details for gas estimation failures, can also use `--debug` flag)

### Test Execution Flow

The test suite runs tests sequentially in the following order:

1. **ERC20 Operations** - Basic token operations
2. **ERC20Permit** - Gasless approval tests
3. **Minting Operations** - Mint functionality and cap enforcement
4. **Burning Operations** - Burn functionality
5. **Pausing Operations** - Pause/unpause and operation blocking
6. **Access Control** - Role management and permissions
7. **Edge Cases** - Boundary conditions and error cases

## Test Structure

```
integration-tests/
├── src/
│   ├── config.ts              # Configuration loading
│   ├── setup.ts               # Test context setup
│   ├── contracts.ts           # Contract interface and ABI
│   ├── test-utils.ts          # Test utilities and helpers
│   ├── index.ts               # Main test runner
│   ├── veera-abi.json         # Contract ABI (generated)
│   └── test-suites/
│       ├── erc20.test.ts      # ERC20 standard tests
│       ├── permit.test.ts     # ERC20Permit tests
│       ├── minting.test.ts    # Minting tests
│       ├── burning.test.ts    # Burning tests
│       ├── pausing.test.ts     # Pausing tests
│       ├── roles.test.ts       # Access control tests
│       └── edge-cases.test.ts  # Edge case tests
├── package.json
├── tsconfig.json
└── README.md
```

## Test Account Setup

### Required Accounts

1. **Admin Account** (`ADMIN_ADDRESS`): Must have `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE`, and `PAUSER_ROLE`
   - **Purpose**: Tests admin-only operations (minting, pausing, role management)
   - **Used for**: 
     - Minting tokens
     - Pausing/unpausing the contract
     - Granting/revoking roles
     - Transferring tokens (as sender)
   - **Must have**: Sufficient ETH for gas fees

2. **Test User Account** (`TEST_USER_ADDRESS`): Regular user account (no special roles)
   - **Purpose**: Tests standard ERC20 operations from a regular user's perspective and verifies that non-admin accounts are properly restricted
   - **Used for**:
     - Receiving tokens (via transfers and mints from admin)
     - Testing `approve()` and `transferFrom()` operations
     - Testing `permit()` (gasless approvals)
     - Testing that unauthorized operations fail (e.g., trying to mint without MINTER_ROLE)
     - Testing `burnFrom()` with approvals
   - **Must have**: Sufficient ETH for gas fees
   - **Note**: This account represents a typical token holder who can receive, transfer, and approve tokens, but cannot perform admin operations

### Optional Accounts (for Role Testing)

3. **Minter Account**: Will be granted `MINTER_ROLE` during tests
   - Used to test: Minting with delegated role
   - Must have sufficient ETH for gas

4. **Pauser Account**: Will be granted `PAUSER_ROLE` during tests
   - Used to test: Pausing with delegated role
   - Must have sufficient ETH for gas

## Understanding Test Output

### Success Output

```
✓ Transfer tokens from admin to user
  TX: 0x1234...
✓ Verify balance after transfer
✓ Approve allowance for user
```

### Failure Output

```
✗ Mint exceeding cap
  Error: ERC20ExceededCap
```

### Summary

At the end, you'll see a summary:

```
TEST SUMMARY
============================================================

✓ ERC20 Operations: 8/8 passed, 0/8 failed
✓ ERC20Permit: 4/4 passed, 0/4 failed
...

OVERALL RESULTS
============================================================

Total Tests: 45
Passed: 45
Failed: 0
Success Rate: 100.00%
```

## Troubleshooting

### Common Issues

1. **"Missing required configuration"**
   - Provide configuration via command-line arguments: `--rpc-url=... --contract-address=...`
   - Or ensure all required variables are set in `.env` file
   - Command-line arguments override environment variables
   - Use `npm test -- --help` to see all available options

2. **"Invalid address format"**
   - Ensure addresses start with `0x` and are 42 characters
   - Check addresses are checksummed (EIP-55 format)

3. **"Invalid private key format"**
   - Ensure private keys start with `0x` and are 66 characters
   - Never share or commit private keys

4. **"Transaction reverted"**
   - Check account has sufficient ETH for gas
   - Verify contract address is correct
   - Ensure account has required roles (for admin operations)

5. **"Failed to connect to RPC"**
   - Verify `BASE_RPC_URL` is correct
   - Check network connectivity
   - Ensure RPC endpoint is accessible

### Gas Issues

If tests fail due to insufficient gas:

1. Ensure all test accounts have sufficient ETH
2. Check current gas prices on the network
3. Some tests may require multiple transactions

## Security Considerations

- **Never commit private keys**: Use environment variables or secure key management
- **Test on testnet first**: Always test on testnet before mainnet
- **Verify contract address**: Double-check the contract address before running tests
- **Review transactions**: Check transaction hashes on block explorer
- **Use separate accounts**: Don't use production accounts for testing

## Integration with CI/CD

The test suite can be integrated into CI/CD pipelines:

```yaml
# Example GitHub Actions
- name: Run Integration Tests
  run: |
    cd integration-tests
    npm install
    npm test
  env:
    BASE_RPC_URL: ${{ secrets.BASE_RPC_URL }}
    CONTRACT_ADDRESS: ${{ secrets.CONTRACT_ADDRESS }}
    ADMIN_ADDRESS: ${{ secrets.ADMIN_ADDRESS }}
    ADMIN_PRIVATE_KEY: ${{ secrets.ADMIN_PRIVATE_KEY }}
    # ... other variables
```

## Contributing

When adding new tests:

1. Create a new test file in `src/test-suites/`
2. Export a function that returns a `TestSuite`
3. Import and call the function in `src/index.ts`
4. Follow the existing test patterns and error handling

## License

MIT

