# TON-SDK utility scripts

Scripts for automatically releasing TON-SDK client libraries for .NET and PHP.

## Prerequisites

* NodeJS v14+
* npm v6+
* git
* gh (GitHub CLI)
* .NET SDK 3.1+
* PHP 7.4+
* composer 2+

## Installation

### Log in into GitHub

```bash
gh auth login
```

### Clone repositories

```bash
gh repo clone https://github.com/andy-a-o/ton-sdk-scripts
gh repo clone https://github.com/radianceteam/ton-client-php
gh repo clone https://github.com/radianceteam/ton-client-php-ext
gh repo clone https://github.com/radianceteam/ton-client-dotnet
gh repo clone https://github.com/radianceteam/ton-client-dotnet-bridge
gh repo clone https://github.com/tonlabs/TON-SDK
```

## Running scripts

First, change to the `ton-sdk-scripts` directory:

```bash
cd ton-sdk-scripts
```

In the common case, run `./ton-sdk.sh help` to see the complete list of commands and options.

### All-in-one script

To upgrade to a specific SDK version, run this script:

```bash
./ton-sdk.sh update -t <SDK VERSION TAG> 
```

In case of any failures, you could re-run any part of the script using commands below.

### Running NodeSE locally

This is helpful for example for running tests locally.

```bash
./ton-sdk.sh run
```

NOTE: it's recommended to wait at least 20 seconds to ensure NodeSE is up and ready for new requests.

### Building SDK for specific version (tag)

#### Binaries only

```bash
./ton-sdk.sh binaries -t <VERSION TAG> -w -d ../binaries
```

#### Upgrade .NET SDK

```bash
./ton-sdk.sh dotnet -t <VERSION TAG> -w
```

#### Upgrade PHP extension

TBD

#### Upgrade PHP SDK

TBD

## Links

- [TON SDK Client Library](https://github.com/tonlabs/TON-SDK)
- [TON SDK PHP Extension](https://github.com/radianceteam/ton-client-php-ext)
- [TON SDK PHP Wrapper](https://github.com/radianceteam/ton-client-php)
- [TON SDK .NET Wrapper](https://github.com/radianceteam/ton-client-dotnet)
- [TON SDK binaries helper project](https://github.com/radianceteam/ton-client-dotnet-bridge)
- [GitHub CLI Manual](https://cli.github.com/manual/)
