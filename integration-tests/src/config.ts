import dotenv from 'dotenv';
import { Address } from 'viem';
import { fileURLToPath } from 'url';
import { dirname, join, resolve } from 'path';

// Load environment variables from .env file in project root
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = join(__dirname, '../..');
dotenv.config({ path: join(projectRoot, '.env') });

export interface TestConfig {
  rpcUrl: string;
  contractAddress: Address;
  // Derived addresses (computed from private keys/keystores in setup.ts)
  adminAddress: Address; // Derived from adminPrivateKey or adminKeystorePath
  adminPrivateKey: `0x${string}`;
  testUserAddress: Address; // Derived from testUserPrivateKey or testUserKeystorePath
  testUserPrivateKey: `0x${string}`;
  minterAddress?: Address; // Derived from minterPrivateKey or minterKeystorePath
  minterPrivateKey?: `0x${string}`;
  pauserAddress?: Address; // Derived from pauserPrivateKey or pauserKeystorePath
  pauserPrivateKey?: `0x${string}`;
  // Keystore paths (optional, alternative to private keys)
  adminKeystorePath?: string;
  testUserKeystorePath?: string;
  minterKeystorePath?: string;
  pauserKeystorePath?: string;
  // Passwords (for keystore decryption)
  globalKeystorePassword?: string;
  adminKeystorePassword?: string;
  testUserKeystorePassword?: string;
  minterKeystorePassword?: string;
  pauserKeystorePassword?: string;
  // Debug mode
  debug?: boolean;
}

/**
 * Parse command-line arguments
 * Supports formats: --key=value or --key value
 */
function parseArgs(): Map<string, string> {
  const args = new Map<string, string>();
  const argv = process.argv.slice(2);

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg.startsWith('--')) {
      const keyValue = arg.slice(2).split('=');
      if (keyValue.length === 2) {
        // --key=value format
        args.set(keyValue[0], keyValue[1]);
      } else if (i + 1 < argv.length && !argv[i + 1].startsWith('--')) {
        // --key value format
        args.set(keyValue[0], argv[i + 1]);
        i++; // Skip next arg as it's the value
      } else {
        // --key (boolean flag, not used here but handle gracefully)
        args.set(keyValue[0], 'true');
      }
    }
  }

  return args;
}

/**
 * Get configuration value from CLI args, env vars, or default
 * Priority: CLI args > Environment variables
 */
function getConfigValue(key: string, cliArgs: Map<string, string>, required = true): string {
  // Check CLI args first (case-insensitive)
  const cliKey = Array.from(cliArgs.keys()).find(
    (k) => k.toLowerCase() === key.toLowerCase()
  );
  if (cliKey) {
    return cliArgs.get(cliKey)!;
  }

  // Fall back to environment variable
  const envValue = process.env[key];
  if (envValue) {
    return envValue;
  }

  // Required but not found
  if (required) {
    throw new Error(
      `Missing required configuration: ${key}. Provide via --${key.toLowerCase()}=value or ${key} environment variable.`
    );
  }

  return '';
}

function validateAddress(name: string, value: string): Address {
  if (!value || !value.startsWith('0x') || value.length !== 42) {
    throw new Error(`Invalid address format for ${name}: ${value}`);
  }
  return value as Address;
}

function validatePrivateKey(name: string, value: string): `0x${string}` {
  if (!value || !value.startsWith('0x') || value.length !== 66) {
    throw new Error(`Invalid private key format for ${name}: ${value}`);
  }
  return value as `0x${string}`;
}

