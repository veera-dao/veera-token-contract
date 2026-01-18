import chalk from 'chalk';
import { Address, PublicClient, formatEther, parseEther } from 'viem';
import { TestContext } from './setup.js';
import { VEERA_ABI, MINTER_ROLE, PAUSER_ROLE, DEFAULT_ADMIN_ROLE, createVeeraContract } from './contracts.js';

export interface DeploymentValidation {
  isValid: boolean;
  issues: string[];
  warnings: string[];
}

export interface GasEstimate {
  operation: string;
  account: Address;
  gas: bigint;
  costWei: bigint;
  costEth: string;
}

export interface AccountBalance {
  address: Address;
  name: string;
  balanceWei: bigint;
  balanceEth: string;
  requiredWei: bigint;
  requiredEth: string;
  sufficient: boolean;
}

/**
 * Estimate gas for a contract write operation
 */
async function estimateGas(
  publicClient: PublicClient,
  contractAddress: Address,
  functionName: string,
  args: unknown[],
  account: Address,
  debug = false
): Promise<bigint> {
  try {
    const gas = await publicClient.estimateContractGas({
      address: contractAddress,
      abi: VEERA_ABI,
      functionName: functionName as never,
      args: args as never,
      account,
    });
    return gas;
  } catch (error) {
    // If estimation fails, return a conservative estimate
    // This can happen if the transaction would revert
    console.log(chalk.yellow(`  ⚠ Could not estimate gas for ${functionName}, using conservative estimate`));
    
    if (debug) {
      console.log(chalk.gray('  Debug information:'));
      if (error instanceof Error) {
        console.log(chalk.gray(`    Error: ${error.message}`));
        if (error.stack) {
          console.log(chalk.gray(`    Stack: ${error.stack.split('\n').slice(0, 3).join('\n')}`));
        }
        // Try to extract revert reason if available
        if (error.message.includes('revert') || error.message.includes('execution reverted')) {
          console.log(chalk.gray(`    This usually means the transaction would revert on-chain`));
          console.log(chalk.gray(`    Common reasons: insufficient balance, insufficient allowance, contract paused, etc.`));
        }
      } else {
        console.log(chalk.gray(`    Error: ${String(error)}`));
      }
      console.log(chalk.gray(`    Function: ${functionName}`));
      console.log(chalk.gray(`    Args: ${JSON.stringify(args, (_, v) => typeof v === 'bigint' ? v.toString() : v)}`));
      console.log(chalk.gray(`    Account: ${account}`));
      console.log('');
    }
    
    return 200000n; // Conservative estimate
  }
}

/**
 * Get current gas price from the network
 */
async function getGasPrice(publicClient: PublicClient): Promise<bigint> {
  try {
    const feeData = await publicClient.estimateFeesPerGas();
    // Use maxFeePerGas if available (EIP-1559), otherwise use gasPrice
    return feeData.maxFeePerGas || feeData.gasPrice || parseEther('0.00000002'); // 20 gwei fallback
  } catch (error) {
    // Fallback to a conservative gas price
    return parseEther('0.00000002'); // 20 gwei
  }
}

/**
 * Estimate all gas costs for the test suite
 */
