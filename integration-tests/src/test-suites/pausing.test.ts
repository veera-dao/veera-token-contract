import { TestContext } from '../setup.js';
import { TestSuite } from '../test-utils.js';
import { PAUSER_ROLE, MINTER_ROLE } from '../contracts.js';
import { ensureAccountHasTokens } from '../token-bootstrap.js';

export async function runPausingTests(context: TestContext): Promise<TestSuite> {
  const suite = new TestSuite('Pausing Operations');
  suite.printHeader();

  const { adminContract, testUserContract, config } = context;
  const testAmount = 10n * 10n ** 18n; // 10 tokens

  // Check if admin has PAUSER_ROLE
  const adminHasPauserRole = await adminContract.hasRole(PAUSER_ROLE, config.adminAddress);
  const adminHasMinterRole = await adminContract.hasRole(MINTER_ROLE, config.adminAddress);

  // Get initial pause state
  const initiallyPaused = await adminContract.paused();

  // If admin doesn't have PAUSER_ROLE, skip pause/unpause tests
  if (!adminHasPauserRole) {
    await suite.runTest('Pause contract', async () => {
      console.log('  ⚠ Skipping pause test - admin does not have PAUSER_ROLE');
    });
    await suite.runTest('Verify contract is paused', async () => {
      console.log('  ⚠ Skipping pause verification - pause test was skipped');
    });
    await suite.runTest('Transfer blocked when paused', async () => {
      console.log('  ⚠ Skipping paused transfer test - admin does not have PAUSER_ROLE');
    });
    await suite.runTest('Setup TransferFrom test - ensure allowance exists', async () => {
      console.log('  ⚠ Skipping TransferFrom setup - admin does not have PAUSER_ROLE');
    });
    await suite.runTest('TransferFrom blocked when paused', async () => {
      console.log('  ⚠ Skipping paused TransferFrom test - admin does not have PAUSER_ROLE');
    });
    await suite.runTest('Mint blocked when paused', async () => {
      console.log('  ⚠ Skipping paused mint test - admin does not have PAUSER_ROLE');
    });
    await suite.runTest('Burn blocked when paused', async () => {
      console.log('  ⚠ Skipping paused burn test - admin does not have PAUSER_ROLE');
    });
    await suite.runTest('Unpause contract', async () => {
      console.log('  ⚠ Skipping unpause test - admin does not have PAUSER_ROLE');
    });
    await suite.runTest('Verify contract is unpaused', async () => {
      console.log('  ⚠ Skipping unpause verification - unpause test was skipped');
    });
    await suite.runTest('Transfer succeeds after unpause', async () => {
      console.log('  ⚠ Skipping post-unpause transfer test - admin does not have PAUSER_ROLE');
    });
    await suite.runTest('Mint succeeds after unpause', async () => {
      console.log('  ⚠ Skipping post-unpause mint test - admin does not have PAUSER_ROLE');
    });
    await suite.runTest('Burn succeeds after unpause', async () => {
      console.log('  ⚠ Skipping post-unpause burn test - admin does not have PAUSER_ROLE');
    });
    return suite;
  }

  // If already paused, unpause first
  if (initiallyPaused) {
    await suite.runTestWithTx('Unpause contract (was already paused)', async () => {
      const txHash = await adminContract.unpause();
      // Wait for transaction confirmation
      await context.publicClient.waitForTransactionReceipt({ hash: txHash });
      // Wait for state to update
      await new Promise(resolve => setTimeout(resolve, 1000));
      return txHash;
    });
  }

  // Test: Pause contract
  await suite.runTestWithTx('Pause contract', async () => {
    const txHash = await adminContract.pause();
    // Wait for transaction confirmation
    await context.publicClient.waitForTransactionReceipt({ hash: txHash });
    return txHash;
  });

  await suite.runTest('Verify contract is paused', async () => {
    // Wait a moment for state to update (may need more time for pause state)
    await new Promise(resolve => setTimeout(resolve, 2000));
    const isPaused = await adminContract.paused();
    if (!isPaused) {
      throw new Error('Contract should be paused');
    }
  });

  // Test: Transfer blocked when paused
  // Bootstrap tokens to admin if needed
  await ensureAccountHasTokens(context, config.adminAddress, testAmount);
  
  await suite.expectRevert('Transfer blocked when paused', async () => {
    await adminContract.transfer(config.testUserAddress, testAmount);
  }, 'EnforcedPause');

  // Test: TransferFrom blocked when paused
  // Note: We need to set up allowance before pausing, so we temporarily unpause
  await suite.runTest('Setup TransferFrom test - ensure allowance exists', async () => {
    // First, ensure we're unpaused to set allowance
    const isCurrentlyPaused = await adminContract.paused();
    if (isCurrentlyPaused) {
      // Unpause temporarily to set allowance
      const unpauseTxHash = await adminContract.unpause();
      await context.publicClient.waitForTransactionReceipt({ hash: unpauseTxHash });
      await new Promise(resolve => setTimeout(resolve, 2000));
    }
    // Set allowance (this will work whether paused or not, but transferFrom requires unpaused)
    const approveTxHash = await adminContract.approve(config.testUserAddress, testAmount);
    await context.publicClient.waitForTransactionReceipt({ hash: approveTxHash });
    await new Promise(resolve => setTimeout(resolve, 1000));
    // Now pause for the test
    const pauseTxHash = await adminContract.pause();
    await context.publicClient.waitForTransactionReceipt({ hash: pauseTxHash });
    await new Promise(resolve => setTimeout(resolve, 2000));
    // Verify we're actually paused
    const isPausedAfter = await adminContract.paused();
    if (!isPausedAfter) {
      throw new Error('Contract should be paused after setup');
    }
  });

  await suite.expectRevert('TransferFrom blocked when paused', async () => {
    // Verify we're paused - wait a bit for state to update
    await new Promise(resolve => setTimeout(resolve, 1000));
    const isPaused = await adminContract.paused();
    if (!isPaused) {
      throw new Error('Contract should be paused for this test');
    }
    await testUserContract.transferFrom(config.adminAddress, config.testUserAddress, testAmount);
  }, 'EnforcedPause');

  // Test: Mint blocked when paused (only if admin has MINTER_ROLE)
  if (adminHasMinterRole) {
    await suite.runTest('Mint blocked when paused', async () => {
      // Verify we're paused first
      await new Promise(resolve => setTimeout(resolve, 2000));
      const isPaused = await adminContract.paused();
      if (!isPaused) {
        throw new Error('Contract should be paused for this test');
      }
      // Check if we can mint (cap not reached) - if cap is reached, burn tokens to create space
      const currentSupply = await adminContract.totalSupply();
      const cap = await adminContract.cap();
      let remaining = cap - currentSupply;
      
      if (remaining < testAmount) {
        // Burn tokens to create space
        const burnAmount = testAmount - remaining + 10n * 10n ** 18n; // Burn a bit extra
        const adminBalance = await adminContract.balanceOf(config.adminAddress);
        if (adminBalance >= burnAmount) {
          const burnTxHash = await adminContract.burn(burnAmount);
          await context.publicClient.waitForTransactionReceipt({ hash: burnTxHash });
          await new Promise(resolve => setTimeout(resolve, 1000));
          remaining = cap - (await adminContract.totalSupply());
        }
      }
      
      if (remaining >= testAmount) {
        await suite.expectRevert('Mint blocked when paused', async () => {
          await adminContract.mint(config.testUserAddress, testAmount);
        }, 'EnforcedPause');
      } else {
        console.log(`  ⚠ Skipping paused mint test - cannot create space (remaining: ${remaining / 10n ** 18n})`);
      }
    });
  } else {
    await suite.runTest('Mint blocked when paused', async () => {
      console.log('  ⚠ Skipping paused mint test - admin does not have MINTER_ROLE');
    });
  }

  // Test: Burn blocked when paused
  // Bootstrap tokens to admin if needed
  await ensureAccountHasTokens(context, config.adminAddress, testAmount);
  
  await suite.expectRevert('Burn blocked when paused', async () => {
    // Verify we're paused first
    await new Promise(resolve => setTimeout(resolve, 1000));
    const isPausedForBurn = await adminContract.paused();
    if (!isPausedForBurn) {
      throw new Error('Contract should be paused for this test');
    }
    await adminContract.burn(testAmount);
  }, 'EnforcedPause');

  // Test: Unpause contract
  // Verify we're actually paused before trying to unpause
  await suite.runTest('Verify contract is paused before unpause', async () => {
    // Wait a moment for state to update (may need more time)
    await new Promise(resolve => setTimeout(resolve, 2000));
    const isPaused = await adminContract.paused();
    if (!isPaused) {
      throw new Error('Contract should be paused before unpause test');
    }
  });
  
  await suite.runTestWithTx('Unpause contract', async () => {
    const txHash = await adminContract.unpause();
    // Wait for transaction confirmation
    await context.publicClient.waitForTransactionReceipt({ hash: txHash });
    // Wait for state to update
    await new Promise(resolve => setTimeout(resolve, 2000));
    // Verify unpause actually succeeded
    const isPausedAfter = await adminContract.paused();
    if (isPausedAfter) {
      throw new Error('Contract should be unpaused after unpause transaction');
    }
    return txHash;
  });

  await suite.runTest('Verify contract is unpaused', async () => {
    // Wait a moment for state to update
    await new Promise(resolve => setTimeout(resolve, 1000));
    const isPaused = await adminContract.paused();
    if (isPaused) {
      throw new Error('Contract should be unpaused');
    }
  });

  // Test: Operations resume after unpause
  // Bootstrap tokens to admin if needed
  await ensureAccountHasTokens(context, config.adminAddress, testAmount);
  
  await suite.runTestWithTx('Transfer succeeds after unpause', async () => {
    return adminContract.transfer(config.testUserAddress, testAmount);
  });

  if (adminHasMinterRole) {
    // Check if we can mint (cap not reached)
    const currentSupply = await adminContract.totalSupply();
    const cap = await adminContract.cap();
    const remaining = cap - currentSupply;
    
    if (remaining >= testAmount) {
      await suite.runTestWithTx('Mint succeeds after unpause', async () => {
        return adminContract.mint(config.testUserAddress, testAmount);
      });
    } else {
      await suite.runTest('Mint succeeds after unpause', async () => {
        console.log(`  ⚠ Skipping post-unpause mint test - cap reached (remaining: ${remaining / 10n ** 18n})`);
      });
    }
  } else {
    await suite.runTest('Mint succeeds after unpause', async () => {
      console.log('  ⚠ Skipping post-unpause mint test - admin does not have MINTER_ROLE');
    });
  }

  await suite.runTestWithTx('Burn succeeds after unpause', async () => {
    const balance = await adminContract.balanceOf(config.adminAddress);
    if (balance >= testAmount) {
      return adminContract.burn(testAmount);
    }
    // Skip if insufficient balance - return undefined to indicate test was skipped
    return undefined;
  });

  // Test: Unauthorized pause (should fail)
  await suite.expectRevert('Pause by unauthorized address', async () => {
    await testUserContract.pause();
  }, 'AccessControlUnauthorizedAccount');

  // Test: Unauthorized unpause (should fail)
  await suite.expectRevert('Unpause by unauthorized address', async () => {
    // First pause as admin
    await adminContract.pause();
    // Then try to unpause as non-pauser
    await testUserContract.unpause();
  }, 'AccessControlUnauthorizedAccount');

  // Restore initial state (CRITICAL - ensures contract state is correct for subsequent tests)
  if (initiallyPaused) {
    await suite.runTestWithTx('Restore initial paused state', async () => {
      const isCurrentlyPaused = await adminContract.paused();
      if (!isCurrentlyPaused) {
        const txHash = await adminContract.pause();
        await context.publicClient.waitForTransactionReceipt({ hash: txHash });
        await new Promise(resolve => setTimeout(resolve, 2000));
        return txHash;
      }
      return undefined;
    });
  } else {
    // Ensure unpaused
    await suite.runTestWithTx('Unpause to restore initial state', async () => {
      const isPaused = await adminContract.paused();
      if (isPaused) {
        const txHash = await adminContract.unpause();
        await context.publicClient.waitForTransactionReceipt({ hash: txHash });
        await new Promise(resolve => setTimeout(resolve, 2000));
        return txHash;
      }
      return undefined;
    });
  }

  // Final verification that contract state matches initial state
  await suite.runTest('Final verification - contract state matches initial', async () => {
    await new Promise(resolve => setTimeout(resolve, 1000));
    const isPaused = await adminContract.paused();
    if (isPaused !== initiallyPaused) {
      throw new Error(`Contract pause state should match initial state. Expected ${initiallyPaused}, got ${isPaused}`);
    }
  });

  return suite;
}

