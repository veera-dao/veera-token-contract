import { Address } from 'viem';
import { TestContext } from './setup.js';
import { createVeeraContract, MINTER_ROLE } from './contracts.js';

/**
 * Find an address that has tokens by checking all configured accounts
 * Returns the first account found with sufficient balance
 */
async function findTokenHolder(
  context: TestContext,
  minAmount: bigint
): Promise<{ address: Address; contract: ReturnType<typeof createVeeraContract> } | null> {
  const { adminContract, config } = context;
  
  // Check admin
  const adminBalance = await adminContract.balanceOf(config.adminAddress);
  if (adminBalance >= minAmount) {
    return { address: config.adminAddress, contract: context.adminContract };
  }
  
  // Check test user
  const userBalance = await adminContract.balanceOf(config.testUserAddress);
  if (userBalance >= minAmount) {
    return { address: config.testUserAddress, contract: context.testUserContract };
  }
  
  // Check minter if configured
  if (config.minterAddress && context.minterContract) {
    const minterBalance = await adminContract.balanceOf(config.minterAddress);
    if (minterBalance >= minAmount) {
      return { address: config.minterAddress, contract: context.minterContract };
    }
  }
  
  // Check pauser if configured
  if (config.pauserAddress && context.pauserContract) {
    const pauserBalance = await adminContract.balanceOf(config.pauserAddress);
    if (pauserBalance >= minAmount) {
      return { address: config.pauserAddress, contract: context.pauserContract };
    }
  }
  
  return null;
}

/**
 * Bootstrap tokens to an address by transferring from another account that has tokens
 * This ensures tests can run even if the target account has zero balance
 */