export async function estimateTestCosts(context: TestContext): Promise<GasEstimate[]> {
  const estimates: GasEstimate[] = [];
  const { config, publicClient } = context;
  const testAmount = 100n * 10n ** 18n; // 100 tokens
  const smallAmount = 10n * 10n ** 18n; // 10 tokens
  const debug = config.debug || false;

  console.log(chalk.blue('Estimating gas costs for all operations...\n'));
  if (debug) {
    console.log(chalk.gray('  Debug mode enabled - full error details will be shown\n'));
  }

  const gasPrice = await getGasPrice(publicClient);
  console.log(chalk.gray(`  Current gas price: ${formatEther(gasPrice)} ETH per gas unit\n`));

  // Create contract instance for state checks
  const contract = createVeeraContract(config.contractAddress, publicClient);
  
  if (debug) {
    console.log(chalk.gray('  Checking contract state before estimating...\n'));
  }

  // Check contract state
  const adminBalance = await contract.balanceOf(config.adminAddress);
  const adminHasMinterRole = await contract.hasRole(MINTER_ROLE, config.adminAddress);
  const adminHasPauserRole = await contract.hasRole(PAUSER_ROLE, config.adminAddress);
  const adminHasAdminRole = await contract.hasRole(DEFAULT_ADMIN_ROLE, config.adminAddress);

  // ERC20 Operations
  try {
    // Only estimate transfer if admin has balance
    if (adminBalance > 0n) {
      const transferAmount = adminBalance >= testAmount ? testAmount : adminBalance;
      const transferGas = await estimateGas(
        publicClient,
        config.contractAddress,
        'transfer',
        [config.testUserAddress, transferAmount],
        config.adminAddress,
        debug
      );
      estimates.push({
        operation: 'ERC20: transfer',
        account: config.adminAddress,
        gas: transferGas,
        costWei: transferGas * gasPrice,
        costEth: formatEther(transferGas * gasPrice),
      });
    } else if (debug) {
      console.log(chalk.gray(`  ⚠ Skipping transfer estimate - admin has 0 token balance\n`));
    }

    const approveGas = await estimateGas(
      publicClient,
      config.contractAddress,
      'approve',
      [config.testUserAddress, testAmount],
      config.adminAddress,
      debug
    );
    estimates.push({
      operation: 'ERC20: approve',
      account: config.adminAddress,
      gas: approveGas,
      costWei: approveGas * gasPrice,
      costEth: formatEther(approveGas * gasPrice),
    });

    // Skip transferFrom - it requires allowance setup which we can't assume
    if (debug) {
      console.log(chalk.gray(`  ⚠ Skipping transferFrom estimate - requires allowance setup\n`));
    }
  } catch (error) {
    console.log(chalk.yellow('  ⚠ Some ERC20 gas estimates failed'));
  }

  // Minting Operations
  try {
    // Only estimate mint if admin has MINTER_ROLE
    if (adminHasMinterRole) {
      const mintGas = await estimateGas(
        publicClient,
        config.contractAddress,
        'mint',
        [config.testUserAddress, testAmount],
        config.adminAddress,
        debug
      );
      estimates.push({
        operation: 'Mint tokens',
        account: config.adminAddress,
        gas: mintGas,
        costWei: mintGas * gasPrice,
        costEth: formatEther(mintGas * gasPrice),
      });
    } else if (debug) {
      console.log(chalk.gray(`  ⚠ Skipping mint estimate - admin does not have MINTER_ROLE\n`));
    }
  } catch (error) {
    console.log(chalk.yellow('  ⚠ Mint gas estimate failed'));
  }

  // Burning Operations
  try {
    // Only estimate burn if admin has balance
    if (adminBalance > 0n) {
      const burnAmount = adminBalance >= smallAmount ? smallAmount : adminBalance;
      const burnGas = await estimateGas(
        publicClient,
        config.contractAddress,
        'burn',
        [burnAmount],
        config.adminAddress,
        debug
      );
      estimates.push({
        operation: 'Burn tokens',
        account: config.adminAddress,
        gas: burnGas,
        costWei: burnGas * gasPrice,
        costEth: formatEther(burnGas * gasPrice),
      });
    } else if (debug) {
      console.log(chalk.gray(`  ⚠ Skipping burn estimate - admin has 0 token balance\n`));
    }

    // Skip burnFrom - it requires allowance setup
    if (debug) {
      console.log(chalk.gray(`  ⚠ Skipping burnFrom estimate - requires allowance setup\n`));
    }
  } catch (error) {
    console.log(chalk.yellow('  ⚠ Burn gas estimates failed'));
  }

  // Pausing Operations
  try {
    // Only estimate pause/unpause if admin has PAUSER_ROLE
    if (adminHasPauserRole) {
      const pauseGas = await estimateGas(
        publicClient,
        config.contractAddress,
        'pause',
        [],
        config.adminAddress,
        debug
      );
      estimates.push({
        operation: 'Pause contract',
        account: config.adminAddress,
        gas: pauseGas,
        costWei: pauseGas * gasPrice,
        costEth: formatEther(pauseGas * gasPrice),
      });

      const unpauseGas = await estimateGas(
        publicClient,
        config.contractAddress,
        'unpause',
        [],
        config.adminAddress,
        debug
      );
      estimates.push({
        operation: 'Unpause contract',
        account: config.adminAddress,
        gas: unpauseGas,
        costWei: unpauseGas * gasPrice,
        costEth: formatEther(unpauseGas * gasPrice),
      });
    } else if (debug) {
      console.log(chalk.gray(`  ⚠ Skipping pause/unpause estimates - admin does not have PAUSER_ROLE\n`));
    }
  } catch (error) {
    console.log(chalk.yellow('  ⚠ Pause gas estimates failed'));
  }

  // Role Management
  try {
    // Only estimate role operations if admin has DEFAULT_ADMIN_ROLE
    if (adminHasAdminRole) {
      const grantRoleGas = await estimateGas(
        publicClient,
        config.contractAddress,
        'grantRole',
        [MINTER_ROLE, config.testUserAddress],
        config.adminAddress,
        debug
      );
      estimates.push({
        operation: 'Grant role',
        account: config.adminAddress,
        gas: grantRoleGas,
        costWei: grantRoleGas * gasPrice,
        costEth: formatEther(grantRoleGas * gasPrice),
      });

      const revokeRoleGas = await estimateGas(
        publicClient,
        config.contractAddress,
        'revokeRole',
        [MINTER_ROLE, config.testUserAddress],
        config.adminAddress,
        debug
      );
      estimates.push({
        operation: 'Revoke role',
        account: config.adminAddress,
        gas: revokeRoleGas,
        costWei: revokeRoleGas * gasPrice,
        costEth: formatEther(revokeRoleGas * gasPrice),
      });
    } else if (debug) {
      console.log(chalk.gray(`  ⚠ Skipping role management estimates - admin does not have DEFAULT_ADMIN_ROLE\n`));
    }
  } catch (error) {
    console.log(chalk.yellow('  ⚠ Role management gas estimates failed'));
  }

  // Permit (if applicable)
  try {
    // Permit is complex, use a conservative estimate
    estimates.push({
      operation: 'ERC20Permit: permit',
      account: config.testUserAddress,
      gas: 80000n,
      costWei: 80000n * gasPrice,
      costEth: formatEther(80000n * gasPrice),
    });
  } catch (error) {
    // Ignore
  }

  // Add estimates for optional accounts if they exist
  if (context.minterWallet && config.minterAddress) {
    try {
      const minterHasRole = await contract.hasRole(MINTER_ROLE, config.minterAddress);
      if (minterHasRole) {
        const minterMintGas = await estimateGas(
          publicClient,
          config.contractAddress,
          'mint',
          [config.testUserAddress, smallAmount],
          config.minterAddress,
          debug
        );
        estimates.push({
          operation: 'Mint (as minter)',
          account: config.minterAddress,
          gas: minterMintGas,
          costWei: minterMintGas * gasPrice,
          costEth: formatEther(minterMintGas * gasPrice),
        });
      } else if (debug) {
        console.log(chalk.gray(`  ⚠ Skipping minter mint estimate - minter does not have MINTER_ROLE\n`));
      }
    } catch (error) {
      // Ignore
    }
  }

  if (context.pauserWallet && config.pauserAddress) {
    try {
      const pauserHasRole = await contract.hasRole(PAUSER_ROLE, config.pauserAddress);
      if (pauserHasRole) {
        const pauserPauseGas = await estimateGas(
          publicClient,
          config.contractAddress,
          'pause',
          [],
          config.pauserAddress,
          debug
        );
        estimates.push({
          operation: 'Pause (as pauser)',
          account: config.pauserAddress,
          gas: pauserPauseGas,
          costWei: pauserPauseGas * gasPrice,
          costEth: formatEther(pauserPauseGas * gasPrice),
        });
      } else if (debug) {
        console.log(chalk.gray(`  ⚠ Skipping pauser pause estimate - pauser does not have PAUSER_ROLE\n`));
      }
    } catch (error) {
      // Ignore
    }
  }

  return estimates;
}

