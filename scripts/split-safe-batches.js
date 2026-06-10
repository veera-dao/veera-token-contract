const fs = require('fs');
const path = require('path');

if (process.argv.length < 3) {
  console.error('❌ Error: Missing input file argument.');
  console.error('Usage: node scripts/split-safe-batches.js <input-file-path>');
  console.error('Example: node scripts/split-safe-batches.js safe-batch-testnet-wire.json');
  process.exit(1);
}

const inputArg = process.argv[2];
const srcFile = path.resolve(process.cwd(), inputArg);

if (!fs.existsSync(srcFile)) {
  console.error(`❌ Error: Source file not found at ${srcFile}`);
  process.exit(1);
}

let rawTxs;
try {
  rawTxs = JSON.parse(fs.readFileSync(srcFile, 'utf8'));
} catch (err) {
  console.error(`❌ Error parsing JSON from ${srcFile}:`, err.message);
  process.exit(1);
}

if (!Array.isArray(rawTxs)) {
  console.error('❌ Error: Input JSON must be an array of transactions.');
  process.exit(1);
}

// Define the networks mapping
const NETWORKS = {
  'BASE_V2_MAINNET': {
    suffix: '-base',
    chainId: '8453',
    name: 'Base Safe Batch'
  },
  'BSC_V2_MAINNET': {
    suffix: '-bsc',
    chainId: '56',
    name: 'BSC Safe Batch'
  },
  'BASESEP_V2_TESTNET': {
    suffix: '-base-sepolia',
    chainId: '84532',
    name: 'Base Sepolia Safe Batch'
  },
  'BSC_V2_TESTNET': {
    suffix: '-bsc-testnet',
    chainId: '97',
    name: 'BSC Testnet Safe Batch'
  }
};

// Initialize transaction groups
const groups = {};
for (const endpoint of Object.keys(NETWORKS)) {
  groups[endpoint] = [];
}

// Group transactions
for (const tx of rawTxs) {
  const endpoint = tx.Endpoint;
  if (!endpoint) {
    console.warn('⚠️ Warning: Transaction missing Endpoint field, skipping:', tx);
    continue;
  }

  if (!NETWORKS[endpoint]) {
    console.warn(`⚠️ Warning: Unknown endpoint '${endpoint}', skipping transaction:`, tx);
    continue;
  }

  groups[endpoint].push({
    to: tx.OmniAddress,
    value: "0",
    data: tx.Data,
    contractMethod: null,
    contractInputsValues: null
  });
}

const makeSafeBatch = (chainId, name, transactions) => ({
  version: "1.0",
  chainId: chainId,
  meta: {
    name: name,
    description: `LayerZero OApp configurations for ${name}`,
    txBuilderVersion: "1.16.5",
    createdFromSafeAddress: ""
  },
  transactions
});

const inputDir = path.dirname(srcFile);
const inputExt = path.extname(srcFile);
const inputBase = path.basename(srcFile, inputExt);

console.log(`Successfully parsed ${rawTxs.length} transactions from ${path.basename(srcFile)}:`);

for (const [endpoint, txs] of Object.entries(groups)) {
  if (txs.length === 0) continue;

  const config = NETWORKS[endpoint];
  const batch = makeSafeBatch(config.chainId, config.name, txs);
  let outFileName = `${inputBase}${config.suffix}${inputExt}`;
  let outFilePath = path.join(inputDir, outFileName);
  let counter = 1;

  while (fs.existsSync(outFilePath)) {
    outFileName = `${inputBase}${config.suffix}-${counter}${inputExt}`;
    outFilePath = path.join(inputDir, outFileName);
    counter++;
  }

  fs.writeFileSync(outFilePath, JSON.stringify(batch, null, 2));
  console.log(`- ${config.name} (${endpoint}): ${txs.length} transactions saved to ${path.relative(process.cwd(), outFilePath)}`);
}
