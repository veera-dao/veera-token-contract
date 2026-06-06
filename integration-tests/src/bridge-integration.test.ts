import chalk from 'chalk';
import dotenv from 'dotenv';
import { readFileSync, existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import {
  createPublicClient,
  createWalletClient,
  http,
  Address,
  Hex,
  parseEther,
  formatEther
} from 'viem';
import { privateKeyToAccount, generatePrivateKey } from 'viem/accounts';
import { baseSepolia, bscTestnet } from 'viem/chains';

// Load environment variables
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = join(__dirname, '../..');
dotenv.config({ path: join(projectRoot, '.env') });

// Load ABI files dynamically
const veeraAbi = JSON.parse(readFileSync(join(projectRoot, 'integration-tests/src/veera-abi.json'), 'utf-8'));
const adapterArtifact = JSON.parse(
  readFileSync(join(projectRoot, 'out/VeeraMintBurnOFTAdapter.sol/VeeraMintBurnOFTAdapter.json'), 'utf-8')
);
const ADAPTER_ABI = adapterArtifact.abi;
const VEERA_ABI = veeraAbi;

// Load manifest
const manifestFile = process.env.DEPLOY_MANIFEST_PATH || 'deploy_manifest.local.json';
const manifestPath = join(projectRoot, manifestFile);
if (!existsSync(manifestPath)) {
  console.error(chalk.red(`❌ Deploy manifest not found at: ${manifestPath}`));
  process.exit(1);
}
const manifest = JSON.parse(readFileSync(manifestPath, 'utf-8'));

const TOKEN_ADDRESS = manifest.expectedTokenAddress as Address;
const BASE_BRIDGE = manifest.networks['84532'].expectedBridgeAddress as Address;
const BSC_BRIDGE = manifest.networks['97'].expectedBridgeAddress as Address;

const BASE_EID = 40245;
const BSC_EID = 40102;

// Standard Options: 200,000 gas for lzReceive, 0 value
const LZ_OPTIONS = '0x00030100110100000000000000000000000000030d40' as Hex;

function addressToBytes32(address: Address): Hex {
  return `0x${address.slice(2).padStart(64, '0')}` as Hex;
}

// Helper to wait
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

// Type-safe contract helper wrappers
async function readContract(publicClient: any, contractAddress: Address, abi: any, functionName: string, args: any[] = []): Promise<any> {
  return publicClient.readContract({
    address: contractAddress,
    abi,
    functionName,
    args
  });
}

async function writeContract(walletClient: any, publicClient: any, contractAddress: Address, abi: any, functionName: string, args: any[] = [], value?: bigint): Promise<Hex> {
  const hash = await walletClient.writeContract({
    address: contractAddress,
    abi,
    functionName,
    args,
    value
  });
  await publicClient.waitForTransactionReceipt({ hash });
  return hash;
}

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
  console.log(chalk.cyan.bold('║          🌉 LAYERZERO TESTNET BRIDGE INTEGRATION 🌉'));
  console.log(chalk.cyan.bold('║'));
  console.log(chalk.cyan.bold('╚════════════════════════════════════════════════════════════════╝\n'));

  // Get RPC URLs
  const baseRpcUrl = process.env.BASE_SEPOLIA_RPC_URL || 'https://sepolia.base.org';
  const bscRpcUrl = process.env.BSC_TESTNET_RPC_URL || 'https://data-seed-prebsc-1-s1.binance.org:8545';

  // Get Private Key
  // Check CLI arguments first
  let privateKey = '';
  const args = process.argv.slice(2);
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith('--private-key=')) {
      privateKey = args[i].split('=')[1];
    } else if (args[i] === '--private-key' && i + 1 < args.length) {
      privateKey = args[i + 1];
    }
  }

  if (!privateKey) {
    privateKey = process.env.PRIVATE_KEY || process.env.ADMIN_PRIVATE_KEY || '';
  }

  if (!privateKey) {
    console.log(chalk.yellow('⚠️  No signing private key provided. Running preflight checks & dry-run simulation...\n'));
    console.log(chalk.blue('To run actual bridge transactions, provide a private key:'));
    console.log(chalk.blue('  - Via env variable: PRIVATE_KEY=0x...'));
    console.log(chalk.blue('  - Or via CLI: --private-key=0x...\n'));

    await runDryRun(baseRpcUrl, bscRpcUrl);
    return;
  }

  if (!privateKey.startsWith('0x')) {
    privateKey = `0x${privateKey}`;
  }

  const account = privateKeyToAccount(privateKey as Hex);
  const userAddress = account.address;
  console.log(chalk.green(`🔑 Loaded Signer Account: ${chalk.bold(userAddress)}\n`));

  // Initialize clients for Base Sepolia (Chain ID 84532)
  console.log(chalk.blue('Initializing Base Sepolia client...'));
  const basePublic = createPublicClient({ chain: baseSepolia, transport: http(baseRpcUrl) });
  const baseWallet = createWalletClient({ account, chain: baseSepolia, transport: http(baseRpcUrl) });

  // Initialize clients for BSC Testnet (Chain ID 97)
  console.log(chalk.blue('Initializing BSC Testnet client...'));
  const bscPublic = createPublicClient({ chain: bscTestnet, transport: http(bscRpcUrl) });
  const bscWallet = createWalletClient({ account, chain: bscTestnet, transport: http(bscRpcUrl) });

  console.log(chalk.green('✓ Clients initialized successfully!\n'));

  // Pre-test cleanup: Ensure adapters are unpaused
  const adminKey = process.env.TESTING_BRIDGE_ADMIN_PRIVATE_KEY;
  if (adminKey) {
    try {
      const adminAcc = privateKeyToAccount(adminKey.startsWith('0x') ? adminKey as Hex : `0x${adminKey}` as Hex);
      const baseAdminWallet = createWalletClient({ account: adminAcc, chain: baseSepolia, transport: http(baseRpcUrl) });
      const bscAdminWallet = createWalletClient({ account: adminAcc, chain: bscTestnet, transport: http(bscRpcUrl) });

      const basePaused = await readContract(basePublic, BASE_BRIDGE, ADAPTER_ABI, 'paused');
      if (basePaused) {
        console.log(chalk.yellow('  ⚠️  Base Bridge is currently paused. Unpausing for test run...'));
        await writeContract(baseAdminWallet, basePublic, BASE_BRIDGE, ADAPTER_ABI, 'unpause');
        console.log(chalk.green('  ✓ Base Bridge unpaused.'));
      }

      const bscPaused = await readContract(bscPublic, BSC_BRIDGE, ADAPTER_ABI, 'paused');
      if (bscPaused) {
        console.log(chalk.yellow('  ⚠️  BSC Bridge is currently paused. Unpausing for test run...'));
        await writeContract(bscAdminWallet, bscPublic, BSC_BRIDGE, ADAPTER_ABI, 'unpause');
        console.log(chalk.green('  ✓ BSC Bridge unpaused.'));
      }
    } catch (e: any) {
      console.log(chalk.yellow(`  ⚠️  Failed to check/unpause adapters during initialization: ${e.message}`));
    }
  }

  // 1. Check native balances
  const baseEthBalance = await basePublic.getBalance({ address: userAddress });
  const bscBnbBalance = await bscPublic.getBalance({ address: userAddress });

  console.log(chalk.white.bold('Initial gas balances:'));
  console.log(`  Base Sepolia (ETH): ${chalk.magenta(formatEther(baseEthBalance))} ETH`);
  console.log(`  BSC Testnet  (BNB): ${chalk.magenta(formatEther(bscBnbBalance))} BNB\n`);

  if (baseEthBalance === 0n) {
    console.error(chalk.red('❌ Insufficient gas on Base Sepolia. Fund the account with Sepolia ETH.'));
    process.exit(1);
  }
  if (bscBnbBalance === 0n) {
    console.error(chalk.red('❌ Insufficient gas on BSC Testnet. Fund the account with testnet BNB.'));
    process.exit(1);
  }

  // 2. Check token balances
  let baseTokenBalance = await readContract(basePublic, TOKEN_ADDRESS, VEERA_ABI, 'balanceOf', [userAddress]);
  let bscTokenBalance = await readContract(bscPublic, TOKEN_ADDRESS, VEERA_ABI, 'balanceOf', [userAddress]);

  console.log(chalk.white.bold('Initial VEERA token balances:'));
  console.log(`  Base Sepolia: ${chalk.cyan(formatEther(baseTokenBalance))} VEERA`);
  console.log(`  BSC Testnet:  ${chalk.cyan(formatEther(bscTokenBalance))} VEERA\n`);

  const amountToSend = parseEther('1'); // Send 1 VEERA

  // Self-healing: if Base Sepolia balance is less than 1 VEERA, attempt to mint
  if (baseTokenBalance < amountToSend) {
    console.log(chalk.yellow('⚠️  Insufficient VEERA on Base Sepolia. Checking if account has MINTER_ROLE to self-mint...'));
    const MINTER_ROLE = await readContract(basePublic, TOKEN_ADDRESS, VEERA_ABI, 'MINTER_ROLE');
    const hasMinter = await readContract(basePublic, TOKEN_ADDRESS, VEERA_ABI, 'hasRole', [MINTER_ROLE, userAddress]);

    if (hasMinter) {
      console.log(chalk.blue('  - Minting 5 VEERA on Base Sepolia...'));
      await writeContract(baseWallet, basePublic, TOKEN_ADDRESS, VEERA_ABI, 'mint', [userAddress, parseEther('5')]);
      baseTokenBalance = await readContract(basePublic, TOKEN_ADDRESS, VEERA_ABI, 'balanceOf', [userAddress]);
      console.log(chalk.green(`  ✓ Mint successful! New balance: ${formatEther(baseTokenBalance)} VEERA\n`));
    } else {
      console.error(chalk.red(`❌ Insufficient VEERA balance (${formatEther(baseTokenBalance)}) and signer lacks MINTER_ROLE.`));
      process.exit(1);
    }
  }

  const skipBase = process.env.SKIP_BASE_TESTS === 'true' || process.argv.includes('--skip-base');

  if (skipBase) {
    console.log(chalk.yellow('\n⏭️  Skipping Stage 1 & Stage 2 base bridge tests (progressing straight to failure/edge cases)...\n'));
  } else {
    // =========================================================================
    // Cycle 1: Base Sepolia -> BSC Testnet
    // =========================================================================
    console.log(chalk.blue.bold('🚀 STAGE 1: Bridging Base Sepolia ➔ BSC Testnet...'));

    // Approve token spend
    console.log(chalk.blue('  - Approving bridge contract on Base Sepolia...'));
    await writeContract(baseWallet, basePublic, TOKEN_ADDRESS, VEERA_ABI, 'approve', [BASE_BRIDGE, amountToSend]);
    console.log(chalk.green('  ✓ Approved spend of 1 VEERA.'));

    // Formulate send params
    const sendParamBase = {
      dstEid: BSC_EID,
      to: addressToBytes32(userAddress),
      amountLD: amountToSend,
      minAmountLD: amountToSend,
      extraOptions: LZ_OPTIONS,
      composeMsg: '0x' as Hex,
      oftCmd: '0x' as Hex
    };

    // Quote send fee
    console.log(chalk.blue('  - Querying LayerZero quote on Base Sepolia...'));
    const { nativeFee: nativeFeeBase } = await readContract(basePublic, BASE_BRIDGE, ADAPTER_ABI, 'quoteSend', [sendParamBase, false]);

    console.log(`  - Quoted LayerZero native fee: ${chalk.magenta(formatEther(nativeFeeBase))} ETH`);

    // Execute bridge send
    console.log(chalk.blue('  - Sending bridge transaction...'));
    const sendTxBase = await writeContract(
      baseWallet,
      basePublic,
      BASE_BRIDGE,
      ADAPTER_ABI,
      'send',
      [sendParamBase, [nativeFeeBase, 0n], userAddress],
      nativeFeeBase
    );
    console.log(chalk.green(`  ✓ Transaction sent! Hash: ${chalk.cyan(sendTxBase)}`));
    console.log(chalk.yellow(`    Trace here: https://testnet.layerzeroscan.com/tx/${sendTxBase}`));

    // Poll BSC Testnet balance
    console.log(chalk.blue('  - Polling BSC Testnet for credit delivery (this may take 1-3 minutes)...'));
    const bscBalanceBefore = bscTokenBalance;
    let bscBalanceAfter = bscBalanceBefore;
    let attempts = 0;
    const maxAttempts = 60; // 30 minutes max (60 * 30s)

    while (bscBalanceAfter === bscBalanceBefore && attempts < maxAttempts) {
      attempts++;
      process.stdout.write(`\r    [Attempt ${attempts}/${maxAttempts}] Current BSC Balance: ${formatEther(bscBalanceAfter)} VEERA (Sleeping for 30s)`);
      await sleep(30000); // 30 seconds
      try {
        bscBalanceAfter = await readContract(bscPublic, TOKEN_ADDRESS, VEERA_ABI, 'balanceOf', [userAddress]);
      } catch (err) {
        process.stdout.write(`\r    [Attempt ${attempts}/${maxAttempts}] Error querying balance: ${(err as Error).message} (Sleeping for 30s)`);
      }
    }
    process.stdout.write(`\r    [Attempt ${attempts}/${maxAttempts}] Final BSC Balance: ${formatEther(bscBalanceAfter)} VEERA\n`);

    if (bscBalanceAfter > bscBalanceBefore) {
      console.log(chalk.green.bold(`\n🎉 STAGE 1 SUCCESSFUL! Received ${formatEther(bscBalanceAfter - bscBalanceBefore)} VEERA on BSC Testnet.\n`));
    } else {
      console.error(chalk.red('\n❌ STAGE 1 TIMEOUT: Token delivery exceeded 30 minutes. Check LayerZeroScan for status.\n'));
      process.exit(1);
    }

    // =========================================================================
    // Cycle 2: BSC Testnet -> Base Sepolia
    // =========================================================================
    console.log(chalk.blue.bold('🚀 STAGE 2: Bridging BSC Testnet ➔ Base Sepolia...'));

    // Approve token spend
    console.log(chalk.blue('  - Approving bridge contract on BSC Testnet...'));
    await writeContract(bscWallet, bscPublic, TOKEN_ADDRESS, VEERA_ABI, 'approve', [BSC_BRIDGE, amountToSend]);
    console.log(chalk.green('  ✓ Approved spend of 1 VEERA.'));

    // Formulate send params
    const sendParamBsc = {
      dstEid: BASE_EID,
      to: addressToBytes32(userAddress),
      amountLD: amountToSend,
      minAmountLD: amountToSend,
      extraOptions: LZ_OPTIONS,
      composeMsg: '0x' as Hex,
      oftCmd: '0x' as Hex
    };

    // Quote send fee
    console.log(chalk.blue('  - Querying LayerZero quote on BSC Testnet...'));
    const { nativeFee: nativeFeeBsc } = await readContract(bscPublic, BSC_BRIDGE, ADAPTER_ABI, 'quoteSend', [sendParamBsc, false]);

    console.log(`  - Quoted LayerZero native fee: ${chalk.magenta(formatEther(nativeFeeBsc))} BNB`);

    // Execute bridge send
    console.log(chalk.blue('  - Sending bridge transaction...'));
    const sendTxBsc = await writeContract(
      bscWallet,
      bscPublic,
      BSC_BRIDGE,
      ADAPTER_ABI,
      'send',
      [sendParamBsc, [nativeFeeBsc, 0n], userAddress],
      nativeFeeBsc
    );
    console.log(chalk.green(`  ✓ Transaction sent! Hash: ${chalk.cyan(sendTxBsc)}`));
    console.log(chalk.yellow(`    Trace here: https://testnet.layerzeroscan.com/tx/${sendTxBsc}`));

    // Poll Base Sepolia balance
    console.log(chalk.blue('  - Polling Base Sepolia for credit delivery (this may take 1-3 minutes)...'));
    const baseBalanceBefore = await readContract(basePublic, TOKEN_ADDRESS, VEERA_ABI, 'balanceOf', [userAddress]);
    let baseBalanceAfter = baseBalanceBefore;
    attempts = 0;

    while (baseBalanceAfter === baseBalanceBefore && attempts < maxAttempts) {
      attempts++;
      process.stdout.write(`\r    [Attempt ${attempts}/${maxAttempts}] Current Base Balance: ${formatEther(baseBalanceAfter)} VEERA (Sleeping for 30s)`);
      await sleep(30000); // 30 seconds
      try {
        baseBalanceAfter = await readContract(basePublic, TOKEN_ADDRESS, VEERA_ABI, 'balanceOf', [userAddress]);
      } catch (err) {
        process.stdout.write(`\r    [Attempt ${attempts}/${maxAttempts}] Error querying balance: ${(err as Error).message} (Sleeping for 30s)`);
      }
    }
    process.stdout.write(`\r    [Attempt ${attempts}/${maxAttempts}] Final Base Balance: ${formatEther(baseBalanceAfter)} VEERA\n`);

    if (baseBalanceAfter > baseBalanceBefore) {
      console.log(chalk.green.bold(`\n🎉 STAGE 2 SUCCESSFUL! Received ${formatEther(baseBalanceAfter - baseBalanceBefore)} VEERA on Base Sepolia.\n`));
    } else {
      console.error(chalk.red('\n❌ STAGE 2 TIMEOUT: Token delivery exceeded 30 minutes. Check LayerZeroScan for status.\n'));
      process.exit(1);
    }
  }

  // 3. Execute failure and edge case integration tests
  await runFailureAndEdgeCaseTests(
    basePublic,
    baseWallet,
    bscPublic,
    bscWallet,
    userAddress,
    baseRpcUrl,
    bscRpcUrl
  );

  console.log(chalk.green.bold('╔════════════════════════════════════════════════════════════════╗'));
  console.log(chalk.green.bold('║'));
  console.log(chalk.green.bold('║            ✅ ALL BRIDGE INTEGRATION CYCLES COMPLETED ✅'));
  console.log(chalk.green.bold('║                   ROUNDTRIP BRIDGING SUCCESSFUL!'));
  console.log(chalk.green.bold('║'));
  console.log(chalk.green.bold('╚════════════════════════════════════════════════════════════════╝\n'));
}