export async function ensureAccountHasTokens(
  context: TestContext,
  targetAddress: Address,
  requiredAmount: bigint
): Promise<void> {
  const { adminContract } = context;
  
  // Check if target already has enough
  const currentBalance = await adminContract.balanceOf(targetAddress);
  if (currentBalance >= requiredAmount) {
    return; // Already has enough
  }
  
  // Find who has tokens
  const tokenHolder = await findTokenHolder(context, requiredAmount);
  
  if (!tokenHolder) {
    // No configured account has tokens - try minting if admin has MINTER_ROLE
    const { config } = context;
    const adminHasMinterRole = await adminContract.hasRole(MINTER_ROLE, config.adminAddress);
    
    if (adminHasMinterRole) {
      // Check if we can mint (cap not reached)
      const currentSupply = await adminContract.totalSupply();
      const cap = await adminContract.cap();
      const remaining = cap - currentSupply;
      
      if (remaining >= requiredAmount) {
        // Mint tokens directly to target address
        await adminContract.mint(targetAddress, requiredAmount);
        
        // Verify mint succeeded
        const finalBalance = await adminContract.balanceOf(targetAddress);
        if (finalBalance < requiredAmount) {
          throw new Error(`Token bootstrap via mint failed: Expected ${targetAddress} to have at least ${requiredAmount / 10n ** 18n} tokens, but got ${finalBalance / 10n ** 18n}`);
        }
        return; // Successfully minted
      } else if (remaining > 0n) {
        // Cap reached but some room - mint what we can
        await adminContract.mint(targetAddress, remaining);
        const balanceAfterMint = await adminContract.balanceOf(targetAddress);
        
        // Try to find any account with tokens to transfer the rest
        const holderWithAny = await findTokenHolder(context, 1n);
        if (holderWithAny && balanceAfterMint < requiredAmount) {
          const stillNeeded = requiredAmount - balanceAfterMint;
          const holderBalance = await adminContract.balanceOf(holderWithAny.address);
          const transferAmount = holderBalance > stillNeeded ? stillNeeded : holderBalance;
          
          if (transferAmount > 0n) {
            await holderWithAny.contract.transfer(targetAddress, transferAmount);
          }
        }
        
        const finalBalance = await adminContract.balanceOf(targetAddress);
        if (finalBalance < requiredAmount) {
          throw new Error(`Cannot bootstrap tokens: Minted ${remaining / 10n ** 18n} tokens (cap reached), but ${requiredAmount / 10n ** 18n} required. Final balance: ${finalBalance / 10n ** 18n}`);
        }
        return; // Successfully minted and transferred
      } else {
        // Cap fully reached - try to find any account with tokens
        const holderWithAny = await findTokenHolder(context, 1n);
        if (!holderWithAny) {
          const totalSupply = await adminContract.totalSupply();
          throw new Error(`Cannot bootstrap tokens: Cap reached (${cap / 10n ** 18n} tokens), contract has ${totalSupply / 10n ** 18n} tokens in supply, but no configured account holds any tokens. Cannot mint or transfer to ${targetAddress}.`);
        }
        
        // Transfer what we can from the holder
        const holderBalance = await adminContract.balanceOf(holderWithAny.address);
        const transferAmount = holderBalance > requiredAmount ? requiredAmount : holderBalance;
        
        if (transferAmount > 0n) {
          await holderWithAny.contract.transfer(targetAddress, transferAmount);
          const newBalance = await adminContract.balanceOf(targetAddress);
          if (newBalance < requiredAmount) {
            throw new Error(`Cannot bootstrap tokens: Cap reached, only transferred ${transferAmount / 10n ** 18n} tokens to ${targetAddress}, but ${requiredAmount / 10n ** 18n} required. Final balance: ${newBalance / 10n ** 18n}`);
          }
        } else {
          throw new Error(`Cannot bootstrap tokens: Cap reached, token holder ${holderWithAny.address} has insufficient balance (${holderBalance / 10n ** 18n}) to transfer ${requiredAmount / 10n ** 18n} tokens.`);
        }
        return; // Successfully transferred
      }
    } else {
      // Admin doesn't have MINTER_ROLE - try to find any account with tokens
      const totalSupply = await adminContract.totalSupply();
      const holderWithAny = await findTokenHolder(context, 1n);
      
      if (!holderWithAny) {
        throw new Error(`Cannot bootstrap tokens: Contract has ${totalSupply / 10n ** 18n} tokens in supply, but no configured account holds any tokens and admin does not have MINTER_ROLE. Cannot mint or transfer to ${targetAddress}.`);
      }
      
      // Transfer what we can
      const holderBalance = await adminContract.balanceOf(holderWithAny.address);
      const transferAmount = holderBalance > requiredAmount ? requiredAmount : holderBalance;
      
      if (transferAmount > 0n) {
        await holderWithAny.contract.transfer(targetAddress, transferAmount);
        const newBalance = await adminContract.balanceOf(targetAddress);
        if (newBalance < requiredAmount) {
          throw new Error(`Cannot bootstrap tokens: Only transferred ${transferAmount / 10n ** 18n} tokens to ${targetAddress}, but ${requiredAmount / 10n ** 18n} required. Admin does not have MINTER_ROLE to mint more.`);
        }
      } else {
        throw new Error(`Cannot bootstrap tokens: Token holder ${holderWithAny.address} has insufficient balance (${holderBalance / 10n ** 18n}) to transfer ${requiredAmount / 10n ** 18n} tokens. Admin does not have MINTER_ROLE to mint more.`);
      }
    }
  } else {
    // Transfer required amount
    const amountToTransfer = requiredAmount - currentBalance;
    await tokenHolder.contract.transfer(targetAddress, amountToTransfer);
    
    // Verify transfer succeeded
    const finalBalance = await adminContract.balanceOf(targetAddress);
    if (finalBalance < requiredAmount) {
      throw new Error(`Token bootstrap failed: Expected ${targetAddress} to have at least ${requiredAmount / 10n ** 18n} tokens, but got ${finalBalance / 10n ** 18n}`);
    }
  }
}

/**
 * Clear allowance between two addresses
 */
export async function clearAllowance(
  context: TestContext,
  owner: Address,
  spender: Address
): Promise<void> {
  const { adminContract, publicClient } = context;
  const currentAllowance = await adminContract.allowance(owner, spender);
  
  if (currentAllowance > 0n) {
    // Get the contract instance for the owner
    let ownerContract: ReturnType<typeof createVeeraContract>;
    if (owner === context.config.adminAddress) {
      ownerContract = context.adminContract;
    } else if (owner === context.config.testUserAddress) {
      ownerContract = context.testUserContract;
    } else if (owner === context.config.minterAddress && context.minterContract) {
      ownerContract = context.minterContract;
    } else if (owner === context.config.pauserAddress && context.pauserContract) {
      ownerContract = context.pauserContract;
    } else {
      throw new Error(`Cannot clear allowance: Owner ${owner} is not a configured test account`);
    }
    
    const txHash = await ownerContract.approve(spender, 0n);
    // Wait for transaction confirmation
    await publicClient.waitForTransactionReceipt({ hash: txHash });
    // Wait a moment for state to update
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
}

