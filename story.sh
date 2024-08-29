#!/bin/bash

# Check if the script is run as root user
if [ "$(id -u)" != "0" ]; then
    echo "This script needs to be run with root user privileges"
    echo "Please try to switch to the root user using 'sudo -i' command and then run this script again."
    exit 1
fi

# Install dependencies
function install_dependencies() {
    apt update && apt upgrade -y
    apt install curl wget jq make gcc nano -y
}

# Install Node.js and npm
function install_nodejs_and_npm() {
    if command -v node > /dev/null 2>&1; then
        echo "Node.js Installed, version: $(node -v)"
    else
        echo "Node.js Not installed, installing..."
        curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
    if command -v npm > /dev/null 2>&1; then
        echo "npm Installed, version: $(npm -v)"
    else
        echo "npm Not installed, installing..."
        sudo apt-get install -y npm
    fi
}

# Install PM2
function install_pm2() {
    if command -v pm2 > /dev/null 2>&1; then
        echo "PM2 Installed, version: $(pm2 -v)"
    else
        echo "PM2 is not installed, installing..."
        npm install pm2@latest -g
    fi
}

# Install the Story node
function install_story_node() {
    install_dependencies
    install_nodejs_and_npm
    install_pm2  # Make sure PM2 is installed

    echo "Start installing the Story node..."

    # Download the execution client and consensus client
    echo "Download the execution client and consensus client..."
    wget https://story-geth-binaries.s3.us-west-1.amazonaws.com/geth-public/geth-linux-amd64-0.9.2-ea9f0d2.tar.gz
    wget https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-0.9.11-2a25df1.tar.gz

    # Unzip the downloaded file
    tar -xzf geth-linux-amd64-0.9.2-ea9f0d2.tar.gz
    tar -xzf story-linux-amd64-0.9.11-2a25df1.tar.gz

    echo "The default data folder settings are:"
    echo "Story data root: ${STORY_DATA_ROOT}"
    echo "Geth Data Root: ${GETH_DATA_ROOT}"

    # Perform client setup
    echo "Setting up the execution client..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sudo xattr -rd com.apple.quarantine ./geth
    fi

    # Run the client using pm2
    cp /root/geth-linux-amd64-0.9.2-ea9f0d2/geth /usr/local/bin
    pm2 start /usr/local/bin/geth --name story-geth -- --iliad --syncmode full

    # Consensus Client Settings
    echo "Setting up the consensus client..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sudo xattr -rd com.apple.quarantine ./story
    fi

    # Initialize the consensus client
    cp /root/story-linux-amd64-0.9.11-2a25df1/story /usr/local/bin
    /usr/local/bin/story init --network iliad

    # Run the consensus client using pm2
    pm2 start /usr/local/bin/story --name story-client -- run

    echo "StoryNode installation complete!"
}

# Function to clear the state
function clear_state() {
    echo "Clear state and reinitialize node..."
    rm -rf ${GETH_DATA_ROOT} && pm2 start /usr/local/bin/geth --name story-geth -- --iliad --syncmode full
    rm -rf ${STORY_DATA_ROOT} && /usr/local/bin/story init --network iliad && pm2 start /usr/local/bin/story --name story-client -- run
}

# Function to check node status
function check_status() {
    echo "Checking Geth status..."
    pm2 logs story-geth
    pm2 logs story-client
}

# Check the .env file and read the private key
function check_env_file() {
    if [ -f ".env" ]; then
        # Read the .env file PRIVATE_KEY
        source .env
        echo "The .env file is loaded and the private key is: ${PRIVATE_KEY}"
    else
        # If the .env file does not exist, prompt the user for a private key
        read -p "Please enter your ETH wallet private key (make sure there is no 0x prefix): " PRIVATE_KEY
        # Create a .env file
        echo "# ~/story/.env" > .env
        echo "PRIVATE_KEY=${PRIVATE_KEY}" >> .env
        echo "The .env file has been created with the following content："
        cat .env
        echo "Please make sure that the account has obtained IP funds (refer to the tutorial page to obtain funds)."
    fi
}

# Set the validator function
function setup_validator() {
    echo "Setting up the validator..."
    # Check the .env file and read the private key
    check_env_file

    # Prompt user for authenticator operation
    echo "You can perform the following validator operations:"
    echo "1. Exporting the Validator Key"
    echo "2. Creating a New Validator"
    echo "3. Staking to an existing validator"
    echo "4. Cancel pledge"
    echo "5. Staking on behalf of other delegators"
    echo "6. Cancel the pledge on behalf of other delegators"
    echo "7. Add Operator"
    echo "8. Remove Operator"
    echo "9. Set the extraction address"
    read -p "Please enter options（1-9）: " OPTION

    case $OPTION in
    1) export_validator_key ;;
    2) create_validator ;;
    3) stake_to_validator ;;
    4) unstake_from_validator ;;
    5) stake_on_behalf ;;
    6) unstake_on_behalf ;;
    7) add_operator ;;
    8) remove_operator ;;
    9) set_withdrawal_address ;;
    *) echo "Invalid option" ;;
    esac
}

# Exporting the Validator Key
function export_validator_key() {
    echo "Exporting validator keys..."
    /usr/local/bin/story validator export
}