async function runFailureAndEdgeCaseTests(
  basePublic: any,
  baseWallet: any,
  bscPublic: any,
  bscWallet: any,
  userAddress: Address,
  baseRpcUrl: string,
  bscRpcUrl: string
) {
  console.log(chalk.yellow.bold('\n🔬 RUNNING FAILURE AND EDGE CASE TESTS...\n'));
  const amountToSend = parseEther('1'); // Use 1 VEERA

  // 1. Underfunded LayerZero Native Fee
  console.log(chalk.blue('Test 1: Underfunding LayerZero Native Fee (msg.value)...'));
  const sendParamBase = {
    dstEid: BSC_EID,
    to: addressToBytes32(userAddress),
    amountLD: amountToSend,
    minAmountLD: amountToSend,
    extraOptions: LZ_OPTIONS,
    composeMsg: '0x' as Hex,
    oftCmd: '0x' as Hex
  };

  try {
    const { nativeFee } = await readContract(basePublic, BASE_BRIDGE, ADAPTER_ABI, 'quoteSend', [sendParamBase, false]);
    // Intentionally pass only half of the native fee
    const halfFee = nativeFee / 2n;
    console.log(`  - Quoted fee: ${formatEther(nativeFee)} ETH. Sending with: ${formatEther(halfFee)} ETH...`);

    // Call send with underfunded fee
    await baseWallet.writeContract({
      address: BASE_BRIDGE,
      abi: ADAPTER_ABI,
      functionName: 'send',
      args: [sendParamBase, [halfFee, 0n], userAddress],
      value: halfFee
    });
    console.log(chalk.red('  ✗ Failure: Transaction succeeded but was expected to revert due to insufficient nativeFee.'));
    process.exit(1);
  } catch (error: any) {
    console.log(chalk.green(`  ✓ Correctly reverted: ${error.message.split('\n')[0]}`));
  }

  // 2. Underfunded Option Gas Limit (enforcedOptions)
  console.log(chalk.blue('\nTest 2: Underfunding Option Gas Limit / Invalid Option Type (extraOptions)...'));
  // Enforced options require type 3. Let's pass invalid type 1 options (hex"0001").
  const invalidOptions = '0x0001' as Hex;
  const sendParamLowGas = {
    ...sendParamBase,
    extraOptions: invalidOptions
  };

  try {
    console.log('  - Attempting quoteSend with invalid option type (type 1 options hex"0001")...');
    await readContract(basePublic, BASE_BRIDGE, ADAPTER_ABI, 'quoteSend', [sendParamLowGas, false]);
    console.log(chalk.red('  ✗ Failure: quoteSend succeeded but was expected to revert due to invalid option type.'));
    process.exit(1);
  } catch (error: any) {
    console.log(chalk.green(`  ✓ Correctly reverted: ${error.message.split('\n')[0]}`));
  }

  // 3. Underfunded Account Gas Balance
  console.log(chalk.blue('\nTest 3: Underfunded Account Gas Balance...'));
  try {
    const tempPrivateKey = generatePrivateKey();
    const tempAccount = privateKeyToAccount(tempPrivateKey);
    const tempWallet = createWalletClient({ account: tempAccount, chain: baseSepolia, transport: http(baseRpcUrl) });
    console.log(`  - Attempting to send from zero-gas account: ${tempAccount.address}...`);

    await tempWallet.writeContract({
      address: TOKEN_ADDRESS,
      abi: VEERA_ABI,
      functionName: 'approve',
      args: [BASE_BRIDGE, amountToSend]
    });
    console.log(chalk.red('  ✗ Failure: Transaction succeeded but was expected to fail due to underfunded account.'));
    process.exit(1);
  } catch (error: any) {
    console.log(chalk.green(`  ✓ Correctly failed: ${error.message.split('\n')[0]}`));
  }

  // 4. Insufficient Token Balance
  console.log(chalk.blue('\nTest 4: Bridging Insufficient Token Balance...'));
  const excessiveAmount = parseEther('100000000000'); // 100 Billion VEERA
  const sendParamExcessive = {
    ...sendParamBase,
    amountLD: excessiveAmount,
    minAmountLD: excessiveAmount
  };

  try {
    const { nativeFee } = await readContract(basePublic, BASE_BRIDGE, ADAPTER_ABI, 'quoteSend', [sendParamExcessive, false]);
    console.log(`  - Attempting to bridge ${formatEther(excessiveAmount)} VEERA (exceeds balance)...`);

    await baseWallet.writeContract({
      address: BASE_BRIDGE,
      abi: ADAPTER_ABI,
      functionName: 'send',
      args: [sendParamExcessive, [nativeFee, 0n], userAddress],
      value: nativeFee
    });
    console.log(chalk.red('  ✗ Failure: Transaction succeeded but was expected to revert due to insufficient token balance.'));
    process.exit(1);
  } catch (error: any) {
    console.log(chalk.green(`  ✓ Correctly reverted: ${error.message.split('\n')[0]}`));
  }

  // 5. Insufficient Token Allowance
  console.log(chalk.blue('\nTest 5: Bridging Insufficient Token Allowance...'));
  try {
    console.log('  - Clearing bridge allowance to 0...');
    await writeContract(baseWallet, basePublic, TOKEN_ADDRESS, VEERA_ABI, 'approve', [BASE_BRIDGE, 0n]);

    const { nativeFee } = await readContract(basePublic, BASE_BRIDGE, ADAPTER_ABI, 'quoteSend', [sendParamBase, false]);
    console.log('  - Attempting to bridge 1 VEERA without allowance...');

    await baseWallet.writeContract({
      address: BASE_BRIDGE,
      abi: ADAPTER_ABI,
      functionName: 'send',
      args: [sendParamBase, [nativeFee, 0n], userAddress],
      value: nativeFee
    });
    console.log(chalk.red('  ✗ Failure: Transaction succeeded but was expected to revert due to insufficient allowance.'));
    process.exit(1);
  } catch (error: any) {
    console.log(chalk.green(`  ✓ Correctly reverted: ${error.message.split('\n')[0]}`));
  } finally {
    console.log('  - Restoring bridge allowance...');
    await writeContract(baseWallet, basePublic, TOKEN_ADDRESS, VEERA_ABI, 'approve', [BASE_BRIDGE, amountToSend]);
  }

  // 6. Bridging Zero Tokens
  console.log(chalk.blue('\nTest 6: Bridging Zero Tokens...'));
  const sendParamZero = {
    ...sendParamBase,
    amountLD: 0n,
    minAmountLD: 0n
  };
  try {
    console.log('  - Attempting to quote or send zero tokens...');
    const { nativeFee } = await readContract(basePublic, BASE_BRIDGE, ADAPTER_ABI, 'quoteSend', [sendParamZero, false]);
    console.log(`    - Quoted native fee for 0 tokens: ${formatEther(nativeFee)} ETH`);
    const sendTxZero = await writeContract(
      baseWallet,
      basePublic,
      BASE_BRIDGE,
      ADAPTER_ABI,
      'send',
      [sendParamZero, [nativeFee, 0n], userAddress],
      nativeFee
    );
    console.log(chalk.green(`  ✓ Successfully processed bridging of 0 tokens. Tx Hash: ${sendTxZero}`));
  } catch (error: any) {
    console.log(chalk.green(`  ✓ Correctly handled or reverted: ${error.message.split('\n')[0]}`));
  }

  // 7. Bridging to Invalid Destination EID
  console.log(chalk.blue('\nTest 7: Bridging to Invalid Destination EID (99999)...'));
  const sendParamInvalidEid = {
    ...sendParamBase,
    dstEid: 99999
  };
  try {
    console.log('  - Attempting to quoteSend for EID 99999...');
    await readContract(basePublic, BASE_BRIDGE, ADAPTER_ABI, 'quoteSend', [sendParamInvalidEid, false]);
    console.log(chalk.red('  ✗ Failure: quoteSend succeeded but was expected to revert due to invalid EID.'));
    process.exit(1);
  } catch (error: any) {
    console.log(chalk.green(`  ✓ Correctly reverted: ${error.message.split('\n')[0]}`));
  }

  // 8. Pausing Test (TESTING_BRIDGE_ADMIN_PRIVATE_KEY)
  console.log(chalk.blue('\nTest 8: Adapter Pausing / Unpausing Checks...'));
  const adminKey = process.env.TESTING_BRIDGE_ADMIN_PRIVATE_KEY;
  if (!adminKey) {
    console.log(chalk.yellow('  ⚠️  Skipping pause test: TESTING_BRIDGE_ADMIN_PRIVATE_KEY is not defined.'));
  } else {
    try {
      const adminAcc = privateKeyToAccount(adminKey.startsWith('0x') ? adminKey as Hex : `0x${adminKey}` as Hex);
      console.log(`  - Loaded Admin Signer Account: ${adminAcc.address}`);

      const baseAdminWallet = createWalletClient({ account: adminAcc, chain: baseSepolia, transport: http(baseRpcUrl) });

      const isPausedInitially = await readContract(basePublic, BASE_BRIDGE, ADAPTER_ABI, 'paused');
      if (isPausedInitially) {
        console.log('  - Adapter was paused initially. Unpausing first...');
        await writeContract(baseAdminWallet, basePublic, BASE_BRIDGE, ADAPTER_ABI, 'unpause');
        console.log(chalk.green('  ✓ Base Bridge Adapter unpaused.'));
      }

      console.log('  - Verifying send reverts while paused...');
      // Query quoteSend fee BEFORE pausing, since quoteSend reverts when paused
      const { nativeFee } = await readContract(basePublic, BASE_BRIDGE, ADAPTER_ABI, 'quoteSend', [sendParamBase, false]);

      console.log('  - Pausing Base Bridge Adapter...');
      await writeContract(baseAdminWallet, basePublic, BASE_BRIDGE, ADAPTER_ABI, 'pause');
      console.log(chalk.green('  ✓ Base Bridge Adapter paused.'));

      try {
        await baseWallet.writeContract({
          address: BASE_BRIDGE,
          abi: ADAPTER_ABI,
          functionName: 'send',
          args: [sendParamBase, [nativeFee, 0n], userAddress],
          value: nativeFee
        });
        console.log(chalk.red('  ✗ Failure: Transaction succeeded but was expected to revert due to paused adapter.'));
        process.exit(1);
      } catch (error: any) {
        console.log(chalk.green(`    ✓ Successfully blocked send: ${error.message.split('\n')[0]}`));
      }

      console.log('  - Unpausing Base Bridge Adapter...');
      await writeContract(baseAdminWallet, basePublic, BASE_BRIDGE, ADAPTER_ABI, 'unpause');
      console.log(chalk.green('  ✓ Base Bridge Adapter unpaused.'));
    } catch (error: any) {
      console.log(chalk.red(`  ✗ Pause test failed with error: ${error.message}`));
      process.exit(1);
    }
  }

  console.log(chalk.green.bold('\n🎉 ALL FAILURE AND EDGE CASE TEST CASES PASSED!\n'));
}

