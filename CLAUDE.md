# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FairplayMP is a secure multi-party computation (SMPC) platform implementing the BGW (Ben-Or, Goldwasser, Wigderson) protocol. It allows multiple parties to jointly compute functions over private inputs without revealing those inputs to each other.

**Important**: FairplayMP requires multiple physical/virtual machines to run the protocol.

## Build Commands

Build system uses Apache Ant 1.8+. All commands run from `runtime/` directory:

```bash
cd runtime

# Full build (clean, compile, jar, junit)
ant

# Individual targets
ant clean           # Remove build artifacts
ant compile         # Compile Java sources
ant jar             # Create libfpmp.jar
ant junit           # Run JUnit tests
```

Output:
- `runtime/build/classes/` - Compiled bytecode
- `runtime/build/jar/libfpmp.jar` - Packaged library

## SFDL Compilation (Circuit Generation)

SFDL (Secure Function Definition Language) programs must be compiled to circuits before execution.

**Using v2 compiler** (recommended):
```bash
java -cp compiler_v2_built/ sfdl.Compiler sfdl/SecondPriceAuction.sfdl
```

**Using v1 compiler**:
```bash
cp sfdl/SecondPriceAuction.sfdl compiler_v1_built/SecondPriceAuction-tocompile.sfdl
cd compiler_v1_built/compiler
java lab.Runner -f ../SecondPriceAuction-tocompile.sfdl
cd ..
ruby Convertor.rb SecondPriceAuction-tocompile.sfdl
mv *.cnv *.Opt.circuit *.Opt.fmt ..
```

Generates: `.cnv`, `.Opt.circuit`, `.Opt.fmt` files

## Running the Protocol

```bash
java -cp runtime/build/classes FairplayMP <randomSeed>
java -cp runtime/build/classes FairplayMP <randomSeed> Test <input>  # Test mode with injected input
```

For multi-machine deployment using Multipass VMs:
```bash
./scripts/deploy-multipass.sh [SEED] [--setup-only|--run-only]
```

## Architecture

### Three Player Types
- **InputPlayer (IP)**: Provides secret inputs to the computation
- **ComputationPlayer (CP)**: Performs secure computation (requires odd number, typically 5)
- **ResultPlayer (RP)**: Receives computation outputs

### Core Components (`runtime/src/`)
- `FairplayMP.java` - Main entry point, orchestrates player types
- `BGW/BGW.java` - Threshold cryptography (Shamir secret sharing, share/reshare/reconstruct)
- `players/` - Player implementations (Player, InputPlayer, ComputationPlayer, ResultPlayer)
- `communication/` - SSL-encrypted message passing (Client, Server, Messages, CPMsgs)
- `circuit/` - Boolean circuit representation and evaluation
- `config/` - XML configuration parsing

### Security Model
- BGW protocol with threshold = ⌊(n-1)/2⌋ (tolerates minority corruption)
- SSL/TLS for inter-party communication
- Modular arithmetic with large primes (p ≡ 3 mod 4)

## Configuration

Edit `config.xml` to configure:
- Circuit file to compute
- Player IP addresses and roles (bidder[0], bidder[1], etc.)
- Computation player IPs (comma-separated)
- Security parameters: port, K (security bits), modulo (large prime)
- SSL certificates (keystore/truststore paths and passwords)

## Example Protocols

- `sfdl/SecondPriceAuction.sfdl` - 4 bidders + seller auction
- `sfdl/Millionaires.sfdl` - 3 parties comparing wealth
- `sfdl/Voting.sfdl` - Simple voting protocol
