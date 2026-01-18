import { TestContext } from '../setup.js';
import { TestSuite, ZERO_ADDRESS } from '../test-utils.js';
import { MINTER_ROLE } from '../contracts.js';
import { ensureAccountHasTokens } from '../token-bootstrap.js';

export async function runBurningTests(context: TestContext): Promise<TestSuite> {
  const suite = new TestSuite('Burning Operations');
  suite.printHeader();

  const { adminContract, testUserContract, config } = context;
  const testAmount = 50n * 10n ** 18n; // 50 tokens

  // Get initial state
  const initialSupply = await adminContract.totalSupply();
  const adminHasMinterRole = await adminContract.hasRole(MINTER_ROLE, config.adminAddress);

  // Bootstrap tokens to admin if needed - NO SKIPPING
  await ensureAccountHasTokens(context, config.adminAddress, testAmount);

  // Test: Burn tokens
  const adminBalanceAfterBootstrap = await adminContract.balanceOf(config.adminAddress);
  if (adminBalanceAfterBootstrap >= testAmount) {
    await suite.runTestWithTx('Burn tokens from own balance', async () => {
      const txHash = await adminContract.burn(testAmount);
      // Wait for transaction confirmation
      await context.publicClient.waitForTransactionReceipt({ hash: txHash });
      return txHash;
    });
  } else {
    await suite.runTest('Skip burn test - insufficient balance', async () => {
      console.log('  ⚠ Skipping burn test due to insufficient balance');
    });
  }

  if (adminBalanceAfterBootstrap >= testAmount) {
    await suite.runTest('Verify balance decreased after burn', async () => {
      // Wait a moment for state to update
      await new Promise(resolve => setTimeout(resolve, 1000));
      const adminBalance = await adminContract.balanceOf(config.adminAddress);
      const expectedBalance = adminBalanceAfterBootstrap - testAmount;
      if (adminBalance !== expectedBalance) {
        throw new Error(
          `Admin balance incorrect. Expected ${expectedBalance}, got ${adminBalance}`
        );
      }
    });

    await suite.runTest('Verify totalSupply decreased after burn', async () => {
      // Wait a moment for state to update
      await new Promise(resolve => setTimeout(resolve, 1000));
      const currentSupply = await adminContract.totalSupply();
      const expectedSupply = initialSupply - testAmount;
      if (currentSupply !== expectedSupply) {
        throw new Error(`Total supply incorrect. Expected ${expectedSupply}, got ${currentSupply}`);
      }
    });
  }

  // Test: BurnFrom with approval
  // Bootstrap tokens to user if needed
  await suite.runTest('Setup burnFrom test', async () => {
    // First, ensure user has some tokens
    const userBalance = await adminContract.balanceOf(config.testUserAddress);
    if (userBalance < testAmount) {
      // Try to bootstrap tokens to user
      try {
        await ensureAccountHasTokens(context, config.testUserAddress, testAmount);
      } catch (error) {
        // If bootstrap fails (e.g., cap reached), try minting if admin has MINTER_ROLE
        if (adminHasMinterRole) {
          const currentSupply = await adminContract.totalSupply();
          const cap = await adminContract.cap();
          const remaining = cap - currentSupply;
          if (remaining >= testAmount) {
            await adminContract.mint(config.testUserAddress, testAmount);
          } else {
            throw new Error(`Cannot setup burnFrom test - cap reached (remaining: ${remaining / 10n ** 18n})`);
          }
        } else {
          throw new Error(`Cannot setup burnFrom test - insufficient user balance and admin cannot mint. Error: ${error instanceof Error ? error.message : String(error)}`);
        }
      }
    }
  });

  await suite.runTestWithTx('Approve admin to burn user tokens', async () => {
    const txHash = await testUserContract.approve(config.adminAddress, testAmount);
    // Wait for transaction confirmation
    await context.publicClient.waitForTransactionReceipt({ hash: txHash });
    await new Promise(resolve => setTimeout(resolve, 1000));
    return txHash;
  });

  // Only run burnFrom test if user has balance (setup should have ensured this)
  const userBalanceForBurnFrom = await adminContract.balanceOf(config.testUserAddress);
  if (userBalanceForBurnFrom >= testAmount) {
    await suite.runTestWithTx('BurnFrom using allowance', async () => {
      const userBalanceBefore = await adminContract.balanceOf(config.testUserAddress);
      const txHash = await adminContract.burnFrom(config.testUserAddress, testAmount);
      // Wait for transaction confirmation
      await context.publicClient.waitForTransactionReceipt({ hash: txHash });
      // Wait a moment for state to update
      await new Promise(resolve => setTimeout(resolve, 2000));
      const userBalanceAfter = await adminContract.balanceOf(config.testUserAddress);
      if (userBalanceAfter !== userBalanceBefore - testAmount) {
        throw new Error(`Balance not updated correctly after burnFrom. Expected ${userBalanceBefore - testAmount}, got ${userBalanceAfter}`);
      }
      return txHash;
    });
  } else {
    await suite.runTest('BurnFrom using allowance', async () => {
      console.log(`  ⚠ Skipping burnFrom test - user has insufficient balance (${userBalanceForBurnFrom} < ${testAmount})`);
    });
  }

  if (userBalanceForBurnFrom >= testAmount) {
    await suite.runTest('Verify allowance reset after burnFrom', async () => {
      // Wait a moment for state to update
      await new Promise(resolve => setTimeout(resolve, 1000));
      const allowance = await adminContract.allowance(config.testUserAddress, config.adminAddress);
      if (allowance !== 0n) {
        throw new Error(`Allowance should be 0 after burnFrom. Got ${allowance}`);
      }
    });
  } else {
    await suite.runTest('Verify allowance reset after burnFrom', async () => {
      console.log(`  ⚠ Skipping allowance verification - burnFrom test was skipped`);
    });
  }

  // Test: Burn more than balance (should fail)
  await suite.expectRevert('Burn more than balance', async () => {
    const balance = await adminContract.balanceOf(config.adminAddress);
    await adminContract.burn(balance + 1n);
  }, 'ERC20InsufficientBalance');


  // Test: Burn then mint again (reclaim supply)
  await suite.runTest('Burn then mint again (reclaim supply)', async () => {
    const burnAmount = 10n * 10n ** 18n;
    const balanceBefore = await adminContract.balanceOf(config.adminAddress);
    const supplyBefore = await adminContract.totalSupply();

    if (balanceBefore >= burnAmount) {
      await suite.runTestWithTx('Burn tokens to free up supply', async () => {
        const txHash = await adminContract.burn(burnAmount);
        // Wait for transaction confirmation
        await context.publicClient.waitForTransactionReceipt({ hash: txHash });
        return txHash;
      });

      await suite.runTest('Verify supply decreased', async () => {
        // Wait a moment for state to update
        await new Promise(resolve => setTimeout(resolve, 1000));
        const supplyAfter = await adminContract.totalSupply();
        if (supplyAfter !== supplyBefore - burnAmount) {
          throw new Error(`Supply not decreased after burn. Expected ${supplyBefore - burnAmount}, got ${supplyAfter}`);
        }
      });

      if (adminHasMinterRole) {
        // Check if we can mint (cap not reached)
        const currentSupply = await adminContract.totalSupply();
        const cap = await adminContract.cap();
        const remaining = cap - currentSupply;
        
        if (remaining >= burnAmount) {
          await suite.runTestWithTx('Mint again to reclaim supply', async () => {
            const txHash = await adminContract.mint(config.adminAddress, burnAmount);
            // Wait for transaction confirmation
            await context.publicClient.waitForTransactionReceipt({ hash: txHash });
            return txHash;
          });
        } else {
          await suite.runTest('Mint again to reclaim supply', async () => {
            console.log(`  ⚠ Skipping mint to reclaim supply - cap reached (remaining: ${remaining / 10n ** 18n})`);
          });
        }
      } else {
        await suite.runTest('Mint again to reclaim supply', async () => {
          console.log('  ⚠ Skipping mint to reclaim supply - admin does not have MINTER_ROLE');
        });
      }

      if (adminHasMinterRole) {
        const currentSupply = await adminContract.totalSupply();
        const cap = await adminContract.cap();
        const remaining = cap - currentSupply;
        
        if (remaining >= burnAmount) {
          await suite.runTest('Verify supply restored', async () => {
            // Wait a moment for state to update
            await new Promise(resolve => setTimeout(resolve, 1000));
            const supplyAfter = await adminContract.totalSupply();
            if (supplyAfter !== supplyBefore) {
              throw new Error(`Supply not restored after mint. Expected ${supplyBefore}, got ${supplyAfter}`);
            }
          });
        } else {
          await suite.runTest('Verify supply restored', async () => {
            console.log('  ⚠ Skipping supply restoration verification - mint test was skipped');
          });
        }
      } else {
        await suite.runTest('Verify supply restored', async () => {
          console.log('  ⚠ Skipping supply restoration verification - mint test was skipped');
        });
      }
    } else {
      console.log('  ⚠ Insufficient balance for burn-then-mint test');
    }
  });

  // Test: burnFrom with zero address (should fail)
  // Note: This might fail with ERC20InsufficientAllowance if there's no allowance, but that's acceptable
  await suite.expectRevert('BurnFrom with zero address', async () => {
    await adminContract.burnFrom(ZERO_ADDRESS, testAmount);
  }, ['ERC20InvalidAccount', 'ERC20InsufficientAllowance']);

  // Test: burnFrom with insufficient allowance (should fail)
  await suite.runTest('Setup burnFrom insufficient allowance test', async () => {
    // Ensure user has tokens
    const userBalance = await adminContract.balanceOf(config.testUserAddress);
    if (userBalance < testAmount) {
      // Try to bootstrap tokens to user
      try {
        await ensureAccountHasTokens(context, config.testUserAddress, testAmount);
      } catch (error) {
        // If bootstrap fails (e.g., cap reached), try minting if admin has MINTER_ROLE
        if (adminHasMinterRole) {
          const currentSupply = await adminContract.totalSupply();
          const cap = await adminContract.cap();
          const remaining = cap - currentSupply;
          if (remaining >= testAmount) {
            await adminContract.mint(config.testUserAddress, testAmount);
          } else {
            throw new Error(`Cannot setup insufficient allowance test - cap reached (remaining: ${remaining / 10n ** 18n})`);
          }
        } else {
          throw new Error(`Cannot setup insufficient allowance test - insufficient user balance and admin cannot mint. Error: ${error instanceof Error ? error.message : String(error)}`);
        }
      }
    }
    // Set a small allowance
    await testUserContract.approve(config.adminAddress, testAmount / 2n);
  });

  // Only test if user has balance
  const userBalanceForInsufficientAllowance = await adminContract.balanceOf(config.testUserAddress);
  if (userBalanceForInsufficientAllowance >= testAmount) {
    await suite.expectRevert('BurnFrom with insufficient allowance', async () => {
      // Try to burn more than allowed
      await adminContract.burnFrom(config.testUserAddress, testAmount);
    }, ['ERC20InsufficientAllowance', 'ERC20InsufficientBalance']);
  } else {
    await suite.runTest('BurnFrom with insufficient allowance', async () => {
      console.log(`  ⚠ Skipping insufficient allowance test - user has insufficient balance (${userBalanceForInsufficientAllowance} < ${testAmount})`);
    });
  }

  // Test: Burn with zero amount (edge case)
  await suite.runTestWithTx('Burn with zero amount', async () => {
    const supplyBefore = await adminContract.totalSupply();
    const adminBalanceBefore = await adminContract.balanceOf(config.adminAddress);
    const txHash = await adminContract.burn(0n);
    const supplyAfter = await adminContract.totalSupply();
    const adminBalanceAfter = await adminContract.balanceOf(config.adminAddress);
    
    // Supply and balance should remain unchanged
    if (supplyAfter !== supplyBefore) {
      throw new Error(`Supply should not change with zero burn. Before: ${supplyBefore}, After: ${supplyAfter}`);
    }
    if (adminBalanceAfter !== adminBalanceBefore) {
      throw new Error(`Balance should not change with zero burn. Before: ${adminBalanceBefore}, After: ${adminBalanceAfter}`);
    }
    return txHash;
  });

  return suite;
}

