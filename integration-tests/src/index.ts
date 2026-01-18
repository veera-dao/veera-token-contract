import chalk from 'chalk';
import { setupTestContext } from './setup.js';
import { TestResult } from './test-utils.js';
import { runPreflightChecks } from './preflight.js';
import { runERC20Tests } from './test-suites/erc20.test.js';
import { runPermitTests } from './test-suites/permit.test.js';
import { runMintingTests } from './test-suites/minting.test.js';
import { runBurningTests } from './test-suites/burning.test.js';
import { runPausingTests } from './test-suites/pausing.test.js';
import { runRoleTests } from './test-suites/roles.test.js';
import { runEdgeCaseTests } from './test-suites/edge-cases.test.js';

async function main() {
  console.log(chalk.cyan.bold('\n╔════════════════════════════════════════════════════════════════╗'));
  console.log(chalk.cyan.bold('║'));
  console.log(chalk.cyan.bold('║     ██╗   ██╗███████╗███████╗██████╗  █████╗'));
  console.log(chalk.cyan.bold('║     ██║   ██║██╔════╝██╔════╝██╔══██╗██╔══██╗'));
  console.log(chalk.cyan.bold('║     ██║   ██║█████╗  █████╗  ██████╔╝███████║'));
  console.log(chalk.cyan.bold('║     ╚██╗ ██╔╝██╔══╝  ██╔══╝  ██╔══██╗██╔══██║'));
  console.log(chalk.cyan.bold('║      ╚████╔╝ ███████╗███████╗██║  ██║██║  ██║'));
  console.log(chalk.cyan.bold('║       ╚═══╝  ╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝'));
  console.log(chalk.cyan.bold('║'));
  console.log(chalk.cyan.bold('║        🧪 INTEGRATION TEST SUITE 🧪'));
  console.log(chalk.cyan.bold('║'));
  console.log(chalk.cyan.bold('╚════════════════════════════════════════════════════════════════╝\n'));

  let context;
  try {
    console.log(chalk.blue('Setting up test context...'));
    context = await setupTestContext();
    console.log(chalk.green(`✓ Connected to contract at ${context.config.contractAddress}\n`));
  } catch (error) {
    console.error(chalk.red('Failed to setup test context:'));
    console.error(error);
    process.exit(1);
  }

  // Run pre-flight checks (gas estimation and balance verification)
  const skipPreflight = process.env.SKIP_PREFLIGHT === 'true';
  if (!skipPreflight && context) {
    const preflightPassed = await runPreflightChecks(context);
    if (!preflightPassed) {
      console.log(chalk.yellow('\n⚠️  Pre-flight checks failed, but continuing with tests...'));
      console.log(chalk.yellow('   Set SKIP_PREFLIGHT=true to skip these checks.\n'));
      const shouldContinue = process.env.FORCE_CONTINUE === 'true';
      if (!shouldContinue) {
        console.log(chalk.red('   Exiting. Set FORCE_CONTINUE=true to run tests anyway.\n'));
        process.exit(1);
      }
    }
  } else if (skipPreflight) {
    console.log(chalk.yellow('⚠️  Skipping pre-flight checks (SKIP_PREFLIGHT=true)\n'));
  }

  if (!context) {
    console.error(chalk.red('Test context is undefined'));
    process.exit(1);
  }

  const allResults: TestResult[] = [];
  const suiteResults: Array<{ name: string; results: TestResult[] }> = [];

  // Run all test suites sequentially
  try {
    console.log(chalk.blue('Starting test execution...\n'));

    // ERC20 Tests
    const erc20Suite = await runERC20Tests(context);
    suiteResults.push({ name: 'ERC20 Operations', results: erc20Suite.getResults() });
    allResults.push(...erc20Suite.getResults());

    // Permit Tests
    const permitSuite = await runPermitTests(context);
    suiteResults.push({ name: 'ERC20Permit', results: permitSuite.getResults() });
    allResults.push(...permitSuite.getResults());

    // Minting Tests
    const mintingSuite = await runMintingTests(context);
    suiteResults.push({ name: 'Minting Operations', results: mintingSuite.getResults() });
    allResults.push(...mintingSuite.getResults());

    // Burning Tests
    const burningSuite = await runBurningTests(context);
    suiteResults.push({ name: 'Burning Operations', results: burningSuite.getResults() });
    allResults.push(...burningSuite.getResults());

    // Pausing Tests
    const pausingSuite = await runPausingTests(context);
    suiteResults.push({ name: 'Pausing Operations', results: pausingSuite.getResults() });
    allResults.push(...pausingSuite.getResults());

    // Role Tests
    const roleSuite = await runRoleTests(context);
    suiteResults.push({ name: 'Access Control', results: roleSuite.getResults() });
    allResults.push(...roleSuite.getResults());

    // Edge Cases
    const edgeCaseSuite = await runEdgeCaseTests(context);
    suiteResults.push({ name: 'Edge Cases', results: edgeCaseSuite.getResults() });
    allResults.push(...edgeCaseSuite.getResults());
  } catch (error) {
    console.error(chalk.red('\nFatal error during test execution:'));
    console.error(error);
  }

  // Print summary
  console.log(chalk.cyan('\n' + '='.repeat(60)));
  console.log(chalk.cyan.bold('  TEST SUMMARY'));
  console.log(chalk.cyan('='.repeat(60) + '\n'));

  // Per-suite summary
  for (const suite of suiteResults) {
    const passed = suite.results.filter((r) => r.passed).length;
    const failed = suite.results.filter((r) => !r.passed).length;
    const total = suite.results.length;
    const status = failed === 0 ? chalk.green('✓') : chalk.red('✗');
    console.log(
      `${status} ${suite.name}: ${chalk.green(`${passed}/${total}`)} passed, ${chalk.red(`${failed}/${total}`)} failed`
    );
  }

  // Overall summary
  const totalPassed = allResults.filter((r) => r.passed).length;
  const totalFailed = allResults.filter((r) => !r.passed).length;
  const total = allResults.length;

  console.log(chalk.cyan('\n' + '='.repeat(60)));
  console.log(chalk.cyan.bold('  OVERALL RESULTS'));
  console.log(chalk.cyan('='.repeat(60) + '\n'));

  console.log(`Total Tests: ${total}`);
  console.log(chalk.green(`Passed: ${totalPassed}`));
  console.log(chalk.red(`Failed: ${totalFailed}`));
  console.log(`Success Rate: ${((totalPassed / total) * 100).toFixed(2)}%\n`);

  // Print failed tests
  if (totalFailed > 0) {
    console.log(chalk.red.bold('Failed Tests:'));
    console.log(chalk.red('='.repeat(60)));
    for (const result of allResults) {
      if (!result.passed) {
        console.log(chalk.red(`\n✗ ${result.name}`));
        if (result.error) {
          console.log(chalk.red(`  Error: ${result.error}`));
        }
      }
    }
    console.log('');
  }

  // Final status
  if (totalFailed === 0) {
    console.log(chalk.green.bold('╔════════════════════════════════════════════════════════════════╗'));
    console.log(chalk.green.bold('║'));
    console.log(chalk.green.bold('║                    ✅ ALL TESTS PASSED ✅'));
    console.log(chalk.green.bold('║'));
    console.log(chalk.green.bold('╚════════════════════════════════════════════════════════════════╝\n'));
    process.exit(0);
  } else {
    console.log(chalk.red.bold('╔════════════════════════════════════════════════════════════════╗'));
    console.log(chalk.red.bold('║'));
    console.log(chalk.red.bold('║                    ❌ SOME TESTS FAILED ❌'));
    console.log(chalk.red.bold('║'));
    console.log(chalk.red.bold('╚════════════════════════════════════════════════════════════════╝\n'));
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(chalk.red('Unhandled error:'));
  console.error(error);
  process.exit(1);
});