/**
 * Check account balances and calculate required amounts
 */
export async function checkAccountBalances(
  context: TestContext,
  estimates: GasEstimate[]
): Promise<AccountBalance[]> {
  const { publicClient, config } = context;
  const accounts: AccountBalance[] = [];

  // Calculate required gas per account
  const gasPerAccount = new Map<Address, bigint>();
  for (const estimate of estimates) {
    const current = gasPerAccount.get(estimate.account) || 0n;
    gasPerAccount.set(estimate.account, current + estimate.costWei);
  }

  // Add buffer (50% extra for safety)
  const buffer = 150n; // 150% = 50% buffer

  // Check admin account
  const adminBalance = await publicClient.getBalance({ address: config.adminAddress });
  const adminRequired = (gasPerAccount.get(config.adminAddress) || 0n) * buffer / 100n;
  accounts.push({
    address: config.adminAddress,
    name: 'Admin',
    balanceWei: adminBalance,
    balanceEth: formatEther(adminBalance),
    requiredWei: adminRequired,
    requiredEth: formatEther(adminRequired),
    sufficient: adminBalance >= adminRequired,
  });

  // Check test user account
  const userBalance = await publicClient.getBalance({ address: config.testUserAddress });
  const userRequired = (gasPerAccount.get(config.testUserAddress) || 0n) * buffer / 100n;
  accounts.push({
    address: config.testUserAddress,
    name: 'Test User',
    balanceWei: userBalance,
    balanceEth: formatEther(userBalance),
    requiredWei: userRequired,
    requiredEth: formatEther(userRequired),
    sufficient: userBalance >= userRequired,
  });

  // Check optional accounts
  if (config.minterAddress) {
    const minterBalance = await publicClient.getBalance({ address: config.minterAddress });
    const minterRequired = (gasPerAccount.get(config.minterAddress) || 0n) * buffer / 100n;
    accounts.push({
      address: config.minterAddress,
      name: 'Minter',
      balanceWei: minterBalance,
      balanceEth: formatEther(minterBalance),
      requiredWei: minterRequired,
      requiredEth: formatEther(minterRequired),
      sufficient: minterBalance >= minterRequired,
    });
  }

  if (config.pauserAddress) {
    const pauserBalance = await publicClient.getBalance({ address: config.pauserAddress });
    const pauserRequired = (gasPerAccount.get(config.pauserAddress) || 0n) * buffer / 100n;
    accounts.push({
      address: config.pauserAddress,
      name: 'Pauser',
      balanceWei: pauserBalance,
      balanceEth: formatEther(pauserBalance),
      requiredWei: pauserRequired,
      requiredEth: formatEther(pauserRequired),
      sufficient: pauserBalance >= pauserRequired,
    });
  }

  return accounts;
}

