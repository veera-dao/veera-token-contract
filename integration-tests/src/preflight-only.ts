import chalk from 'chalk';
import { setupTestContext } from './setup.js';
import { runPreflightChecks } from './preflight.js';

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
  console.log(chalk.cyan.bold('║           🔍 PRE-FLIGHT CHECKS ONLY 🔍'));
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

  const preflightPassed = await runPreflightChecks(context);
  
  if (preflightPassed) {
    console.log(chalk.green.bold('╔════════════════════════════════════════════════════════════════╗'));
    console.log(chalk.green.bold('║'));
    console.log(chalk.green.bold('║              ✅ PRE-FLIGHT CHECKS PASSED ✅'));
    console.log(chalk.green.bold('║'));
    console.log(chalk.green.bold('╚════════════════════════════════════════════════════════════════╝\n'));
    process.exit(0);
  } else {
    console.log(chalk.red.bold('╔════════════════════════════════════════════════════════════════╗'));
    console.log(chalk.red.bold('║'));
    console.log(chalk.red.bold('║              ❌ PRE-FLIGHT CHECKS FAILED ❌'));
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

