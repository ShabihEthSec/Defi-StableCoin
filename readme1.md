1. Relative Stability: Anchored or pegged -> $1.00
   1. Chainlink price feed.
   2. Set a function to exchange ETH & BTC -> $$$
2. Stability Mechanism (Minting): Algorithmic (Decentralized)
   1. People can only mint  the stablecoin with enough collateral (coded) 
3. Collateral (Crypto)
   1. wETH (wrapped ETH or ERC20 version of Eth)
   2. wBTC (wrapped BTC or ERC20 version of BTC)


1. What are our invariant/properties?
   - Invariant: The Properties of the system that should always hold.

   - Two popular methodologies to find these edge cases: 1. Fuzz/Invariant Test
                                                         2. Symbolic Execution/ Formal Verification
      Semi-Random = Random

1. Some proper oracle use
2. Write more tests
3. Smart Contract Audit

* Points to Remember: 
      1. Understand Our Invariants
      2. Write a fuzz test for Invariant

   - Fuzzing: 
         - Stateless Fuzzing: Where the state of previous run is discarded for every new run. 
         - Stateful Fuzzing:Fuzzing where the final state of your previous run is the starting state of your next run.
     * Foundry "Invariant" tests == Stateful Fuzzing 
     * Should Import {StdInvariant} from "forge-std/StdInvariant.sol"   
     * Foundry automatically randomizes both inputs and function call sequences when testing invariants.
     * You define invariants in test functions, and Foundry ensures they are checked after fuzzing each sequence of calls.
     * If you need granular control, you can write custom sequences or integrate additional randomness logic.

## In Foundry:
   - Fuzz Tests: Random data to one function
   - Invariant Tests: Random data & Random Function Calls to many Functions
                                 OR
   - Foundry Fuzzing = Stateless Fuzzing
   - Foundry Invariant = Stateful Fuzzing  
  
### Practical Examples Of Invariants: 
   - New Tokens minted < inflation rate
   - Only possible to have 1 winner  in a lottery
   - Only withdraw what they deposit
  # 1. Understand what the invariants are
  # 2. Write functions that can execute them


----------------------------------------------------------------------------------------------------------------------------------------------------

# Handler Base testing:    