import { createPublicClient, createWalletClient, http, PublicClient, WalletClient, Address } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { TestConfig, loadConfig } from './config.js';
import { createVeeraContract, getChain, VeeraContract } from './contracts.js';
import { decryptKeystore, getKeystorePassword } from './keystore.js';

export interface TestContext {
  config: TestConfig;
  publicClient: PublicClient;
  adminWallet: WalletClient;
  adminContract: VeeraContract;
  adminPrivateKey: `0x${string}`;
  testUserWallet: WalletClient;
  testUserContract: VeeraContract;
  testUserPrivateKey: `0x${string}`;
  minterWallet?: WalletClient;
  minterContract?: VeeraContract;
  minterPrivateKey?: `0x${string}`;
  pauserWallet?: WalletClient;
  pauserContract?: VeeraContract;
  pauserPrivateKey?: `0x${string}`;
}

/**
 * Get private key from keystore or use provided private key
 */
async function getPrivateKey(
  config: TestConfig,
  accountType: 'admin' | 'testUser' | 'minter' | 'pauser'
): Promise<`0x${string}`> {
  const keystorePath = 
    accountType === 'admin' ? config.adminKeystorePath :
    accountType === 'testUser' ? config.testUserKeystorePath :
    accountType === 'minter' ? config.minterKeystorePath :
    config.pauserKeystorePath;

  const privateKey = 
    accountType === 'admin' ? config.adminPrivateKey :
    accountType === 'testUser' ? config.testUserPrivateKey :
    accountType === 'minter' ? config.minterPrivateKey :
    config.pauserPrivateKey;

  const accountKeystorePassword = 
    accountType === 'admin' ? config.adminKeystorePassword :
    accountType === 'testUser' ? config.testUserKeystorePassword :
    accountType === 'minter' ? config.minterKeystorePassword :
    config.pauserKeystorePassword;

  if (keystorePath) {
    const password = await getKeystorePassword(
      accountType,
      accountKeystorePassword,
      config.globalKeystorePassword
    );
    return await decryptKeystore(keystorePath, password);
  }

  if (privateKey && privateKey !== '0x0') {
    return privateKey;
  }

  throw new Error(`${accountType} account requires either keystore or private key`);
}

export async function setupTestContext(): Promise<TestContext> {
  const config = loadConfig();
  const chain = getChain(config.rpcUrl);

  // Create public client for read operations
  const publicClient = createPublicClient({
    chain,
    transport: http(config.rpcUrl),
  });

  // Get private keys (from keystore or direct)
  const adminPrivateKey = await getPrivateKey(config, 'admin');
  const testUserPrivateKey = await getPrivateKey(config, 'testUser');

  // Create wallet clients for write operations and derive addresses
  const adminAccount = privateKeyToAccount(adminPrivateKey);
  // Store derived address in config
  config.adminAddress = adminAccount.address;
  const adminWallet = createWalletClient({
    account: adminAccount,
    chain,
    transport: http(config.rpcUrl),
  });

  const testUserAccount = privateKeyToAccount(testUserPrivateKey);
  // Store derived address in config
  config.testUserAddress = testUserAccount.address;
  const testUserWallet = createWalletClient({
    account: testUserAccount,
    chain,
    transport: http(config.rpcUrl),
  });

  // Create contract instances
  const adminContract = createVeeraContract(config.contractAddress, publicClient, adminWallet);
  const testUserContract = createVeeraContract(config.contractAddress, publicClient, testUserWallet);

  const context: TestContext = {
    config,
    publicClient,
    adminWallet,
    adminContract,
    adminPrivateKey: adminPrivateKey,
    testUserWallet,
    testUserContract,
    testUserPrivateKey: testUserPrivateKey,
  };

  // Setup optional wallets for role testing
  // Derive addresses from private keys/keystores and store in config
  if (config.minterKeystorePath || config.minterPrivateKey) {
    const minterPrivateKey = await getPrivateKey(config, 'minter');
    const minterAccount = privateKeyToAccount(minterPrivateKey);
    // Store derived address in config
    config.minterAddress = minterAccount.address;
    const minterWallet = createWalletClient({
      account: minterAccount,
      chain,
      transport: http(config.rpcUrl),
    });
    context.minterWallet = minterWallet;
    context.minterContract = createVeeraContract(config.contractAddress, publicClient, minterWallet);
    context.minterPrivateKey = minterPrivateKey;
  }

  if (config.pauserKeystorePath || config.pauserPrivateKey) {
    const pauserPrivateKey = await getPrivateKey(config, 'pauser');
    const pauserAccount = privateKeyToAccount(pauserPrivateKey);
    // Store derived address in config
    config.pauserAddress = pauserAccount.address;
    const pauserWallet = createWalletClient({
      account: pauserAccount,
      chain,
      transport: http(config.rpcUrl),
    });
    context.pauserWallet = pauserWallet;
    context.pauserContract = createVeeraContract(config.contractAddress, publicClient, pauserWallet);
    context.pauserPrivateKey = pauserPrivateKey;
  }

  return context;
}

export async function waitForTransaction(publicClient: PublicClient, hash: `0x${string}`) {
  return publicClient.waitForTransactionReceipt({ hash });
}

export function formatAddress(address: Address): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

export function formatAmount(amount: bigint, decimals = 18): string {
  const divisor = BigInt(10 ** decimals);
  const whole = amount / divisor;
  const fraction = amount % divisor;
  if (fraction === 0n) {
    return whole.toString();
  }
  const fractionStr = fraction.toString().padStart(decimals, '0');
  const trimmed = fractionStr.replace(/0+$/, '');
  return `${whole}.${trimmed}`;
}

