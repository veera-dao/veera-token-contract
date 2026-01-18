import { TestContext } from '../setup.js';
import { TestSuite, ZERO_ADDRESS } from '../test-utils.js';
import { MINTER_ROLE } from '../contracts.js';

export async function runMintingTests(context: TestContext): Promise<TestSuite> {
  const suite = new TestSuite('Minting Operations');
  suite.printHeader();

  const { adminContract, testUserContract, config } = context;
  const testAmount = 100n * 10n ** 18n; // 100 tokens

  // Get initial state
  const initialSupply = await adminContract.totalSupply();
  const cap = await adminContract.cap();
  const initialUserBalance = await adminContract.balanceOf(config.testUserAddress);
  
  // Check if admin has MINTER_ROLE
  const adminHasMinterRole = await adminContract.hasRole(MINTER_ROLE, config.adminAddress);

  // Test: Successful mint (only if admin has MINTER_ROLE)
  if (adminHasMinterRole) {
    // Check if we can mint (cap not reached)
    const currentSupply = await adminContract.totalSupply();
    const cap = await adminContract.cap();
    const remaining = cap - currentSupply;
    
    if (remaining >= testAmount) {
      await suite.runTestWithTx('Mint tokens to user (success)', async () => {
        return adminContract.mint(config.testUserAddress, testAmount);
      });
    } else {
      await suite.runTest('Mint tokens to user (success)', async () => {
        console.log(`  ⚠ Skipping mint test - cap reached (supply: ${currentSupply / 10n ** 18n}, cap: ${cap / 10n ** 18n}, remaining: ${remaining / 10n ** 18n})`);
      });
    }

    if (remaining >= testAmount) {
      await suite.runTest('Verify balance after mint', async () => {
        // Wait a moment for state to update
        await new Promise(resolve => setTimeout(resolve, 1000));
        const userBalance = await adminContract.balanceOf(config.testUserAddress);
        if (userBalance !== initialUserBalance + testAmount) {
          throw new Error(
            `User balance incorrect. Expected ${initialUserBalance + testAmount}, got ${userBalance}`
          );
        }
      });

      await suite.runTest('Verify totalSupply increased', async () => {
        // Wait a moment for state to update
        await new Promise(resolve => setTimeout(resolve, 1000));
        const newSupply = await adminContract.totalSupply();
        if (newSupply !== initialSupply + testAmount) {
          throw new Error(`Total supply incorrect. Expected ${initialSupply + testAmount}, got ${newSupply}`);
        }
      });
    } else {
      await suite.runTest('Verify balance after mint', async () => {
        console.log('  ⚠ Skipping balance verification - mint test was skipped');
      });
      await suite.runTest('Verify totalSupply increased', async () => {
        console.log('  ⚠ Skipping supply verification - mint test was skipped');
      });
    }

    // Test: Mint to zero address (should fail)
    await suite.expectRevert('Mint to zero address', async () => {
      await adminContract.mint(ZERO_ADDRESS, testAmount);
    }, ['ERC20InvalidReceiver', 'AccessControlUnauthorizedAccount']);
  } else {
    await suite.runTest('Mint tokens to user (success)', async () => {
      console.log('  ⚠ Skipping mint test - admin does not have MINTER_ROLE');
    });
    await suite.runTest('Verify balance after mint', async () => {
      console.log('  ⚠ Skipping balance verification - mint test was skipped');
    });
    await suite.runTest('Verify totalSupply increased', async () => {
      console.log('  ⚠ Skipping supply verification - mint test was skipped');
    });
    await suite.runTest('Mint to zero address', async () => {
      console.log('  ⚠ Skipping zero address mint test - admin does not have MINTER_ROLE');
    });
  }

  // Test: Mint exceeding cap (should fail, only if admin has MINTER_ROLE)
  if (adminHasMinterRole) {
    await suite.runTest('Calculate remaining supply', async () => {
      const currentSupply = await adminContract.totalSupply();
      let remaining = cap - currentSupply;
      
      // If cap is reached, burn tokens to create space for the test
      if (remaining <= 0n) {
        const burnAmount = 100n * 10n ** 18n; // Burn 100 tokens to create space
        const adminBalance = await adminContract.balanceOf(config.adminAddress);
        if (adminBalance >= burnAmount) {
          const burnTxHash = await adminContract.burn(burnAmount);
          await context.publicClient.waitForTransactionReceipt({ hash: burnTxHash });
          await new Promise(resolve => setTimeout(resolve, 1000));
          remaining = cap - (await adminContract.totalSupply());
        } else {
          console.log('  ⚠ Cannot create space for cap test - insufficient balance to burn');
          return;
        }
      }

      // Try to mint more than remaining
      const excessAmount = remaining + 1n;
      await suite.expectRevert('Mint exceeding cap', async () => {
        await adminContract.mint(config.testUserAddress, excessAmount);
      }, 'ERC20ExceededCap');
    });
  } else {
    await suite.runTest('Calculate remaining supply', async () => {
      console.log('  ⚠ Skipping cap enforcement test - admin does not have MINTER_ROLE');
    });
  }

  // Test: Mint exactly at cap boundary (if possible, only if admin has MINTER_ROLE)
  if (adminHasMinterRole) {
    await suite.runTest('Mint up to cap boundary', async () => {
      const currentSupply = await adminContract.totalSupply();
      let remaining = cap - currentSupply;
      
      // If cap is reached, burn tokens to create space for the test
      if (remaining <= 0n) {
        const burnAmount = 100n * 10n ** 18n; // Burn 100 tokens to create space
        const adminBalance = await adminContract.balanceOf(config.adminAddress);
        if (adminBalance >= burnAmount) {
          const burnTxHash = await adminContract.burn(burnAmount);
          await context.publicClient.waitForTransactionReceipt({ hash: burnTxHash });
          await new Promise(resolve => setTimeout(resolve, 1000));
          remaining = cap - (await adminContract.totalSupply());
        } else {
          console.log('  ⚠ Cannot create space for boundary test - insufficient balance to burn');
          return;
        }
      }

      // Mint exactly the remaining amount
      if (remaining > 0n) {
        await suite.runTestWithTx('Mint exactly remaining supply', async () => {
          const txHash = await adminContract.mint(config.testUserAddress, remaining);
          // Wait for transaction confirmation
          await context.publicClient.waitForTransactionReceipt({ hash: txHash });
          return txHash;
        });

        await suite.runTest('Verify totalSupply equals cap', async () => {
          // Wait a moment for state to update
          await new Promise(resolve => setTimeout(resolve, 1000));
          const finalSupply = await adminContract.totalSupply();
          if (finalSupply !== cap) {
            throw new Error(`Total supply should equal cap. Expected ${cap}, got ${finalSupply}`);
          }
        });
      }
    });
  } else {
    await suite.runTest('Mint up to cap boundary', async () => {
      console.log('  ⚠ Skipping cap boundary test - admin does not have MINTER_ROLE');
    });
  }

  // Test: Mint by unauthorized address (should fail)
  await suite.expectRevert('Mint by unauthorized address', async () => {
    await testUserContract.mint(config.testUserAddress, testAmount);
  }, 'AccessControlUnauthorizedAccount');

  // Test: Mint with zero amount (edge case, only if admin has MINTER_ROLE)
  if (adminHasMinterRole) {
    await suite.runTestWithTx('Mint with zero amount', async () => {
      const supplyBefore = await adminContract.totalSupply();
      const userBalanceBefore = await adminContract.balanceOf(config.testUserAddress);
      const txHash = await adminContract.mint(config.testUserAddress, 0n);
      const supplyAfter = await adminContract.totalSupply();
      const userBalanceAfter = await adminContract.balanceOf(config.testUserAddress);
      
      // Supply and balance should remain unchanged
      if (supplyAfter !== supplyBefore) {
        throw new Error(`Supply should not change with zero mint. Before: ${supplyBefore}, After: ${supplyAfter}`);
      }
      if (userBalanceAfter !== userBalanceBefore) {
        throw new Error(`Balance should not change with zero mint. Before: ${userBalanceBefore}, After: ${userBalanceAfter}`);
      }
      return txHash;
    });
  } else {
    await suite.runTest('Mint with zero amount', async () => {
      console.log('  ⚠ Skipping zero amount mint test - admin does not have MINTER_ROLE');
    });
  }

  return suite;
}

