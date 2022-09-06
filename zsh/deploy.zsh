#!/bin/zsh
PATH=$PATH:/bin/:/usr/bin:/usr/local/bin

canister=${1:-staking_pool}
network=${2:-local}
wallet=${3}

# Confirm before deploying to mainnet
if [[ $network != "local" ]]
then
    echo "Confirm mainnet launch"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) break;;
            No ) exit;;
        esac
    done
fi

# Get or create canister ID
canister_id=
canisters_json="./canister_ids.json" && [[ $network == local ]] && canisters_json=".dfx/local/canister_ids.json"
while [ ! $canister_id ];
do
    # Find canister ID in local json files
    [ -f $canisters_json ] && canister_id=$(jq ".\"$canister\".\"$network\"" $canisters_json);
    if [[ ! $canister_id ]]
    then
        # Create the canister
        dfx canister --network $network $wallet create $canister;
    fi
done

# Deploy using config manifest as arguments
dfx deploy $wallet --network $network $canister --argument "(
    principal $canister_id
)"