# Creating a New Validator
function create_validator() {
    read -p "Please enter the pledge amount (in IP): " AMOUNT_TO_STAKE_IN_IP
    AMOUNT_TO_STAKE_IN_WEI=$((AMOUNT_TO_STAKE_IN_IP * 1000000000000000000))
    /usr/local/bin/story validator create --stake ${AMOUNT_TO_STAKE_IN_WEI}
}

# Staking to an existing validator
function stake_to_validator() {
    read -p "Please enter the authenticator public key (Base64 format): " VALIDATOR_PUB_KEY_IN_BASE64
    read -p "Please enter the pledge amount (in IP): " AMOUNT_TO_STAKE_IN_IP
    AMOUNT_TO_STAKE_IN_WEI=$((AMOUNT_TO_STAKE_IN_IP * 1000000000000000000))
    /usr/local/bin/story validator stake --validator-pubkey ${VALIDATOR_PUB_KEY_IN_BASE64} --stake ${AMOUNT_TO_STAKE_IN_WEI}
}

# Cancel pledge
function unstake_from_validator() {
    read -p "Please enter the authenticator public key (Base64 format) : " VALIDATOR_PUB_KEY_IN_BASE64
    read -p "Please enter the amount to cancel the pledge (in IP units): " AMOUNT_TO_UNSTAKE_IN_IP
    AMOUNT_TO_UNSTAKE_IN_WEI=$((AMOUNT_TO_UNSTAKE_IN_IP * 1000000000000000000))
    /usr/local/bin/story validator unstake --validator-pubkey ${VALIDATOR_PUB_KEY_IN_BASE64} --unstake ${AMOUNT_TO_UNSTAKE_IN_WEI}
}

# Staking on behalf of other delegators
function stake_on_behalf() {
    read -p "Please enter the client's public key (Base64 format): " DELEGATOR_PUB_KEY_IN_BASE64
    read -p "Please enter the authenticator public key (Base64 format): " VALIDATOR_PUB_KEY_IN_BASE64
    read -p "Please enter the pledge amount (in IP): " AMOUNT_TO_STAKE_IN_IP
    AMOUNT_TO_STAKE_IN_WEI=$((AMOUNT_TO_STAKE_IN_IP * 1000000000000000000))
    /usr/local/bin/story validator stake-on-behalf --delegator-pubkey ${DELEGATOR_PUB_KEY_IN_BASE64} --validator-pubkey ${VALIDATOR_PUB_KEY_IN_BASE64} --stake ${AMOUNT_TO_STAKE_IN_WEI}
}

# Cancel the pledge on behalf of other delegators
function unstake_on_behalf() {
    read -p "Please enter the client's public key (Base64 format): " DELEGATOR_PUB_KEY_IN_BASE64
    read -p "Please enter the authenticator public key (Base64 format): " VALIDATOR_PUB_KEY_IN_BASE64
    read -p "Please enter the amount to cancel the pledge (in IP units): " AMOUNT_TO_UNSTAKE_IN_IP
    AMOUNT_TO_UNSTAKE_IN_WEI=$((AMOUNT_TO_UNSTAKE_IN_IP * 1000000000000000000))
    /usr/local/bin/story validator unstake-on-behalf --delegator-pubkey ${DELEGATOR_PUB_KEY_IN_BASE64} --validator-pubkey ${VALIDATOR_PUB_KEY_IN_BASE64} --unstake ${AMOUNT_TO_UNSTAKE_IN_WEI}
}

# Add Operator
function add_operator() {
    read -p "Please enter the operator's EVM address: " OPERATOR_EVM_ADDRESS
    /usr/local/bin/story validator add-operator --operator ${OPERATOR_EVM_ADDRESS}
}

# Remove Operator
function remove_operator() {
    read -p "Please enter the operator's EVM address: " OPERATOR_EVM_ADDRESS
    /usr/local/bin/story validator remove-operator --operator ${OPERATOR_EVM_ADDRESS}
}

# Set the extraction address
function set_withdrawal_address() {
    read -p "Please enter a new pickup address: " NEW_WITHDRAWAL_ADDRESS
    /usr/local/bin/story validator set-withdrawal-address --address ${NEW_WITHDRAWAL_ADDRESS}
}

# Main Menu
function main_menu() {
    clear
    echo "Welcome to WibuCrypto"
    echo "============================Story_Protocol===================================="
    echo "Telegram :https://t.me/wibuairdrop142"
    echo "Website :https://wibucrypto.pro/"
    echo "Youtube :https://www.youtube.com/@wibucrypto2201"
    echo "Discord :https://discord.gg/krCx2ssjGa"
    echo "Tiktok :https://www.tiktok.com/@waibucrypto"
    echo "Please select the action you want to perform:"
    echo "1. Install the Story node"
    echo "2. Clear state and reinitialize"
    echo "3. Checking Node Status"
    echo "4. Setting up the validator"
    echo "5. Quit"
    read -p "Please enter options（1-5）: " OPTION

    case $OPTION in
    1) install_story_node ;;
    2) clear_state ;;
    3) check_status ;;
    4) setup_validator ;;
    5) exit 0 ;;
    *) echo "Invalid option" ;;
    esac
}

# Show main menu
check_env_file  # Check .env file before main menu
main_menu
