# Veera ERC20 Token

## Token Specs
- Name: Veera
- Symbol: VEERA
- Initial supply: 1,000,000,000 VEERA (1_000_000_000 ether)
- Features: burnable, pausable, permit (EIP-2612), and owner-only minting

## Deploy
1. Set the required environment variables (override the defaults only if needed):
   ```bash
   export TOKEN_OWNER=0xYourOwnerAddress        # required
   export TOKEN_NAME="Veera"                    # optional override
   export TOKEN_SYMBOL="VEERA"                  # optional override
   export TOKEN_INITIAL_SUPPLY=1000000000e18    # optional override
   export RPC_URL=https://your.rpc.url
   ```
2. Create secure deployment keys and deploy:
   ```bash
   ./scripts/generate-keystore.sh
   ./scripts/deploy.sh
   ```
   These scripts will create password protected deployer keys, and use them to securely deploy the token.

## Development
- Build: `forge build`
- Test: `forge test`
- Format: `forge fmt`

## Project Structure
- `src/BaseERC20.sol`: Veera token implementation.
- `script/DeployBaseERC20.s.sol`: Deployment script with Veera defaults.
- `test/`: Foundry unit tests.
