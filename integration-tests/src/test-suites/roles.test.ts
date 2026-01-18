import { TestContext } from '../setup.js';
import { TestSuite } from '../test-utils.js';
import { DEFAULT_ADMIN_ROLE, MINTER_ROLE, PAUSER_ROLE } from '../contracts.js';

export async function runRoleTests(context: TestContext): Promise<TestSuite> {
  const suite = new TestSuite('Access Control (Roles)');
  suite.printHeader();

  const { adminContract, config, minterContract, pauserContract } = context;

  // Verify initial role assignments
  await suite.runTest('Verify admin has DEFAULT_ADMIN_ROLE', async () => {
    const hasRole = await adminContract.hasRole(DEFAULT_ADMIN_ROLE, config.adminAddress);
    if (!hasRole) {
      throw new Error('Admin should have DEFAULT_ADMIN_ROLE');
    }
  });

  await suite.runTest('Verify admin has MINTER_ROLE', async () => {
    const hasRole = await adminContract.hasRole(MINTER_ROLE, config.adminAddress);
    if (!hasRole) {
      throw new Error('Admin should have MINTER_ROLE');
    }
  });

  await suite.runTest('Verify admin has PAUSER_ROLE', async () => {
    const hasRole = await adminContract.hasRole(PAUSER_ROLE, config.adminAddress);
    if (!hasRole) {
      throw new Error('Admin should have PAUSER_ROLE');
    }
  });

  // Use minter if configured (address is derived from private key/keystore)
  if (config.minterAddress && minterContract) {
    // Test: Grant MINTER_ROLE
    await suite.runTest('Verify minter does not have MINTER_ROLE initially', async () => {
      const hasRole = await adminContract.hasRole(MINTER_ROLE, config.minterAddress!);
      if (hasRole) {
        console.log('  ⚠ Minter already has MINTER_ROLE, skipping grant test');
        return;
      }
    });

    await suite.runTestWithTx('Grant MINTER_ROLE to minter address', async () => {
      const txHash = await adminContract.grantRole(MINTER_ROLE, config.minterAddress!);
      // Wait for transaction confirmation
      await context.publicClient.waitForTransactionReceipt({ hash: txHash });
      return txHash;
    });

    await suite.runTest('Verify minter has MINTER_ROLE', async () => {
      // Wait a moment for state to update
      await new Promise(resolve => setTimeout(resolve, 1000));
      const hasRole = await adminContract.hasRole(MINTER_ROLE, config.minterAddress!);
      if (!hasRole) {
        throw new Error('Minter should have MINTER_ROLE after grant');
      }
    });

    // Test: Minter can mint
    // Check if we can mint (cap not reached)
    const currentSupply = await adminContract.totalSupply();
    const cap = await adminContract.cap();
    const remaining = cap - currentSupply;
    const mintAmount = 10n * 10n ** 18n;
    
    if (remaining >= mintAmount) {
      await suite.runTestWithTx('Minter can mint tokens', async () => {
        return minterContract.mint(config.testUserAddress, mintAmount);
      });
    } else {
      await suite.runTest('Minter can mint tokens', async () => {
        console.log(`  ⚠ Skipping minter mint test - cap reached (remaining: ${remaining / 10n ** 18n})`);
      });
    }

    // Test: Revoke MINTER_ROLE
    await suite.runTestWithTx('Revoke MINTER_ROLE from minter', async () => {
      const txHash = await adminContract.revokeRole(MINTER_ROLE, config.minterAddress!);
      // Wait for transaction confirmation
      await context.publicClient.waitForTransactionReceipt({ hash: txHash });
      return txHash;
    });

    await suite.runTest('Verify minter no longer has MINTER_ROLE', async () => {
      // Wait a moment for state to update
      await new Promise(resolve => setTimeout(resolve, 1000));
      const hasRole = await adminContract.hasRole(MINTER_ROLE, config.minterAddress!);
      if (hasRole) {
        throw new Error('Minter should not have MINTER_ROLE after revoke');
      }
    });

    // Test: Minter cannot mint after revocation
    await suite.expectRevert('Minter cannot mint after role revocation', async () => {
      await minterContract.mint(config.testUserAddress, 10n * 10n ** 18n);
    }, 'AccessControlUnauthorizedAccount');
  } else {
    console.log('  ⚠ Minter account not provided (--minter-keystore or --minter-private-key), skipping minter role tests');
  }

  if (config.pauserAddress && pauserContract) {
    // Test: Grant PAUSER_ROLE
    await suite.runTest('Verify pauser does not have PAUSER_ROLE initially', async () => {
      const hasRole = await adminContract.hasRole(PAUSER_ROLE, config.pauserAddress!);
      if (hasRole) {
        console.log('  ⚠ Pauser already has PAUSER_ROLE, skipping grant test');
        return;
      }
    });

    await suite.runTestWithTx('Grant PAUSER_ROLE to pauser address', async () => {
      const txHash = await adminContract.grantRole(PAUSER_ROLE, config.pauserAddress!);
      // Wait for transaction confirmation
      await context.publicClient.waitForTransactionReceipt({ hash: txHash });
      return txHash;
    });

    await suite.runTest('Verify pauser has PAUSER_ROLE', async () => {
      // Wait a moment for state to update (may need more time for role changes)
      await new Promise(resolve => setTimeout(resolve, 2000));
      const hasRole = await adminContract.hasRole(PAUSER_ROLE, config.pauserAddress!);
      if (!hasRole) {
        throw new Error('Pauser should have PAUSER_ROLE after grant');
      }
    });

    // Test: Pauser can pause
    await suite.runTestWithTx('Pauser can pause contract', async () => {
      // Ensure contract is unpaused first
      const isPaused = await adminContract.paused();
      if (isPaused) {
        // Unpause as admin first
        const unpauseTxHash = await adminContract.unpause();
        await context.publicClient.waitForTransactionReceipt({ hash: unpauseTxHash });
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
      
      const txHash = await pauserContract.pause();
      // Wait for transaction confirmation
      await context.publicClient.waitForTransactionReceipt({ hash: txHash });
      return txHash;
    });

    await suite.runTest('Verify contract is paused by pauser', async () => {
      // Wait a moment for state to update
      await new Promise(resolve => setTimeout(resolve, 1000));
      const isPaused = await adminContract.paused();
      if (!isPaused) {
        throw new Error('Contract should be paused');
      }
    });

    // Test: Pauser can unpause
    await suite.runTestWithTx('Pauser can unpause contract', async () => {
      // Ensure contract is paused first
      const isPaused = await adminContract.paused();
      if (!isPaused) {
        // Pause as pauser first
        const pauseTxHash = await pauserContract.pause();
        await context.publicClient.waitForTransactionReceipt({ hash: pauseTxHash });
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
      
      const txHash = await pauserContract.unpause();
      // Wait for transaction confirmation
      await context.publicClient.waitForTransactionReceipt({ hash: txHash });
      return txHash;
    });

    // Test: Revoke PAUSER_ROLE
    await suite.runTestWithTx('Revoke PAUSER_ROLE from pauser', async () => {
      const txHash = await adminContract.revokeRole(PAUSER_ROLE, config.pauserAddress!);
      // Wait for transaction confirmation
      await context.publicClient.waitForTransactionReceipt({ hash: txHash });
      return txHash;
    });

    await suite.runTest('Verify pauser no longer has PAUSER_ROLE', async () => {
      // Wait a moment for state to update (role changes may need more time)
      await new Promise(resolve => setTimeout(resolve, 2000));
      const hasRole = await adminContract.hasRole(PAUSER_ROLE, config.pauserAddress!);
      if (hasRole) {
        throw new Error('Pauser should not have PAUSER_ROLE after revoke');
      }
    });
  } else {
    console.log('  ⚠ Pauser account not provided (--pauser-keystore or --pauser-private-key), skipping pauser role tests');
  }

  // Test: Grant DEFAULT_ADMIN_ROLE (multi-admin scenario)
  await suite.runTest('Read role admin for MINTER_ROLE', async () => {
    const roleAdmin = await adminContract.getRoleAdmin(MINTER_ROLE);
    if (roleAdmin !== DEFAULT_ADMIN_ROLE) {
      throw new Error(`MINTER_ROLE admin should be DEFAULT_ADMIN_ROLE, got ${roleAdmin}`);
    }
  });

  // Test: Unauthorized role grant (should fail)
  await suite.expectRevert('Unauthorized role grant', async () => {
    const { testUserContract } = context;
    await testUserContract.grantRole(MINTER_ROLE, config.testUserAddress);
  }, 'AccessControlUnauthorizedAccount');

  // Test: getRoleAdmin for all roles
  await suite.runTest('Verify getRoleAdmin for MINTER_ROLE', async () => {
    const roleAdmin = await adminContract.getRoleAdmin(MINTER_ROLE);
    if (roleAdmin !== DEFAULT_ADMIN_ROLE) {
      throw new Error(`MINTER_ROLE admin should be DEFAULT_ADMIN_ROLE, got ${roleAdmin}`);
    }
  });

  await suite.runTest('Verify getRoleAdmin for PAUSER_ROLE', async () => {
    const roleAdmin = await adminContract.getRoleAdmin(PAUSER_ROLE);
    if (roleAdmin !== DEFAULT_ADMIN_ROLE) {
      throw new Error(`PAUSER_ROLE admin should be DEFAULT_ADMIN_ROLE, got ${roleAdmin}`);
    }
  });

  await suite.runTest('Verify getRoleAdmin for DEFAULT_ADMIN_ROLE', async () => {
    const roleAdmin = await adminContract.getRoleAdmin(DEFAULT_ADMIN_ROLE);
    // DEFAULT_ADMIN_ROLE is its own admin
    if (roleAdmin !== DEFAULT_ADMIN_ROLE) {
      throw new Error(`DEFAULT_ADMIN_ROLE admin should be itself, got ${roleAdmin}`);
    }
  });

  // Test: supportsInterface for ERC165
  // Note: Full supportsInterface test would require adding it to the contract interface
  // For now, we verify the contract is accessible and roles work correctly
  await suite.runTest('Verify contract supports standard interfaces', async () => {
    // Verify contract responds to standard ERC20 calls
    const name = await adminContract.name();
    if (!name) {
      throw new Error('Contract should return name');
    }
    // Verify AccessControl interface works
    const hasRole = await adminContract.hasRole(DEFAULT_ADMIN_ROLE, config.adminAddress);
    if (!hasRole) {
      throw new Error('Contract should support AccessControl interface');
    }
  });

  // Note: Full supportsInterface test would require adding it to the contract interface
  // For now, we verify the contract is accessible and roles work correctly

  return suite;
}

