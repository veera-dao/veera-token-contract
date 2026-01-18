import chalk from 'chalk';
import { Address } from 'viem';

export interface TestResult {
  name: string;
  passed: boolean;
  error?: string;
  txHash?: `0x${string}`;
}

export class TestSuite {
  private results: TestResult[] = [];
  private suiteName: string;

  constructor(suiteName: string) {
    this.suiteName = suiteName;
  }

  async runTest(name: string, testFn: () => Promise<void>): Promise<void> {
    try {
      await testFn();
      this.results.push({ name, passed: true });
      console.log(chalk.green(`  ✓ ${name}`));
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.results.push({ name, passed: false, error: errorMessage });
      console.log(chalk.red(`  ✗ ${name}`));
      console.log(chalk.red(`    Error: ${errorMessage}`));
    }
  }

  async runTestWithTx(
    name: string,
    testFn: () => Promise<`0x${string}` | void>
  ): Promise<void> {
    try {
      const txHash = await testFn();
      this.results.push({ name, passed: true, txHash: txHash || undefined });
      if (txHash) {
        console.log(chalk.green(`  ✓ ${name}`));
        console.log(chalk.gray(`    TX: ${txHash}`));
      } else {
        console.log(chalk.green(`  ✓ ${name}`));
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.results.push({ name, passed: false, error: errorMessage });
      console.log(chalk.red(`  ✗ ${name}`));
      console.log(chalk.red(`    Error: ${errorMessage}`));
    }
  }

  async expectRevert(name: string, testFn: () => Promise<void>, expectedError?: string | string[]): Promise<void> {
    try {
      await testFn();
      this.results.push({ name, passed: false, error: 'Expected transaction to revert but it succeeded' });
      console.log(chalk.red(`  ✗ ${name}`));
      console.log(chalk.red(`    Error: Expected revert but transaction succeeded`));
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      if (expectedError) {
        const expectedErrors = Array.isArray(expectedError) ? expectedError : [expectedError];
        const matches = expectedErrors.some(err => errorMessage.includes(err));
        if (!matches) {
          this.results.push({
            name,
            passed: false,
            error: `Expected error containing one of [${expectedErrors.join(', ')}] but got: ${errorMessage}`,
          });
          console.log(chalk.red(`  ✗ ${name}`));
          console.log(chalk.red(`    Error: Expected one of [${expectedErrors.join(', ')}] but got: ${errorMessage}`));
        } else {
          this.results.push({ name, passed: true });
          console.log(chalk.green(`  ✓ ${name} (reverted as expected)`));
        }
      } else {
        this.results.push({ name, passed: true });
        console.log(chalk.green(`  ✓ ${name} (reverted as expected)`));
      }
    }
  }

  printHeader(): void {
    console.log(chalk.cyan(`\n${'='.repeat(60)}`));
    console.log(chalk.cyan.bold(`  ${this.suiteName}`));
    console.log(chalk.cyan(`${'='.repeat(60)}\n`));
  }

  getResults(): TestResult[] {
    return this.results;
  }

  getSummary(): { passed: number; failed: number; total: number } {
    const passed = this.results.filter((r) => r.passed).length;
    const failed = this.results.filter((r) => !r.passed).length;
    return { passed, failed, total: this.results.length };
  }
}

export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000' as Address;

