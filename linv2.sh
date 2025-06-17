#!/bin/bash

export PATH=/bin:/usr/bin:/usr/local/bin:$PATH

set -e

SOCKS_ADDR="127.0.0.1"
SOCKS_PORT="2080"
WORK_DIR="/opt/xray-client"
XRAY_BIN="$WORK_DIR/xray"
CONFIG_FILE="$WORK_DIR/config.json"
PID_FILE="$WORK_DIR/xray.pid"

install_deps() {
    echo "[*] Installing dependencies..."
    for pkg in curl wget unzip jq; do
        if ! command -v $pkg &>/dev/null; then
            echo "Installing $pkg..."
            apt-get update -y && apt-get install -y $pkg
        fi
    done
}

install_xray() {
    echo "[*] Installing Xray-core..."
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    if [ -f "Xray-linux-64.zip" ]; then
        echo "[*] Xray-linux-64.zip already exists, skipping download and install. for update run ./linv2.sh update"
        return
    fi

    LATEST=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name')
    FILE="Xray-linux-64.zip"
    wget -q "https://github.com/XTLS/Xray-core/releases/download/${LATEST}/${FILE}" -O "$FILE"
    unzip -o "$FILE"
    chmod +x xray
}

update_xray() {
    echo "[*] Updating Xray-core..."
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    rm Xray-linux-64.zip

    LATEST=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name')
    FILE="Xray-linux-64.zip"
    wget -q "https://github.com/XTLS/Xray-core/releases/download/${LATEST}/${FILE}" -O "$FILE"
    unzip -o "$FILE"
    chmod +x xray
}



parse_vless_uri() {
    URI="$1"
    SOCKS_PORT="$2"
    echo "[*] Parsing VLESS URI..."

    FULL=${URI#vless://}
    UUID=${FULL%%@*}
    FULL=${FULL#*@}
    HOST_PORT=${FULL%%\?*}
    QUERY_FRAGMENT=${FULL#*\?}
    HOST=${HOST_PORT%%:*}
    PORT=${HOST_PORT##*:}
    QUERY=${QUERY_FRAGMENT%%#*}

    TYPE="tcp"
    PATH="/"
    HOST_HEADER=""
    ENCRYPTION="none"

    IFS='&' read -ra PARAMS <<< "$QUERY"
    for param in "${PARAMS[@]}"; do
        KEY=${param%%=*}
        VALUE=${param#*=}
        case "$KEY" in
            type) TYPE="$VALUE" ;;
            path) PATH=$(printf '%b' "${VALUE//%/\\x}") ;;
            host) HOST_HEADER="$VALUE" ;;
            encryption) ENCRYPTION="$VALUE" ;;
        esac
    done

    /bin/cat > "$CONFIG_FILE" <<EOF
{
    "dns": {
        "disableFallback": true,
        "servers": [
            {
                "address": "https://8.8.8.8/dns-query",
                "domains": [],
                "queryStrategy": ""
            },
            {
                "address": "localhost",
                "domains": [],
                "queryStrategy": ""
            }
        ],
        "tag": "dns"
    },
    "inbounds": [
        {
            "listen": "$SOCKS_ADDR",
            "port": $SOCKS_PORT,
            "protocol": "socks",
            "settings": {
                "udp": true
            },
            "sniffing": {
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ],
                "enabled": true,
                "metadataOnly": false,
                "routeOnly": true
            },
            "tag": "socks-in"
        },
        {
            "listen": "$SOCKS_ADDR",
            "port": $(($SOCKS_PORT + 1)),
            "protocol": "http",
            "sniffing": {
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ],
                "enabled": true,
                "metadataOnly": false,
                "routeOnly": true
            },
            "tag": "http-in"
        }
    ],
    "log": {
        "loglevel": "warning"
    },
    "outbounds": [
        {
            "domainStrategy": "AsIs",
            "flow": null,
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": "$HOST",
                        "port": $PORT,
                        "users": [
                            {
                                "id": "$UUID",
                                "encryption": "$ENCRYPTION",
                                "flow": ""
                            }
                        ]
                    }
                ]
            },
            "streamSettings": {
                "network": "$TYPE",
                "wsSettings": {
                    "headers": {
                        "Host": "$HOST_HEADER"
                    },
                    "path": "$PATH"
                }
            },
            "tag": "proxy"
        },
        {
            "domainStrategy": "",
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "domainStrategy": "",
            "protocol": "freedom",
            "tag": "bypass"
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        },
        {
            "protocol": "dns",
            "proxySettings": {
                "tag": "proxy",
                "transportLayer": true
            },
            "settings": {
                "address": "8.8.8.8",
                "network": "tcp",
                "port": 53,
                "userLevel": 1
            },
            "tag": "dns-out"
        }
    ],
    "policy": {
        "levels": {
            "1": {
                "connIdle": 30
            }
        },
        "system": {
            "statsOutboundDownlink": true,
            "statsOutboundUplink": true
        }
    },
    "routing": {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "inboundTag": [
                    "socks-in",
                    "http-in"
                ],
                "outboundTag": "dns-out",
                "port": "53",
                "type": "field"
            },
            {
                "outboundTag": "proxy",
                "port": "0-65535",
                "type": "field"
            }
        ]
    },
    "stats": {}
}
EOF
}


run_xray() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(/bin/cat "$PID_FILE")" 2>/dev/null; then
        echo "[*] Xray is already running with PID $(/bin/cat "$PID_FILE")"
        exit 0
    fi

    echo "[*] Starting Xray..."
    "$XRAY_BIN" run -config "$CONFIG_FILE" > /dev/null 2>&1 &
    echo $! > "$PID_FILE"
    echo "[*] Xray started with PID $(/bin/cat "$PID_FILE")"
}


stop_xray() {
    if [[ -f "$PID_FILE" ]]; then
        PID=$(/bin/cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo "[*] Stopping Xray (PID $PID)..."
            kill "$PID"
            rm -f "$PID_FILE"
            echo "[*] Xray stopped."
        else
            echo "[!] PID file exists but process not running. Cleaning up..."
            rm -f "$PID_FILE"
        fi
    else
        echo "[*] Xray is not running."
    fi
    exit 0
}

usage() {
    echo "Usage:"
    echo "  $0 -vless <vless_uri> [-socksPort <port>]"
    echo "  $0 update"
    echo "  $0 stop"
    exit 1
}


if [[ "$1" == "stop" ]]; then
    stop_xray
fi

if [[ "$1" == "update" ]]; then
    update_xray
fi

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -vless)
        VLESS_URI="$2"
        shift; shift
        ;;
        -socksPort)
        SOCKS_PORT="$2"
        shift; shift
        ;;
        *)
        usage
        ;;
    esac
done

if [[ -z "$VLESS_URI" ]]; then
    usage
fi

install_deps
install_xray
cd "$WORK_DIR"
parse_vless_uri "$VLESS_URI" "$SOCKS_PORT"
run_xray
