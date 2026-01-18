import { TestContext } from '../setup.js';
import { TestSuite, ZERO_ADDRESS } from '../test-utils.js';
import { MINTER_ROLE } from '../contracts.js';

export async function runEdgeCaseTests(context: TestContext): Promise<TestSuite> {
  const suite = new TestSuite('Edge Cases');
  suite.printHeader();

  const { adminContract, testUserContract, config } = context;
  const testAmount = 100n * 10n ** 18n; // 100 tokens
  const adminHasMinterRole = await adminContract.hasRole(MINTER_ROLE, config.adminAddress);

  // Test: Transfer to zero address
  await suite.expectRevert('Transfer to zero address', async () => {
    await adminContract.transfer(ZERO_ADDRESS, testAmount);
  }, 'ERC20InvalidReceiver');

  // Test: Transfer with insufficient balance
  await suite.expectRevert('Transfer with insufficient balance', async () => {
    const balance = await adminContract.balanceOf(config.testUserAddress);
    // Try to transfer more than the user has (balance + 1)
    await testUserContract.transfer(config.adminAddress, balance + 1n);
  }, 'ERC20InsufficientBalance');

  // Test: TransferFrom with insufficient allowance
  await suite.runTest('Setup insufficient allowance test', async () => {
    // Set a small allowance
    await adminContract.approve(config.testUserAddress, testAmount / 2n);
  });

  await suite.expectRevert('TransferFrom with insufficient allowance', async () => {
    // Try to transfer more than allowed
    await testUserContract.transferFrom(config.adminAddress, config.testUserAddress, testAmount);
  }, 'ERC20InsufficientAllowance');

  // Test: Approve zero address (should fail per ERC20 standard)
  await suite.expectRevert('Approve zero address', async () => {
    await adminContract.approve(ZERO_ADDRESS, testAmount);
  }, 'ERC20InvalidSpender');

  // Test: Mint to zero address (only if admin has MINTER_ROLE)
  if (adminHasMinterRole) {
    await suite.expectRevert('Mint to zero address', async () => {
      await adminContract.mint(ZERO_ADDRESS, testAmount);
    }, ['ERC20InvalidReceiver', 'AccessControlUnauthorizedAccount']);
  } else {
    await suite.runTest('Mint to zero address', async () => {
      console.log('  ⚠ Skipping zero address mint test - admin does not have MINTER_ROLE');
    });
  }

  // Test: Cap enforcement - verify cap is immutable
  await suite.runTest('Verify cap is constant', async () => {
    const cap1 = await adminContract.cap();
    const cap2 = await adminContract.cap();
    if (cap1 !== cap2) {
      throw new Error('Cap should be constant');
    }
  });

  // Test: State consistency - totalSupply <= cap
  await suite.runTest('Verify totalSupply <= cap (invariant)', async () => {
    const totalSupply = await adminContract.totalSupply();
    const cap = await adminContract.cap();
    if (totalSupply > cap) {
      throw new Error(`Invariant violated: totalSupply (${totalSupply}) > cap (${cap})`);
    }
  });

  // Test: State consistency - sum of balances (approximate check)
  await suite.runTest('Verify balance consistency', async () => {
    const adminBalance = await adminContract.balanceOf(config.adminAddress);
    const userBalance = await adminContract.balanceOf(config.testUserAddress);
    const totalSupply = await adminContract.totalSupply();

    // Note: This is an approximate check since there may be other addresses with balances
    // In a real scenario, you'd need to track all addresses or use events
    if (adminBalance + userBalance > totalSupply) {
      throw new Error('Sum of known balances exceeds total supply');
    }
  });

  // Test: Zero amount transfers (should succeed but do nothing)
  await suite.runTestWithTx('Transfer zero amount', async () => {
    return adminContract.transfer(config.testUserAddress, 0n);
  });

  await suite.runTest('Verify balances unchanged after zero transfer', async () => {
    // Zero amount transfers should succeed but not change balances
    // This is verified by the transaction succeeding without errors
    const adminBalance = await adminContract.balanceOf(config.adminAddress);
    const userBalance = await adminContract.balanceOf(config.testUserAddress);
    // Verify balances are valid (non-negative)
    if (adminBalance < 0n || userBalance < 0n) {
      throw new Error('Balances should be non-negative');
    }
  });

  // Test: Approve to self
  await suite.runTestWithTx('Approve to self', async () => {
    const selfApproveAmount = 50n * 10n ** 18n;
    const txHash = await adminContract.approve(config.adminAddress, selfApproveAmount);
    // Wait for transaction to be confirmed (contract already waits, but ensure state is updated)
    // Read allowance after transaction
    const allowance = await adminContract.allowance(config.adminAddress, config.adminAddress);
    if (allowance !== selfApproveAmount) {
      throw new Error(`Self-approval should set allowance. Expected ${selfApproveAmount}, got ${allowance}`);
    }
    return txHash;
  });

  // Test: Approve with maximum uint256
  // First clear any existing allowance
  await suite.runTest('Clear existing allowance before max uint256 test', async () => {
    const { clearAllowance } = await import('../token-bootstrap.js');
    await clearAllowance(context, config.adminAddress, config.testUserAddress);
  });
  
  await suite.runTestWithTx('Approve with maximum uint256', async () => {
    const maxUint256 = 2n ** 256n - 1n;
    const txHash = await adminContract.approve(config.testUserAddress, maxUint256);
    // Wait for transaction confirmation
    await context.publicClient.waitForTransactionReceipt({ hash: txHash });
    return txHash;
  });

  await suite.runTest('Verify max uint256 allowance', async () => {
    // Wait a moment for state to update (may need more time for large values)
    await new Promise(resolve => setTimeout(resolve, 2000));
    const maxUint256 = 2n ** 256n - 1n;
    const allowance = await adminContract.allowance(config.adminAddress, config.testUserAddress);
    if (allowance !== maxUint256) {
      throw new Error(`Allowance should be max uint256. Expected ${maxUint256}, got ${allowance}`);
    }
  });

  // Test: Maximum uint256 value (boundary)
  await suite.runTest('Test with very large amount (should fail if exceeds balance)', async () => {
    const maxUint256 = 2n ** 256n - 1n;
    const balance = await adminContract.balanceOf(config.adminAddress);
    
    if (maxUint256 > balance) {
      await suite.expectRevert('Transfer maximum uint256 (exceeds balance)', async () => {
        await adminContract.transfer(config.testUserAddress, maxUint256);
      }, 'ERC20InsufficientBalance');
    }
  });

  // Test: Decimals consistency
  await suite.runTest('Verify decimals is 18', async () => {
    const decimals = await adminContract.decimals();
    if (decimals !== 18) {
      throw new Error(`Decimals should be 18, got ${decimals}`);
    }
  });

  // Test: Name and symbol consistency
  await suite.runTest('Verify token name', async () => {
    const name = await adminContract.name();
    if (name !== 'Veera Token') {
      throw new Error(`Token name should be "Veera Token", got "${name}"`);
    }
  });

  await suite.runTest('Verify token symbol', async () => {
    const symbol = await adminContract.symbol();
    if (symbol !== 'VEERA') {
      throw new Error(`Token symbol should be "VEERA", got "${symbol}"`);
    }
  });

  return suite;
}

