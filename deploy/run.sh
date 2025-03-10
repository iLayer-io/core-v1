#!/bin/bash
# run.sh

CONFIG_FILE="config.yaml"

# Ensure PRIVATE_KEY is set
if [ -z "$PRIVATE_KEY" ]; then
  echo "Error: PRIVATE_KEY environment variable is not set."
  exit 1
fi

# Get the number of chains from config.yaml
chain_count=$(yq e '.chains | length' "$CONFIG_FILE")

# Export remote chain IDs for all chains from the config file
REMOTE_CHAIN_COUNT=$chain_count
export REMOTE_CHAIN_COUNT
for (( j=0; j<chain_count; j++ )); do
  remoteId=$(yq e ".chains[$j].remoteChainId" "$CONFIG_FILE")
  export REMOTE_CHAIN_ID_${j}=$remoteId
done

# Iterate over each chain configuration and deploy
for (( i=0; i<chain_count; i++ )); do
    NAME=$(yq e ".chains[$i].name" "$CONFIG_FILE")
    RPC=$(yq e ".chains[$i].rpc" "$CONFIG_FILE")
    ENDPOINT_ADDRESS=$(yq e ".chains[$i].endpointAddress" "$CONFIG_FILE")
    SEND_LIBRARY=$(yq e ".chains[$i].sendLibrary" "$CONFIG_FILE")
    RECEIVE_LIBRARY=$(yq e ".chains[$i].receiveLibrary" "$CONFIG_FILE")
    
    ULN_CONFIRMATIONS=$(yq e ".chains[$i].uln.confirmations" "$CONFIG_FILE")
    ULN_REQUIRED_DVN_COUNT=$(yq e ".chains[$i].uln.requiredDVNCount" "$CONFIG_FILE")
    ULN_OPTIONAL_DVN_COUNT=$(yq e ".chains[$i].uln.optionalDVNCount" "$CONFIG_FILE")
    ULN_OPTIONAL_DVN_THRESHOLD=$(yq e ".chains[$i].uln.optionalDVNThreshold" "$CONFIG_FILE")
    ULN_REQUIRED_DVN_0=$(yq e ".chains[$i].uln.requiredDVNs[0]" "$CONFIG_FILE")
    ULN_REQUIRED_DVN_1=$(yq e ".chains[$i].uln.requiredDVNs[1]" "$CONFIG_FILE")
    
    EXECUTOR_ADDRESS=$(yq e ".chains[$i].executor.executorAddress" "$CONFIG_FILE")
    EXECUTOR_MAX_MESSAGE_SIZE=$(yq e ".chains[$i].executor.maxMessageSize" "$CONFIG_FILE")

    # Export these variables for the Forge scripts to use
    export ENDPOINT_ADDRESS
    export SEND_LIBRARY
    export RECEIVE_LIBRARY
    export ULN_CONFIRMATIONS
    export ULN_REQUIRED_DVN_COUNT
    export ULN_OPTIONAL_DVN_COUNT
    export ULN_OPTIONAL_DVN_THRESHOLD
    export ULN_REQUIRED_DVN_0
    export ULN_REQUIRED_DVN_1
    export EXECUTOR_ADDRESS
    export EXECUTOR_MAX_MESSAGE_SIZE

    echo "Deploying CREATE3Factory on $NAME using RPC $RPC..."
    # Deploy CREATE3Factory and capture its deployed address from output
    CREATE3_FACTORY=$(forge script script/DeployCreate3Factory.s.sol --rpc-url "$RPC" --broadcast --private-key "$PRIVATE_KEY" | grep "Deployed CREATE3Factory at:" | awk '{print $NF}')
    if [ -z "$CREATE3_FACTORY" ]; then
        echo "Error: Failed to deploy CREATE3Factory on $NAME."
        exit 1
    fi
    export CREATE3_FACTORY

    echo "Deploying OrderHub-Spoke on $NAME using RPC $RPC..."
    forge script script/DeployHubSpoke.s.sol --rpc-url "$RPC" --broadcast --private-key "$PRIVATE_KEY"
done
