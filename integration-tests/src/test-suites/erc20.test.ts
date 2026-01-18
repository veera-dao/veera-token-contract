import { TestContext } from '../setup.js';
import { TestSuite } from '../test-utils.js';
import { ensureAccountHasTokens, clearAllowance } from '../token-bootstrap.js';

export async function runERC20Tests(context: TestContext): Promise<TestSuite> {
  const suite = new TestSuite('ERC20 Standard Operations');
  suite.printHeader();

  const { adminContract, testUserContract, config } = context;
  const testAmount = 100n * 10n ** 18n; // 100 tokens

  // Bootstrap tokens to admin if needed - NO SKIPPING
  await ensureAccountHasTokens(context, config.adminAddress, testAmount * 2n); // Need extra for transferFrom

  // Get initial balances (after bootstrap)
  const initialAdminBalance = await adminContract.balanceOf(config.adminAddress);
  const initialUserBalance = await adminContract.balanceOf(config.testUserAddress);

  // Test: Transfer tokens (admin should have tokens after bootstrap)
  await suite.runTestWithTx('Transfer tokens from admin to user', async () => {
    const txHash = await adminContract.transfer(config.testUserAddress, testAmount);
    // Wait for transaction confirmation (contract already waits, but ensure state is updated)
    await context.publicClient.waitForTransactionReceipt({ hash: txHash });
    return txHash;
  });

  await suite.runTest('Verify balance after transfer', async () => {
    // Wait a moment for state to update
    await new Promise(resolve => setTimeout(resolve, 1000));
    const adminBalance = await adminContract.balanceOf(config.adminAddress);
    const userBalance = await adminContract.balanceOf(config.testUserAddress);

    if (adminBalance !== initialAdminBalance - testAmount) {
      throw new Error(
        `Admin balance incorrect. Expected ${initialAdminBalance - testAmount}, got ${adminBalance}`
      );
    }
    if (userBalance !== initialUserBalance + testAmount) {
      throw new Error(
        `User balance incorrect. Expected ${initialUserBalance + testAmount}, got ${userBalance}`
      );
    }
  });

  // Test: Approve allowance
  // Clear any existing allowance first
  await clearAllowance(context, config.adminAddress, config.testUserAddress);
  
  await suite.runTestWithTx('Approve allowance for user', async () => {
    const txHash = await adminContract.approve(config.testUserAddress, testAmount);
    // Wait for transaction confirmation
    await context.publicClient.waitForTransactionReceipt({ hash: txHash });
    return txHash;
  });

  await suite.runTest('Verify allowance after approve', async () => {
    // Wait a moment for state to update
    await new Promise(resolve => setTimeout(resolve, 1000));
    const allowance = await adminContract.allowance(config.adminAddress, config.testUserAddress);
    if (allowance !== testAmount) {
      throw new Error(`Allowance incorrect. Expected ${testAmount}, got ${allowance}`);
    }
  });

  // Test: TransferFrom using allowance
  // Admin should have tokens after bootstrap, ensure we have enough for this test
  await ensureAccountHasTokens(context, config.adminAddress, testAmount);
  
  // Set allowance for transferFrom
  await clearAllowance(context, config.adminAddress, config.testUserAddress);
  // Wait for clearAllowance to complete
  await new Promise(resolve => setTimeout(resolve, 1000));
  
  const approveTxHash = await adminContract.approve(config.testUserAddress, testAmount);
  await context.publicClient.waitForTransactionReceipt({ hash: approveTxHash });
  // Wait a moment for state to update
  await new Promise(resolve => setTimeout(resolve, 2000));
  
  // Verify allowance is actually set before attempting transferFrom
  const allowanceBeforeTransfer = await adminContract.allowance(config.adminAddress, config.testUserAddress);
  if (allowanceBeforeTransfer !== testAmount) {
    throw new Error(`Allowance not set correctly before transferFrom. Expected ${testAmount}, got ${allowanceBeforeTransfer}`);
  }
  
  await suite.runTestWithTx('TransferFrom using allowance', async () => {
    const adminBalanceBefore = await adminContract.balanceOf(config.adminAddress);
    const txHash = await testUserContract.transferFrom(
      config.adminAddress,
      config.testUserAddress,
      testAmount / 2n
    );
    // Wait for transaction confirmation
    await context.publicClient.waitForTransactionReceipt({ hash: txHash });
    // Wait a moment for state to update
    await new Promise(resolve => setTimeout(resolve, 2000));
    const adminBalanceAfter = await adminContract.balanceOf(config.adminAddress);
    if (adminBalanceAfter !== adminBalanceBefore - testAmount / 2n) {
      throw new Error('Balance not updated correctly after transferFrom');
    }
    return txHash;
  });

  await suite.runTest('Verify allowance decreased after transferFrom', async () => {
    // Wait a moment for state to update
    await new Promise(resolve => setTimeout(resolve, 1000));
    const allowance = await adminContract.allowance(config.adminAddress, config.testUserAddress);
    const expectedAllowance = testAmount - testAmount / 2n;
    if (allowance !== expectedAllowance) {
      throw new Error(`Allowance incorrect. Expected ${expectedAllowance}, got ${allowance}`);
    }
  });

  // Test: Read token metadata
  await suite.runTest('Read token name', async () => {
    const name = await adminContract.name();
    if (name !== 'Veera Token') {
      throw new Error(`Token name incorrect. Expected "Veera Token", got "${name}"`);
    }
  });

  await suite.runTest('Read token symbol', async () => {
    const symbol = await adminContract.symbol();
    if (symbol !== 'VEERA') {
      throw new Error(`Token symbol incorrect. Expected "VEERA", got "${symbol}"`);
    }
  });

  await suite.runTest('Read token decimals', async () => {
    const decimals = await adminContract.decimals();
    if (decimals !== 18) {
      throw new Error(`Token decimals incorrect. Expected 18, got ${decimals}`);
    }
  });

  await suite.runTest('Read total supply', async () => {
    const totalSupply = await adminContract.totalSupply();
    if (totalSupply <= 0n) {
      throw new Error(`Total supply should be greater than 0, got ${totalSupply}`);
    }
  });

  // Test: Transfer to self (should succeed per ERC20)
  const selfTransferAmount = 10n * 10n ** 18n; // 10 tokens
  await ensureAccountHasTokens(context, config.adminAddress, selfTransferAmount);
  
  await suite.runTestWithTx('Transfer to self', async () => {
    const balanceBefore = await adminContract.balanceOf(config.adminAddress);
    const txHash = await adminContract.transfer(config.adminAddress, selfTransferAmount);
    const balanceAfter = await adminContract.balanceOf(config.adminAddress);
    // Balance should remain unchanged when transferring to self
    if (balanceAfter !== balanceBefore) {
      throw new Error(`Self-transfer should not change balance. Before: ${balanceBefore}, After: ${balanceAfter}`);
    }
    return txHash;
  });

  // Test: Approve reset behavior (approving same spender with different amount)
  // Clear any existing allowance first
  await clearAllowance(context, config.adminAddress, config.testUserAddress);
  
  await suite.runTestWithTx('Approve reset behavior - clear existing allowance', async () => {
    // Double-check allowance is cleared
    return adminContract.approve(config.testUserAddress, 0n);
  });

  await suite.runTestWithTx('Approve reset behavior - change allowance', async () => {
    const firstAmount = 50n * 10n ** 18n;
    const secondAmount = 75n * 10n ** 18n;
    
    // First approval
    const txHash1 = await adminContract.approve(config.testUserAddress, firstAmount);
    // Wait for transaction confirmation
    await context.publicClient.waitForTransactionReceipt({ hash: txHash1 });
    // Wait a moment for state to update
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // Verify first allowance
    const allowance = await adminContract.allowance(config.adminAddress, config.testUserAddress);
    if (allowance !== firstAmount) {
      throw new Error(`First allowance incorrect. Expected ${firstAmount}, got ${allowance}`);
    }
    
    // Second approval with different amount (should reset)
    const txHash2 = await adminContract.approve(config.testUserAddress, secondAmount);
    // Wait for transaction confirmation
    await context.publicClient.waitForTransactionReceipt({ hash: txHash2 });
    return txHash2;
  });

  await suite.runTest('Verify allowance reset after second approve', async () => {
    // Wait a moment for state to update
    await new Promise(resolve => setTimeout(resolve, 1000));
    const expectedAmount = 75n * 10n ** 18n;
    const allowance = await adminContract.allowance(config.adminAddress, config.testUserAddress);
    if (allowance !== expectedAmount) {
      throw new Error(`Allowance should be reset to ${expectedAmount}, got ${allowance}`);
    }
  });

  // Test: TransferFrom with zero amount
  await suite.runTestWithTx('TransferFrom with zero amount', async () => {
    // Ensure there's an allowance
    await clearAllowance(context, config.adminAddress, config.testUserAddress);
    await adminContract.approve(config.testUserAddress, testAmount);
    // Transfer zero amount - should succeed but not change balances
    const txHash = await testUserContract.transferFrom(
      config.adminAddress,
      config.testUserAddress,
      0n
    );
    // Transaction should succeed (balances remain unchanged)
    return txHash;
  });

  return suite;
}

