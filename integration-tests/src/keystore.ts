import { readFileSync, existsSync } from 'fs';
import { resolve } from 'path';
import { Wallet } from 'ethers';

/**
 * Read password from file or return as-is if it's not a file path
 */
function getPassword(value: string): string {
  // Check if it's a file path (exists and is readable)
  try {
    if (existsSync(value)) {
      const password = readFileSync(value, 'utf-8').trim();
      return password;
    }
  } catch (error) {
    // Not a file, treat as password string
  }
  return value;
}

/**
 * Decrypt keystore file and extract private key
 */
export async function decryptKeystore(
  keystorePath: string,
  password: string
): Promise<`0x${string}`> {
  const resolvedPath = resolve(keystorePath);
  
  if (!existsSync(resolvedPath)) {
    throw new Error(`Keystore file not found: ${resolvedPath}`);
  }

  try {
    const keystoreJson = readFileSync(resolvedPath, 'utf-8');
    const wallet = await Wallet.fromEncryptedJson(keystoreJson, password);
    return wallet.privateKey as `0x${string}`;
  } catch (error) {
    if (error instanceof Error) {
      if (error.message.includes('invalid password') || error.message.includes('MAC')) {
        throw new Error(`Invalid password for keystore: ${resolvedPath}`);
      }
      throw new Error(`Failed to decrypt keystore ${resolvedPath}: ${error.message}`);
    }
    throw error;
  }
}

/**
 * Get password for a keystore with fallback chain:
 * 1. Account-specific password (CLI arg or env var)
 * 2. Global keystore password (CLI arg or env var)
 * 3. Prompt user
 */
export async function getKeystorePassword(
  accountType: string,
  accountSpecificPassword?: string,
  globalPassword?: string
): Promise<string> {
  // Try account-specific password first
  if (accountSpecificPassword) {
    return getPassword(accountSpecificPassword);
  }

  // Try global password
  if (globalPassword) {
    return getPassword(globalPassword);
  }

  // Prompt user
  const readline = await import('readline');
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve) => {
    rl.question(`Enter password for ${accountType} keystore: `, (password) => {
      rl.close();
      resolve(password);
    });
  });
}

