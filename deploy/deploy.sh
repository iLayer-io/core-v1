#!/bin/bash
# deploy.sh

CONFIG_FILE="config.yaml"

GLOBAL_OWNER=$(yq e '.global.owner' "$CONFIG_FILE")
GLOBAL_OWNER_PRIVATE_KEY=$(yq e '.global.ownerPrivateKey' "$CONFIG_FILE")
GLOBAL_TRUSTED_FORWARDER=$(yq e '.global.trustedForwarder' "$CONFIG_FILE")
GLOBAL_MAX_DEADLINE=$(yq e '.global.maxDeadline' "$CONFIG_FILE")
GLOBAL_WITHDRAW_TIME_BUFFER=$(yq e '.global.withdrawTimeBuffer' "$CONFIG_FILE")
GLOBAL_SALT=$(yq e '.global.salt' "$CONFIG_FILE")

export OWNER="$GLOBAL_OWNER"
export OWNER_PRIVATE_KEY="$GLOBAL_OWNER_PRIVATE_KEY"
export TRUSTED_FORWARDER="$GLOBAL_TRUSTED_FORWARDER"
export MAX_DEADLINE="$GLOBAL_MAX_DEADLINE"
export WITHDRAW_TIME_BUFFER="$GLOBAL_WITHDRAW_TIME_BUFFER"
export SALT="$GLOBAL_SALT"

chain_count=$(yq e '.chains | length' "$CONFIG_FILE")

for (( i=0; i<chain_count; i++ )); do
    CHAIN_ROUTER=$(yq e ".chains[$i].router" "$CONFIG_FILE")
    export ROUTER="$CHAIN_ROUTER"

    CHAIN_NAME=$(yq e ".chains[$i].name" "$CONFIG_FILE")
    CHAIN_RPC=$(yq e ".chains[$i].rpc" "$CONFIG_FILE")

    remote_endpoints=()
    for (( j=0; j<chain_count; j++ )); do
        chain_name_j=$(yq e ".chains[$j].name" "$CONFIG_FILE")
        if [ "$chain_name_j" == "$CHAIN_NAME" ]; then
            continue
        fi
        endpoint_j=$(yq e ".chains[$j].endpointId" "$CONFIG_FILE")
        remote_endpoints+=("$endpoint_j")
    done

    remote_count=${#remote_endpoints[@]}
    export REMOTE_ENDPOINT_COUNT="$remote_count"

    for (( k=0; k<remote_count; k++ )); do
        varname="REMOTE_ENDPOINT_$k"
        export $varname="${remote_endpoints[$k]}"
    done

    echo "Deploy Hub e Spoke su $CHAIN_NAME con $remote_count remote peers."

    export RPC_URL="$CHAIN_RPC"

    forge script ../script/DeployToMainnet.s.sol --rpc-url "$CHAIN_RPC" --broadcast --slow --skip-simulation --private-key "$OWNER_PRIVATE_KEY" --sender "$OWNER"
done

echo "Deploy completato su tutte le chain."
