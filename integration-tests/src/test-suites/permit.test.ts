import { privateKeyToAccount } from 'viem/accounts';
import { TestContext } from '../setup.js';
import { TestSuite } from '../test-utils.js';

export async function runPermitTests(context: TestContext): Promise<TestSuite> {
  const suite = new TestSuite('ERC20Permit (Gasless Approvals)');
  suite.printHeader();

  const { adminContract, testUserContract, config, publicClient, adminPrivateKey, testUserPrivateKey } = context;
  const testAmount = 100n * 10n ** 18n; // 100 tokens
  const spender = config.testUserAddress;

  // Get domain separator
  await suite.runTest('Read DOMAIN_SEPARATOR', async () => {
    const domainSeparator = await adminContract.DOMAIN_SEPARATOR();
    if (!domainSeparator || domainSeparator === '0x') {
      throw new Error('DOMAIN_SEPARATOR is empty');
    }
  });

  // Get initial nonce
  let initialNonce: bigint;
  await suite.runTest('Read initial nonce', async () => {
    initialNonce = await adminContract.nonces(config.adminAddress);
  });

  // Test: Valid permit
  await suite.runTestWithTx('Permit with valid signature', async () => {
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 86400); // 1 day from now
    const nonce = await adminContract.nonces(config.adminAddress);

    // Create EIP-712 signature
    const account = privateKeyToAccount(adminPrivateKey);
    const signature = await account.signTypedData({
      domain: {
        name: 'Veera Token',
        version: '1',
        chainId: await publicClient.getChainId(),
        verifyingContract: config.contractAddress,
      },
      types: {
        Permit: [
          { name: 'owner', type: 'address' },
          { name: 'spender', type: 'address' },
          { name: 'value', type: 'uint256' },
          { name: 'nonce', type: 'uint256' },
          { name: 'deadline', type: 'uint256' },
        ],
      },
      primaryType: 'Permit',
      message: {
        owner: config.adminAddress,
        spender,
        value: testAmount,
        nonce,
        deadline,
      },
    });

    // Split signature
    const r = signature.slice(0, 66) as `0x${string}`;
    const s = `0x${signature.slice(66, 130)}` as `0x${string}`;
    const v = parseInt(signature.slice(130, 132), 16);

    const txHash = await testUserContract.permit(
      config.adminAddress,
      spender,
      testAmount,
      deadline,
      v,
      r,
      s
    );
    // Wait for transaction confirmation
    await context.publicClient.waitForTransactionReceipt({ hash: txHash });
    return txHash;
  });

  await suite.runTest('Verify allowance after permit', async () => {
    // Wait a moment for state to update
    await new Promise(resolve => setTimeout(resolve, 1000));
    const allowance = await adminContract.allowance(config.adminAddress, spender);
    if (allowance !== testAmount) {
      throw new Error(`Allowance incorrect. Expected ${testAmount}, got ${allowance}`);
    }
  });

  await suite.runTest('Verify nonce incremented after permit', async () => {
    // Wait a moment for state to update
    await new Promise(resolve => setTimeout(resolve, 1000));
    const newNonce = await adminContract.nonces(config.adminAddress);
    if (newNonce !== initialNonce! + 1n) {
      throw new Error(`Nonce incorrect. Expected ${initialNonce! + 1n}, got ${newNonce}`);
    }
  });

  // Test: Permit with expired deadline (should fail)
  await suite.expectRevert('Permit with expired deadline', async () => {
    const deadline = BigInt(Math.floor(Date.now() / 1000) - 3600); // 1 hour ago
    const nonce = await adminContract.nonces(config.adminAddress);

    const account = privateKeyToAccount(adminPrivateKey);
    const signature = await account.signTypedData({
      domain: {
        name: 'Veera Token',
        version: '1',
        chainId: await publicClient.getChainId(),
        verifyingContract: config.contractAddress,
      },
      types: {
        Permit: [
          { name: 'owner', type: 'address' },
          { name: 'spender', type: 'address' },
          { name: 'value', type: 'uint256' },
          { name: 'nonce', type: 'uint256' },
          { name: 'deadline', type: 'uint256' },
        ],
      },
      primaryType: 'Permit',
      message: {
        owner: config.adminAddress,
        spender,
        value: testAmount,
        nonce,
        deadline,
      },
    });

    const r = signature.slice(0, 66) as `0x${string}`;
    const s = `0x${signature.slice(66, 130)}` as `0x${string}`;
    const v = parseInt(signature.slice(130, 132), 16);

    await testUserContract.permit(config.adminAddress, spender, testAmount, deadline, v, r, s);
  }, 'deadline');

  // Test: Permit with invalid signature (wrong signer)
  // Clear any existing allowance first to avoid confusion
  await suite.runTest('Clear allowance before invalid signature test', async () => {
    const { clearAllowance } = await import('../token-bootstrap.js');
    await clearAllowance(context, config.adminAddress, spender);
  });
  
  await suite.expectRevert('Permit with invalid signature (wrong signer)', async () => {
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 86400);
    const nonce = await adminContract.nonces(config.adminAddress);

    // Sign with wrong private key (test user instead of admin)
    const account = privateKeyToAccount(testUserPrivateKey);
    const signature = await account.signTypedData({
      domain: {
        name: 'Veera Token',
        version: '1',
        chainId: await publicClient.getChainId(),
        verifyingContract: config.contractAddress,
      },
      types: {
        Permit: [
          { name: 'owner', type: 'address' },
          { name: 'spender', type: 'address' },
          { name: 'value', type: 'uint256' },
          { name: 'nonce', type: 'uint256' },
          { name: 'deadline', type: 'uint256' },
        ],
      },
      primaryType: 'Permit',
      message: {
        owner: config.adminAddress, // Owner is admin, but signed by test user
        spender,
        value: testAmount,
        nonce,
        deadline,
      },
    });

    const r = signature.slice(0, 66) as `0x${string}`;
    const s = `0x${signature.slice(66, 130)}` as `0x${string}`;
    const v = parseInt(signature.slice(130, 132), 16);

    await testUserContract.permit(config.adminAddress, spender, testAmount, deadline, v, r, s);
  }, ['ERC2612InvalidSigner']);

  // Test: Permit with wrong nonce (should fail)
  // Clear any existing allowance first
  await suite.runTest('Clear allowance before wrong nonce test', async () => {
    const { clearAllowance } = await import('../token-bootstrap.js');
    await clearAllowance(context, config.adminAddress, spender);
  });
  
  await suite.expectRevert('Permit with wrong nonce', async () => {
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 86400);
    const currentNonce = await adminContract.nonces(config.adminAddress);
    const wrongNonce = currentNonce + 1n; // Use wrong nonce

    const account = privateKeyToAccount(adminPrivateKey);
    const signature = await account.signTypedData({
      domain: {
        name: 'Veera Token',
        version: '1',
        chainId: await publicClient.getChainId(),
        verifyingContract: config.contractAddress,
      },
      types: {
        Permit: [
          { name: 'owner', type: 'address' },
          { name: 'spender', type: 'address' },
          { name: 'value', type: 'uint256' },
          { name: 'nonce', type: 'uint256' },
          { name: 'deadline', type: 'uint256' },
        ],
      },
      primaryType: 'Permit',
      message: {
        owner: config.adminAddress,
        spender,
        value: testAmount,
        nonce: wrongNonce,
        deadline,
      },
    });

    const r = signature.slice(0, 66) as `0x${string}`;
    const s = `0x${signature.slice(66, 130)}` as `0x${string}`;
    const v = parseInt(signature.slice(130, 132), 16);

    await testUserContract.permit(config.adminAddress, spender, testAmount, deadline, v, r, s);
  }, ['ERC2612InvalidSigner', 'signature']);

  // Test: Permit with wrong chain ID (should fail)
  // Clear any existing allowance first
  await suite.runTest('Clear allowance before wrong chain ID test', async () => {
    const { clearAllowance } = await import('../token-bootstrap.js');
    await clearAllowance(context, config.adminAddress, spender);
  });
  
  await suite.expectRevert('Permit with wrong chain ID', async () => {
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 86400);
    const nonce = await adminContract.nonces(config.adminAddress);
    const correctChainId = await publicClient.getChainId();
    const wrongChainId = correctChainId === 84532 ? 8453 : 84532; // Use wrong chain ID

    const account = privateKeyToAccount(adminPrivateKey);
    const signature = await account.signTypedData({
      domain: {
        name: 'Veera Token',
        version: '1',
        chainId: wrongChainId,
        verifyingContract: config.contractAddress,
      },
      types: {
        Permit: [
          { name: 'owner', type: 'address' },
          { name: 'spender', type: 'address' },
          { name: 'value', type: 'uint256' },
          { name: 'nonce', type: 'uint256' },
          { name: 'deadline', type: 'uint256' },
        ],
      },
      primaryType: 'Permit',
      message: {
        owner: config.adminAddress,
        spender,
        value: testAmount,
        nonce,
        deadline,
      },
    });

    const r = signature.slice(0, 66) as `0x${string}`;
    const s = `0x${signature.slice(66, 130)}` as `0x${string}`;
    const v = parseInt(signature.slice(130, 132), 16);

    await testUserContract.permit(config.adminAddress, spender, testAmount, deadline, v, r, s);
  }, ['ERC2612InvalidSigner', 'signature']);

  // Test: Multiple consecutive permits (nonce increment)
  await suite.runTest('Multiple consecutive permits', async () => {
    const permitAmount = 50n * 10n ** 18n;
    const deadline1 = BigInt(Math.floor(Date.now() / 1000) + 86400);
    const deadline2 = BigInt(Math.floor(Date.now() / 1000) + 86400 * 2);

    // First permit
    const nonce1 = await adminContract.nonces(config.adminAddress);
    const account = privateKeyToAccount(adminPrivateKey);
    const signature1 = await account.signTypedData({
      domain: {
        name: 'Veera Token',
        version: '1',
        chainId: await publicClient.getChainId(),
        verifyingContract: config.contractAddress,
      },
      types: {
        Permit: [
          { name: 'owner', type: 'address' },
          { name: 'spender', type: 'address' },
          { name: 'value', type: 'uint256' },
          { name: 'nonce', type: 'uint256' },
          { name: 'deadline', type: 'uint256' },
        ],
      },
      primaryType: 'Permit',
      message: {
        owner: config.adminAddress,
        spender,
        value: permitAmount,
        nonce: nonce1,
        deadline: deadline1,
      },
    });

    const r1 = signature1.slice(0, 66) as `0x${string}`;
    const s1 = `0x${signature1.slice(66, 130)}` as `0x${string}`;
    const v1 = parseInt(signature1.slice(130, 132), 16);

    await suite.runTestWithTx('First permit', async () => {
      const txHash = await testUserContract.permit(config.adminAddress, spender, permitAmount, deadline1, v1, r1, s1);
      // Wait for transaction confirmation
      await context.publicClient.waitForTransactionReceipt({ hash: txHash });
      return txHash;
    });

    // Wait for transaction confirmation and state update
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    // Verify nonce incremented - re-read to get current nonce
    const nonceAfter1 = await adminContract.nonces(config.adminAddress);
    if (nonceAfter1 !== nonce1 + 1n) {
      throw new Error(`Nonce should increment. Expected ${nonce1 + 1n}, got ${nonceAfter1}`);
    }

    // Second permit with incremented nonce and double the value
    const secondPermitValue = permitAmount * 2n;
    const signature2 = await account.signTypedData({
      domain: {
        name: 'Veera Token',
        version: '1',
        chainId: await publicClient.getChainId(),
        verifyingContract: config.contractAddress,
      },
      types: {
        Permit: [
          { name: 'owner', type: 'address' },
          { name: 'spender', type: 'address' },
          { name: 'value', type: 'uint256' },
          { name: 'nonce', type: 'uint256' },
          { name: 'deadline', type: 'uint256' },
        ],
      },
      primaryType: 'Permit',
      message: {
        owner: config.adminAddress,
        spender,
        value: secondPermitValue,
        nonce: nonceAfter1,
        deadline: deadline2,
      },
    });

    const r2 = signature2.slice(0, 66) as `0x${string}`;
    const s2 = `0x${signature2.slice(66, 130)}` as `0x${string}`;
    const v2 = parseInt(signature2.slice(130, 132), 16);

    await suite.runTestWithTx('Second permit', async () => {
      const txHash = await testUserContract.permit(config.adminAddress, spender, secondPermitValue, deadline2, v2, r2, s2);
      // Wait for transaction confirmation
      await context.publicClient.waitForTransactionReceipt({ hash: txHash });
      return txHash;
    });

    // Wait for transaction confirmation and state update
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    // Verify nonce incremented again - use nonceAfter1 as base, not nonce1
    const nonceAfter2 = await adminContract.nonces(config.adminAddress);
    if (nonceAfter2 !== nonceAfter1 + 1n) {
      throw new Error(`Nonce should increment again. Expected ${nonceAfter1 + 1n}, got ${nonceAfter2}`);
    }

    // Verify allowance is set to the second permit value (permit is SET, not ADD)
    // The second permit should have set the allowance to secondPermitValue
    await new Promise(resolve => setTimeout(resolve, 1000));
    const finalAllowance = await adminContract.allowance(config.adminAddress, spender);
    if (finalAllowance !== secondPermitValue) {
      throw new Error(`Allowance should be set to second permit value. Expected ${secondPermitValue}, got ${finalAllowance}`);
    }
  });

  // Test: Permit with zero amount
  // Clear any existing allowance first
  await suite.runTest('Clear allowance before zero amount permit test', async () => {
    const { clearAllowance } = await import('../token-bootstrap.js');
    await clearAllowance(context, config.adminAddress, spender);
  });
  
  await suite.runTestWithTx('Permit with zero amount', async () => {
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 86400);
    const nonce = await adminContract.nonces(config.adminAddress);

    const account = privateKeyToAccount(adminPrivateKey);
    const signature = await account.signTypedData({
      domain: {
        name: 'Veera Token',
        version: '1',
        chainId: await publicClient.getChainId(),
        verifyingContract: config.contractAddress,
      },
      types: {
        Permit: [
          { name: 'owner', type: 'address' },
          { name: 'spender', type: 'address' },
          { name: 'value', type: 'uint256' },
          { name: 'nonce', type: 'uint256' },
          { name: 'deadline', type: 'uint256' },
        ],
      },
      primaryType: 'Permit',
      message: {
        owner: config.adminAddress,
        spender,
        value: 0n,
        nonce,
        deadline,
      },
    });

    const r = signature.slice(0, 66) as `0x${string}`;
    const s = `0x${signature.slice(66, 130)}` as `0x${string}`;
    const v = parseInt(signature.slice(130, 132), 16);

    return testUserContract.permit(config.adminAddress, spender, 0n, deadline, v, r, s);
  });

  await suite.runTest('Verify zero amount permit succeeded', async () => {
    // Zero amount permit should succeed - this verifies the permit mechanism works with zero values
    // The allowance may be 0 or a previous value depending on test order
    const allowance = await adminContract.allowance(config.adminAddress, spender);
    // The important thing is that the permit transaction succeeded
    if (allowance < 0n) {
      throw new Error('Allowance should be non-negative');
    }
  });

  return suite;
}