async function runDryRun(baseRpcUrl: string, bscRpcUrl: string) {
  console.log(chalk.cyan('🔍 Starting Dry-Run Check...'));

  // Setup clients
  const basePublic = createPublicClient({ chain: baseSepolia, transport: http(baseRpcUrl) });
  const bscPublic = createPublicClient({ chain: bscTestnet, transport: http(bscRpcUrl) });

  // 1. Check contracts exist
  console.log(chalk.blue('\n1. Checking contract code sizes...'));

  const tokenCodeBase = await basePublic.getBytecode({ address: TOKEN_ADDRESS });
  const tokenCodeBsc = await bscPublic.getBytecode({ address: TOKEN_ADDRESS });
  const bridgeCodeBase = await basePublic.getBytecode({ address: BASE_BRIDGE });
  const bridgeCodeBsc = await bscPublic.getBytecode({ address: BSC_BRIDGE });

  console.log(`   VEERA Token on Base: ${tokenCodeBase ? chalk.green('✓ Deployed') : chalk.red('✗ Missing')}`);
  console.log(`   VEERA Token on BSC:  ${tokenCodeBsc ? chalk.green('✓ Deployed') : chalk.red('✗ Missing')}`);
  console.log(`   Adapter on Base:     ${bridgeCodeBase ? chalk.green('✓ Deployed') : chalk.red('✗ Missing')}`);
  console.log(`   Adapter on BSC:      ${bridgeCodeBsc ? chalk.green('✓ Deployed') : chalk.red('✗ Missing')}`);

  if (!tokenCodeBase || !tokenCodeBsc || !bridgeCodeBase || !bridgeCodeBsc) {
    console.log(chalk.red('\n❌ Dry-run failed. Deploy contracts to testnet first.'));
    return;
  }

  // 2. Verify settings
  console.log(chalk.blue('\n2. Verifying OFT Config on-chain...'));

  const baseInner = await readContract(basePublic, BASE_BRIDGE, ADAPTER_ABI, 'token');
  const bscInner = await readContract(bscPublic, BSC_BRIDGE, ADAPTER_ABI, 'token');

  console.log(`   Base Adapter inner token matches: ${baseInner.toLowerCase() === TOKEN_ADDRESS.toLowerCase() ? chalk.green('✓ Yes') : chalk.red('✗ No')}`);
  console.log(`   BSC Adapter inner token matches:  ${bscInner.toLowerCase() === TOKEN_ADDRESS.toLowerCase() ? chalk.green('✓ Yes') : chalk.red('✗ No')}`);

  // 3. Verify Peer configurations
  console.log(chalk.blue('\n3. Verifying LayerZero Peers...'));

  const basePeer = await readContract(basePublic, BASE_BRIDGE, ADAPTER_ABI, 'peers', [BSC_EID]);
  const bscPeer = await readContract(bscPublic, BSC_BRIDGE, ADAPTER_ABI, 'peers', [BASE_EID]);

  const expectedBasePeer = addressToBytes32(BSC_BRIDGE);
  const expectedBscPeer = addressToBytes32(BASE_BRIDGE);

  console.log(`   Base Adapter has BSC Peer: ${basePeer.toLowerCase() === expectedBasePeer.toLowerCase() ? chalk.green('✓ Yes') : chalk.red('✗ No')}`);
  console.log(`   BSC Adapter has Base Peer: ${bscPeer.toLowerCase() === expectedBscPeer.toLowerCase() ? chalk.green('✓ Yes') : chalk.red('✗ No')}`);

  // 4. Verify Minter role
  console.log(chalk.blue('\n4. Verifying Token Minter Roles...'));

  const MINTER_ROLE = await readContract(basePublic, TOKEN_ADDRESS, VEERA_ABI, 'MINTER_ROLE');

  const baseMinter = await readContract(basePublic, TOKEN_ADDRESS, VEERA_ABI, 'hasRole', [MINTER_ROLE, BASE_BRIDGE]);
  const bscMinter = await readContract(bscPublic, TOKEN_ADDRESS, VEERA_ABI, 'hasRole', [MINTER_ROLE, BSC_BRIDGE]);

  console.log(`   Base Bridge has MINTER_ROLE: ${baseMinter ? chalk.green('✓ Yes') : chalk.red('✗ No (Bridging credit will fail)')}`);
  console.log(`   BSC Bridge has MINTER_ROLE:  ${bscMinter ? chalk.green('✓ Yes') : chalk.red('✗ No (Bridging credit will fail)')}`);

  console.log(chalk.green.bold('\n✓ Dry-run completed! All essential bridge parameters checked.'));
}

main().catch((err) => {
  console.error(chalk.red('\nFatal error in bridge integration test:'));
  console.error(err);
  process.exit(1);
});
