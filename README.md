# Xray Client Auto Installer and Runner

A simple and efficient Bash script to install, update, configure, and run the [Xray-core](https://github.com/XTLS/Xray-core) client on Linux systems. The script automatically parses a VLESS URI to generate the JSON config file, sets up SOCKS5 and HTTP inbound proxies, and manages the Xray process lifecycle.

---

## 🔧 Installation

To install and run the script:

```bash
curl -fsSL -o linv2.sh https://raw.githubusercontent.com/yxnjm/linv2/main/linv2.sh
chmod +x linv2.sh
```

---

## Features

- Automatically installs required dependencies (`curl`, `wget`, `unzip`, `jq`) if missing.
- Downloads and installs the latest Xray-core binary for Linux (64-bit).
- Supports updating the Xray-core to the latest release.
- Parses a VLESS URI string to generate a fully working JSON configuration.
- Provides SOCKS5 and HTTP inbound proxies with configurable ports.
- Routes DNS queries through the VLESS proxy.
- Manages starting and stopping Xray with PID file tracking.
- Lightweight and easy to use.
- Supports advanced VLESS configurations including WebSocket (`ws`) and XTLS over HTTP (`xhttp` / Reality).

---

## Requirements

- Linux x86_64 system
- Bash shell
- Root or sudo privileges for installing dependencies
- VLESS URI (supports type=ws and type=xhttp with Reality)

---

## Usage

```bash
# Basic usage with a VLESS URI (replace with your actual URI)
./linv2.sh -vless "vless://UUID@host:port?type=ws&path=%2Fwebsocket&host=example.com" [-socksPort 2080]

# Update Xray-core to the latest version
./linv2.sh update

# Stop the running Xray process
./linv2.sh stop
```