/**
 * Validate contract deployment state
 */
export async function validateContractDeployment(context: TestContext): Promise<DeploymentValidation> {
  const { config, publicClient } = context;
  const issues: string[] = [];
  const warnings: string[] = [];
  
  const contract = createVeeraContract(config.contractAddress, publicClient);
  
  // Check contract name and symbol
  try {
    const name = await contract.name();
    const symbol = await contract.symbol();
    if (name !== 'Veera Token') {
      warnings.push(`Contract name is "${name}", expected "Veera Token"`);
    }
    if (symbol !== 'VEERA') {
      warnings.push(`Contract symbol is "${symbol}", expected "VEERA"`);
    }
  } catch (error) {
    issues.push(`Cannot read contract metadata: ${error instanceof Error ? error.message : String(error)}`);
  }
  
  // Check admin roles (CRITICAL)
  try {
    const hasAdminRole = await contract.hasRole(DEFAULT_ADMIN_ROLE, config.adminAddress);
    const hasMinterRole = await contract.hasRole(MINTER_ROLE, config.adminAddress);
    const hasPauserRole = await contract.hasRole(PAUSER_ROLE, config.adminAddress);
    
    if (!hasAdminRole) {
      issues.push(`Admin address ${config.adminAddress} does NOT have DEFAULT_ADMIN_ROLE. Contract may have been deployed with a different admin address.`);
    }
    if (!hasMinterRole) {
      issues.push(`Admin address ${config.adminAddress} does NOT have MINTER_ROLE. Contract may have been deployed with a different admin address.`);
    }
    if (!hasPauserRole) {
      issues.push(`Admin address ${config.adminAddress} does NOT have PAUSER_ROLE. Contract may have been deployed with a different admin address.`);
    }
  } catch (error) {
    issues.push(`Cannot check admin roles: ${error instanceof Error ? error.message : String(error)}`);
  }
  
  // Check initial pause state
  try {
    const isPaused = await contract.paused();
    if (isPaused) {
      warnings.push('Contract is currently paused. Some tests may need to unpause first.');
    }
  } catch (error) {
    warnings.push(`Cannot check pause state: ${error instanceof Error ? error.message : String(error)}`);
  }
  
  // Check token balance and total supply
  try {
    const adminBalance = await contract.balanceOf(config.adminAddress);
    const totalSupply = await contract.totalSupply();
    if (adminBalance === 0n && totalSupply > 0n) {
      warnings.push(`Admin has 0 token balance but contract has ${totalSupply / 10n ** 18n} tokens in supply. Transfer tests will transfer tokens TO admin.`);
    } else if (adminBalance === 0n && totalSupply === 0n) {
      warnings.push(`Admin has 0 token balance and contract has 0 total supply. Transfer tests will be skipped.`);
    }
  } catch (error) {
    warnings.push(`Cannot check admin token balance: ${error instanceof Error ? error.message : String(error)}`);
  }
  
  return {
    isValid: issues.length === 0,
    issues,
    warnings,
  };
}