export function loadConfig(): TestConfig {
  const cliArgs = parseArgs();

  // Check for debug flag
  const debug = cliArgs.has('debug') || process.env.DEBUG === 'true';

  // Show help if requested
  if (cliArgs.has('help') || cliArgs.has('h')) {
    console.log(`
Usage: npm test [options]

Options:
  --rpc-url=<url>                    RPC URL (overrides BASE_RPC_URL)
  --contract-address=<addr>          Contract address (overrides CONTRACT_ADDRESS)
  
  Account Configuration (use either private key OR keystore):
  --admin-private-key=<key>           Admin private key (overrides ADMIN_PRIVATE_KEY)
  --admin-keystore=<path>             Admin keystore file path (overrides ADMIN_KEYSTORE)
  --admin-keystore-password=<pwd>    Admin keystore password or file (overrides ADMIN_KEYSTORE_PASSWORD)
  Note: Admin address is automatically derived from private key/keystore
  
  --test-user-private-key=<key>       Test user private key (overrides TEST_USER_PRIVATE_KEY)
  --test-user-keystore=<path>         Test user keystore file path (overrides TEST_USER_KEYSTORE)
  --test-user-keystore-password=<pwd> Test user keystore password or file (overrides TEST_USER_KEYSTORE_PASSWORD)
  Note: Test user address is automatically derived from private key/keystore
  
  --minter-private-key=<key>          Minter private key (overrides MINTER_PRIVATE_KEY, optional)
  --minter-keystore=<path>            Minter keystore file path (overrides MINTER_KEYSTORE, optional)
  --minter-keystore-password=<pwd>    Minter keystore password or file (overrides MINTER_KEYSTORE_PASSWORD, optional)
  Note: Minter address is automatically derived from private key/keystore
  
  --pauser-private-key=<key>          Pauser private key (overrides PAUSER_PRIVATE_KEY, optional)
  --pauser-keystore=<path>            Pauser keystore file path (overrides PAUSER_KEYSTORE, optional)
  --pauser-keystore-password=<pwd>    Pauser keystore password or file (overrides PAUSER_KEYSTORE_PASSWORD, optional)
  Note: Pauser address is automatically derived from private key/keystore
  
  Global Keystore Password (applies to all keystores if not account-specific):
  --keystore-password=<pwd>           Global keystore password or file (overrides KEYSTORE_PASSWORD)
  
  Debug Options:
  --debug                             Enable debug mode (prints full error details for gas estimation failures)
  
  --help, -h                          Show this help message

Examples:
  # Using private keys
  npm test --rpc-url=https://sepolia.base.org --contract-address=0x1234... --admin-private-key=0x...
  
  # Using keystores
  npm test --rpc-url=https://sepolia.base.org --contract-address=0x1234... \\
    --admin-keystore=keystores/testnet-admin-1 --admin-keystore-password=mypassword
  
  # Using keystore password file
  npm test --rpc-url=https://sepolia.base.org --contract-address=0x1234... \\
    --admin-keystore=keystores/testnet-admin-1 --keystore-password=/path/to/password.txt
  
  # Mixed (some keystores, some private keys)
  npm test --admin-keystore=keystores/testnet-admin-1 \\
    --test-user-private-key=0x...
`);
    process.exit(0);
  }

  const rpcUrl = getConfigValue('BASE_RPC_URL', cliArgs) || getConfigValue('rpc-url', cliArgs);
  if (!rpcUrl) {
    throw new Error('RPC URL is required. Provide via --rpc-url=<url> or BASE_RPC_URL environment variable.');
  }

  const contractAddress = validateAddress(
    'CONTRACT_ADDRESS',
    getConfigValue('CONTRACT_ADDRESS', cliArgs) || getConfigValue('contract-address', cliArgs)
  );

  const config: TestConfig = {
    rpcUrl,
    contractAddress,
    adminAddress: '0x0' as Address, // Placeholder, will be derived in setup.ts
    adminPrivateKey: '0x0' as `0x${string}`, // Placeholder, will be set below
    testUserAddress: '0x0' as Address, // Placeholder, will be derived in setup.ts
    testUserPrivateKey: '0x0' as `0x${string}`, // Placeholder, will be set below
  };

  // Get global keystore password
  const globalKeystorePassword = getConfigValue('KEYSTORE_PASSWORD', cliArgs, false) || 
                                  getConfigValue('keystore-password', cliArgs, false);
  if (globalKeystorePassword) {
    config.globalKeystorePassword = globalKeystorePassword;
  }

  // Admin: Check for keystore first, then private key
  const adminKeystorePath = getConfigValue('ADMIN_KEYSTORE', cliArgs, false) || 
                            getConfigValue('admin-keystore', cliArgs, false);
  const adminPrivateKeyValue = getConfigValue('ADMIN_PRIVATE_KEY', cliArgs, false) || 
                               getConfigValue('admin-private-key', cliArgs, false);
  const adminKeystorePassword = getConfigValue('ADMIN_KEYSTORE_PASSWORD', cliArgs, false) || 
                                 getConfigValue('admin-keystore-password', cliArgs, false);

  if (adminKeystorePath) {
    config.adminKeystorePath = resolve(adminKeystorePath);
    if (adminKeystorePassword) {
      config.adminKeystorePassword = adminKeystorePassword;
    }
  } else if (adminPrivateKeyValue) {
    config.adminPrivateKey = validatePrivateKey('ADMIN_PRIVATE_KEY', adminPrivateKeyValue);
  } else {
    throw new Error('Admin account requires either --admin-keystore=<path> or --admin-private-key=<key>');
  }

  // Test User: Check for keystore first, then private key
  const testUserKeystorePath = getConfigValue('TEST_USER_KEYSTORE', cliArgs, false) || 
                               getConfigValue('test-user-keystore', cliArgs, false);
  const testUserPrivateKeyValue = getConfigValue('TEST_USER_PRIVATE_KEY', cliArgs, false) || 
                                  getConfigValue('test-user-private-key', cliArgs, false);
  const testUserKeystorePassword = getConfigValue('TEST_USER_KEYSTORE_PASSWORD', cliArgs, false) || 
                                   getConfigValue('test-user-keystore-password', cliArgs, false);

  if (testUserKeystorePath) {
    config.testUserKeystorePath = resolve(testUserKeystorePath);
    if (testUserKeystorePassword) {
      config.testUserKeystorePassword = testUserKeystorePassword;
    }
  } else if (testUserPrivateKeyValue) {
    config.testUserPrivateKey = validatePrivateKey('TEST_USER_PRIVATE_KEY', testUserPrivateKeyValue);
  } else {
    throw new Error('Test user account requires either --test-user-keystore=<path> or --test-user-private-key=<key>');
  }

  const minterKeystorePath = getConfigValue('MINTER_KEYSTORE', cliArgs, false) || 
                             getConfigValue('minter-keystore', cliArgs, false);
  const minterPrivateKeyValue = getConfigValue('MINTER_PRIVATE_KEY', cliArgs, false) || 
                                getConfigValue('minter-private-key', cliArgs, false);
  const minterKeystorePassword = getConfigValue('MINTER_KEYSTORE_PASSWORD', cliArgs, false) || 
                                 getConfigValue('minter-keystore-password', cliArgs, false);

  if (minterKeystorePath || minterPrivateKeyValue) {
    if (minterKeystorePath) {
      config.minterKeystorePath = resolve(minterKeystorePath);
      if (minterKeystorePassword) {
        config.minterKeystorePassword = minterKeystorePassword;
      }
    } else if (minterPrivateKeyValue) {
      config.minterPrivateKey = validatePrivateKey('MINTER_PRIVATE_KEY', minterPrivateKeyValue);
    }
    // Address will be derived in setup.ts from private key/keystore
  }

  const pauserKeystorePath = getConfigValue('PAUSER_KEYSTORE', cliArgs, false) || 
                             getConfigValue('pauser-keystore', cliArgs, false);
  const pauserPrivateKeyValue = getConfigValue('PAUSER_PRIVATE_KEY', cliArgs, false) || 
                                getConfigValue('pauser-private-key', cliArgs, false);
  const pauserKeystorePassword = getConfigValue('PAUSER_KEYSTORE_PASSWORD', cliArgs, false) || 
                                 getConfigValue('pauser-keystore-password', cliArgs, false);

  if (pauserKeystorePath || pauserPrivateKeyValue) {
    if (pauserKeystorePath) {
      config.pauserKeystorePath = resolve(pauserKeystorePath);
      if (pauserKeystorePassword) {
        config.pauserKeystorePassword = pauserKeystorePassword;
      }
    } else if (pauserPrivateKeyValue) {
      config.pauserPrivateKey = validatePrivateKey('PAUSER_PRIVATE_KEY', pauserPrivateKeyValue);
    }
    // Address will be derived in setup.ts from private key/keystore
  }

  // Set debug flag
  if (debug) {
    config.debug = true;
  }

  return config;
}

