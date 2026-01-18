import { Address, PublicClient, WalletClient } from 'viem';
import { base, baseSepolia } from 'viem/chains';
import veeraAbi from './veera-abi.json' assert { type: 'json' };

export const VEERA_ABI = veeraAbi as readonly unknown[];

// Role constants - these match the contract's role definitions
export const DEFAULT_ADMIN_ROLE = '0x0000000000000000000000000000000000000000000000000000000000000000' as const;
// MINTER_ROLE and PAUSER_ROLE are computed as keccak256("MINTER_ROLE") and keccak256("PAUSER_ROLE")
// They should be read from the contract, but we provide constants for convenience
// Note: These will be verified against the contract during tests
export const MINTER_ROLE = '0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6' as const; // keccak256("MINTER_ROLE")
export const PAUSER_ROLE = '0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a' as const; // keccak256("PAUSER_ROLE")

export interface VeeraContract {
  // ERC20
  name(): Promise<string>;
  symbol(): Promise<string>;
  decimals(): Promise<number>;
  totalSupply(): Promise<bigint>;
  balanceOf(account: Address): Promise<bigint>;
  allowance(owner: Address, spender: Address): Promise<bigint>;
  transfer(to: Address, amount: bigint): Promise<`0x${string}`>;
  approve(spender: Address, amount: bigint): Promise<`0x${string}`>;
  transferFrom(from: Address, to: Address, amount: bigint): Promise<`0x${string}`>;

  // Minting (custom function)
  mint(to: Address, amount: bigint): Promise<`0x${string}`>;

  // ERC20Burnable
  burn(amount: bigint): Promise<`0x${string}`>;
  burnFrom(account: Address, amount: bigint): Promise<`0x${string}`>;

  // ERC20Capped
  cap(): Promise<bigint>;

  // ERC20Pausable
  paused(): Promise<boolean>;
  pause(): Promise<`0x${string}`>;
  unpause(): Promise<`0x${string}`>;

  // ERC20Permit
  nonces(owner: Address): Promise<bigint>;
  DOMAIN_SEPARATOR(): Promise<`0x${string}`>;
  permit(
    owner: Address,
    spender: Address,
    value: bigint,
    deadline: bigint,
    v: number,
    r: `0x${string}`,
    s: `0x${string}`
  ): Promise<`0x${string}`>;

  // AccessControl
  DEFAULT_ADMIN_ROLE(): Promise<`0x${string}`>;
  MINTER_ROLE(): Promise<`0x${string}`>;
  PAUSER_ROLE(): Promise<`0x${string}`>;
  hasRole(role: `0x${string}`, account: Address): Promise<boolean>;
  grantRole(role: `0x${string}`, account: Address): Promise<`0x${string}`>;
  revokeRole(role: `0x${string}`, account: Address): Promise<`0x${string}`>;
  getRoleAdmin(role: `0x${string}`): Promise<`0x${string}`>;
}

export function createVeeraContract(
  address: Address,
  publicClient: PublicClient,
  walletClient?: WalletClient
): VeeraContract {
  const read = async <T>(functionName: string, args: unknown[] = []): Promise<T> => {
    return publicClient.readContract({
      address,
      abi: VEERA_ABI,
      functionName: functionName as never,
      args: args as never,
    }) as Promise<T>;
  };

  const write = async (functionName: string, args: unknown[] = []): Promise<`0x${string}`> => {
    if (!walletClient) {
      throw new Error('Wallet client required for write operations');
    }
    // walletClient already has chain configured from setup
    // @ts-expect-error - walletClient.writeContract expects chain but it's already in walletClient config
    const hash = await walletClient.writeContract({
      address,
      abi: VEERA_ABI,
      functionName: functionName as never,
      args: args as never,
    });
    // Wait for transaction receipt
    await publicClient.waitForTransactionReceipt({ hash });
    return hash;
  };

  return {
    // ERC20
    name: () => read<string>('name'),
    symbol: () => read<string>('symbol'),
    decimals: () => read<number>('decimals'),
    totalSupply: () => read<bigint>('totalSupply'),
    balanceOf: (account: Address) => read<bigint>('balanceOf', [account]),
    allowance: (owner: Address, spender: Address) => read<bigint>('allowance', [owner, spender]),
    transfer: (to: Address, amount: bigint) => write('transfer', [to, amount]),
    approve: (spender: Address, amount: bigint) => write('approve', [spender, amount]),
    transferFrom: (from: Address, to: Address, amount: bigint) => write('transferFrom', [from, to, amount]),

    // Minting
    mint: (to: Address, amount: bigint) => write('mint', [to, amount]),

    // ERC20Burnable
    burn: (amount: bigint) => write('burn', [amount]),
    burnFrom: (account: Address, amount: bigint) => write('burnFrom', [account, amount]),

    // ERC20Capped
    cap: () => read<bigint>('cap'),

    // ERC20Pausable
    paused: () => read<boolean>('paused'),
    pause: () => write('pause'),
    unpause: () => write('unpause'),

    // ERC20Permit
    nonces: (owner: Address) => read<bigint>('nonces', [owner]),
    DOMAIN_SEPARATOR: () => read<`0x${string}`>('DOMAIN_SEPARATOR'),
    permit: (
      owner: Address,
      spender: Address,
      value: bigint,
      deadline: bigint,
      v: number,
      r: `0x${string}`,
      s: `0x${string}`
    ) => write('permit', [owner, spender, value, deadline, v, r, s]),

    // AccessControl
    DEFAULT_ADMIN_ROLE: () => read<`0x${string}`>('DEFAULT_ADMIN_ROLE'),
    MINTER_ROLE: () => read<`0x${string}`>('MINTER_ROLE'),
    PAUSER_ROLE: () => read<`0x${string}`>('PAUSER_ROLE'),
    hasRole: (role: `0x${string}`, account: Address) => read<boolean>('hasRole', [role, account]),
    grantRole: (role: `0x${string}`, account: Address) => write('grantRole', [role, account]),
    revokeRole: (role: `0x${string}`, account: Address) => write('revokeRole', [role, account]),
    getRoleAdmin: (role: `0x${string}`) => read<`0x${string}`>('getRoleAdmin', [role]),
  };
}

export function getChain(rpcUrl: string) {
  // Determine chain from RPC URL
  if (rpcUrl.includes('mainnet') || rpcUrl.includes('base.org')) {
    return base;
  } else if (rpcUrl.includes('sepolia') || rpcUrl.includes('84532')) {
    return baseSepolia;
  }
  // Default to base for unknown URLs
  return base;
}