/**
 * Run pre-flight checks: estimate costs and verify balances
 */
export async function runPreflightChecks(context: TestContext): Promise<boolean> {
  console.log(chalk.cyan.bold('\n' + '='.repeat(60)));
  console.log(chalk.cyan.bold('  PRE-FLIGHT CHECKS'));
  console.log(chalk.cyan('='.repeat(60) + '\n'));

  // Print all addresses that will be used
  console.log(chalk.blue.bold('Accounts Used:\n'));
  console.log(chalk.cyan(`  Admin: ${context.config.adminAddress}`));
  console.log(chalk.cyan(`  Test User: ${context.config.testUserAddress}`));
  if (context.config.minterAddress) {
    console.log(chalk.cyan(`  Minter: ${context.config.minterAddress}`));
  }
  if (context.config.pauserAddress) {
    console.log(chalk.cyan(`  Pauser: ${context.config.pauserAddress}`));
  }
  console.log(chalk.cyan(`  Contract: ${context.config.contractAddress}\n`));

  try {
    // Validate contract deployment first
    console.log(chalk.blue.bold('Contract Deployment Validation:\n'));
    const deploymentValidation = await validateContractDeployment(context);
    
    if (deploymentValidation.warnings.length > 0) {
      for (const warning of deploymentValidation.warnings) {
        console.log(chalk.yellow(`  ⚠ ${warning}`));
      }
      console.log('');
    }
    
    if (deploymentValidation.issues.length > 0) {
      console.log(chalk.red.bold('  ❌ DEPLOYMENT ISSUES DETECTED:\n'));
      for (const issue of deploymentValidation.issues) {
        console.log(chalk.red(`    ✗ ${issue}`));
      }
      console.log(chalk.red.bold('\n  ⚠️  CRITICAL: Contract deployment validation failed!'));
      console.log(chalk.red('     The contract may have been deployed with a different admin address.'));
      console.log(chalk.red('     Tests will likely fail. Please verify the contract deployment.\n'));
      return false;
    }
    
    console.log(chalk.green('  ✓ Contract deployment validation passed\n'));
    // Estimate gas costs
    const estimates = await estimateTestCosts(context);

    // Calculate totals
    const totalGas = estimates.reduce((sum, e) => sum + e.gas, 0n);
    const totalCostWei = estimates.reduce((sum, e) => sum + e.costWei, 0n);
    const totalCostEth = formatEther(totalCostWei);

    // Group by account
    const byAccount = new Map<Address, { operations: number; totalGas: bigint; totalCost: bigint }>();
    for (const estimate of estimates) {
      const existing = byAccount.get(estimate.account) || { operations: 0, totalGas: 0n, totalCost: 0n };
      byAccount.set(estimate.account, {
        operations: existing.operations + 1,
        totalGas: existing.totalGas + estimate.gas,
        totalCost: existing.totalCost + estimate.costWei,
      });
    }

    // Display estimates
    console.log(chalk.blue.bold('Gas Cost Estimates:\n'));
    for (const [address, stats] of byAccount.entries()) {
      const accountName = context.config.adminAddress === address
        ? 'Admin'
        : context.config.testUserAddress === address
          ? 'Test User'
          : context.config.minterAddress === address
            ? 'Minter'
            : context.config.pauserAddress === address
              ? 'Pauser'
              : 'Unknown';
      console.log(chalk.cyan(`  ${accountName} (${address}):`));
      console.log(chalk.gray(`    Operations: ${stats.operations}`));
      console.log(chalk.gray(`    Total Gas: ${stats.totalGas.toLocaleString()}`));
      console.log(chalk.gray(`    Estimated Cost: ${formatEther(stats.totalCost)} ETH\n`));
    }

    console.log(chalk.cyan.bold('Overall Totals:'));
    console.log(chalk.gray(`  Total Operations: ${estimates.length}`));
    console.log(chalk.gray(`  Total Gas: ${totalGas.toLocaleString()}`));
    console.log(chalk.gray(`  Total Estimated Cost: ${totalCostEth} ETH\n`));

    // Check balances
    console.log(chalk.blue.bold('Account Balance Check:\n'));
    const balances = await checkAccountBalances(context, estimates);

    let allSufficient = true;
    for (const balance of balances) {
      const status = balance.sufficient ? chalk.green('✓') : chalk.red('✗');
      console.log(`${status} ${balance.name} (${balance.address}):`);
      console.log(chalk.gray(`  Balance: ${balance.balanceEth} ETH`));
      console.log(chalk.gray(`  Required: ${balance.requiredEth} ETH (with 50% buffer)`));
      if (balance.sufficient) {
        const remaining = formatEther(balance.balanceWei - balance.requiredWei);
        console.log(chalk.green(`  ✓ Sufficient (${remaining} ETH remaining)\n`));
      } else {
        const shortfall = formatEther(balance.requiredWei - balance.balanceWei);
        console.log(chalk.red(`  ✗ Insufficient (${shortfall} ETH short)\n`));
        allSufficient = false;
      }
    }

    if (!allSufficient) {
      console.log(chalk.red.bold('\n⚠️  WARNING: Some accounts have insufficient balance!'));
      console.log(chalk.red('   Tests may fail partway through execution.\n'));
      return false;
    }

    console.log(chalk.green.bold('\n✓ All pre-flight checks passed!\n'));
    return true;
  } catch (error) {
    console.error(chalk.red('Pre-flight check failed:'));
    console.error(error);
    return false;
  }
}

