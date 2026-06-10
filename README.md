# Veera Token (`$VEERA`)

This repository contains the smart contracts for the **Veera Token**, a standardized, secure, and deterministic ERC20 implementation with access control, capping, pause capability, and permit support. It is built using [Foundry](https://getfoundry.sh/) and [OpenZeppelin](https://www.openzeppelin.com/) standards.

The repository also contains an OFT bridge adapter implementation for cross chain native token transfer using [LayerZero](https://layerzero.network/).

The architecture is designed with **security** and **future interoperability** (cross-chain native bridging) in mind.

## Info

* [CoinGecko](https://www.coingecko.com/en/coins/veera)
* [CoinMarketCap](https://coinmarketcap.com/currencies/veera/)

| Contract | Chain | Address |
| :--- | :--- | :--- |
| Token | Base | [0x6e398a93eAcc13CBCb3e9a7c7a0B73821220E532](https://basescan.org/address/0x6e398a93eAcc13CBCb3e9a7c7a0B73821220E532) |
| Token | BSC | [0x6e398a93eAcc13CBCb3e9a7c7a0B73821220E532](https://bscscan.com/address/0x6e398a93eAcc13CBCb3e9a7c7a0B73821220E532) |
| Token | Base Sepolia | [0x6e398a93eAcc13CBCb3e9a7c7a0B73821220E532](https://sepolia.basescan.org/address/0x6e398a93eAcc13CBCb3e9a7c7a0B73821220E532) |
| Token | BSC Testnet | [0x6e398a93eAcc13CBCb3e9a7c7a0B73821220E532](https://testnet.bscscan.com/address/0x6e398a93eAcc13CBCb3e9a7c7a0B73821220E532) |
| Bridge | Base | [0x3BD842cf30a6B21F177C2D59436698F44bf3E2F8](https://basescan.org/address/0x3BD842cf30a6B21F177C2D59436698F44bf3E2F8) |
| Bridge | BSC | [0x3BD842cf30a6B21F177C2D59436698F44bf3E2F8](https://bscscan.com/address/0x3BD842cf30a6B21F177C2D59436698F44bf3E2F8) |
| Bridge | Base Sepolia | [0x812bbd935209dC60cb4B249fc24cF7FD31AeC102](https://sepolia.basescan.org/address/0x812bbd935209dC60cb4B249fc24cF7FD31AeC102) |
| Bridge | BSC Testnet | [0x51B58210055f72D9843bdeBC6Deb33b5E9B7F61E](https://testnet.bscscan.com/address/0x51B58210055f72D9843bdeBC6Deb33b5E9B7F61E) |

## Documentation

* [Token](docs/token.md)
* [Bridge](docs/bridge.md)

## Audits

* [Token](audits/token-contract-audit-report-Octane.pdf)
* [Bridge](audits/bridge-contract-audit-report-Hashlock.pdf)