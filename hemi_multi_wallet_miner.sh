#!/bin/bash

ARCH=$(uname -m)
WALLET_DIR="$HOME/hemi_wallets"
LOG_DIR="$HOME/hemi_logs"

show() {
    echo -e "\033[1;35m$1\033[0m"
}

# Check and install jq if not present
if ! command -v jq &> /dev/null; then
    show "jq not found, installing..."
    sudo apt-get update
    sudo apt-get install -y jq > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        show "Failed to install jq. Please check your package manager."
        exit 1
    fi
fi

# Function to check latest version
check_latest_version() {
    for i in {1..3}; do
        LATEST_VERSION=$(curl -s https://api.github.com/repos/hemilabs/heminetwork/releases/latest | jq -r '.tag_name')
        if [ -n "$LATEST_VERSION" ]; then
            show "Latest version available: $LATEST_VERSION"
            return 0
        fi
        show "Attempt $i: Failed to fetch the latest version. Retrying..."
        sleep 2
    done

    show "Failed to fetch the latest version after 3 attempts. Please check your internet connection or GitHub API limits."
    exit 1
}

check_latest_version

# Download and extract if necessary
download_and_extract() {
    if [ "$ARCH" == "x86_64" ]; then
        ARCH_DIR="heminetwork_${LATEST_VERSION}_linux_amd64"
        TARBALL="heminetwork_${LATEST_VERSION}_linux_amd64.tar.gz"
    elif [ "$ARCH" == "arm64" ]; then
        ARCH_DIR="heminetwork_${LATEST_VERSION}_linux_arm64"
        TARBALL="heminetwork_${LATEST_VERSION}_linux_arm64.tar.gz"
    else
        show "Unsupported architecture: $ARCH"
        exit 1
    fi

    if [ ! -d "$ARCH_DIR" ]; then
        show "Downloading for $ARCH architecture..."
        wget --quiet --show-progress "https://github.com/hemilabs/heminetwork/releases/download/$LATEST_VERSION/$TARBALL" -O "$TARBALL"
        tar -xzf "$TARBALL" > /dev/null
    else
        show "Latest version for $ARCH is already downloaded. Skipping download."
    fi

    cd "$ARCH_DIR" || { show "Failed to change directory."; exit 1; }
}

download_and_extract

# Create necessary directories
mkdir -p "$WALLET_DIR" "$LOG_DIR"

# Function to generate a new wallet
generate_wallet() {
    local wallet_number=$1
    local wallet_file="$WALLET_DIR/wallet_$wallet_number.json"
    
    ./keygen -secp256k1 -json -net="testnet" > "$wallet_file"
    if [ $? -ne 0 ]; then
        show "Failed to generate wallet $wallet_number."
        return 1
    fi
    
    show "Wallet $wallet_number generated and saved to $wallet_file"
    cat "$wallet_file"
    echo
    
    local pubkey_hash=$(jq -r '.pubkey_hash' "$wallet_file")
    show "Join: https://discord.gg/hemixyz"
    show "Request faucet from faucet channel to this address: $pubkey_hash"
    echo
    
    read -p "Have you requested faucet for wallet $wallet_number? (y/N): " faucet_requested
    if [[ ! "$faucet_requested" =~ ^[Yy]$ ]]; then
        show "Please request faucet before continuing."
        return 1
    fi
    
    return 0
}

# Function to create and start a service for a wallet
create_and_start_service() {
    local wallet_number=$1
    local wallet_file="$WALLET_DIR/wallet_$wallet_number.json"
    local priv_key=$(jq -r '.private_key' "$wallet_file")
    
    read -p "Enter static fee for wallet $wallet_number (numerical only, recommended: 100-200): " static_fee
    echo

    local service_name="hemi_wallet_$wallet_number.service"
    local log_file="$LOG_DIR/hemi_wallet_$wallet_number.log"

    cat << EOF | sudo tee "/etc/systemd/system/$service_name" > /dev/null
[Unit]
Description=Hemi Network popmd Service for Wallet $wallet_number
After=network.target

[Service]
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/popmd
Environment="POPM_BTC_PRIVKEY=$priv_key"
Environment="POPM_STATIC_FEE=$static_fee"
Environment="POPM_BFG_URL=wss://testnet.rpc.hemi.network/v1/ws/public"
Restart=on-failure
StandardOutput=append:$log_file
StandardError=append:$log_file

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "$service_name"
    sudo systemctl start "$service_name"
    
    show "Service $service_name started for wallet $wallet_number. Logs will be saved to $log_file"
}

view_logs() {
    local wallet_number=$1
    local log_file="$LOG_DIR/hemi_wallet_$wallet_number.log"
    
    if [ -f "$log_file" ]; then
        tail -f "$log_file"
    else
        show "Log file for wallet $wallet_number not found."
    fi
}

# Main loop for wallet creation and service start
wallet_count=0
while true; do
    echo
    show "1. Create a new wallet and start mining"
    show "2. View logs for an existing wallet"
    show "3. Exit"
    read -p "Choose an option (1/2/3): " choice
    
    case $choice in
        1)
            wallet_count=$((wallet_count + 1))
            show "Creating wallet $wallet_count"
            if generate_wallet $wallet_count; then
                create_and_start_service $wallet_count
            else
                wallet_count=$((wallet_count - 1))
            fi
            ;;
        2)
            read -p "Enter wallet number to view logs: " log_wallet
            view_logs $log_wallet
            ;;
        3)
            break
            ;;
        *)
            show "Invalid option. Please try again."
            ;;
    esac
done

show "PoP mining successfully started for $wallet_count wallet(s)"
show "You can check the logs for each wallet in the $LOG_DIR directory"
