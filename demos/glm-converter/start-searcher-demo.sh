#!/bin/bash

# use dot as a decimal separator
export LC_NUMERIC="en_US.UTF-8"

set +x

ETH_RPC_URL=http://localhost:8545
DEPLOYER_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
DEPLOYER_ADDR=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

# anvil \
1>/dev/null anvil \
             --block-time 3 \
             --chain-id 1 \
             --fork-url $ETHEREUM_NODE_MAINNET &

anvil_id=$!

echo "Waiting for anvil to open its port..."
while ! nc -z localhost 8545; do
    sleep 0.1
done

MAX_UINT_256=115792089237316195423570985008687907853269984665640564039457584007913129639936

uint_prob() {
    local probability=$1
    local normalized_to_uint=$(echo "$probability * $MAX_UINT_256" | bc | tr -d '\\\n')
    local normalized_to_uint=$(printf "%.0f\n" "$normalized_to_uint")
    echo $normalized_to_uint
}

export unit_prob

eth_to_wei() {
    local eth_amount=$1
    local wei_amount=$(echo "$eth_amount * 1000000000000000000" | bc)
    local wei_amount_int=$(printf "%.0f\n" "$wei_amount")
    echo $wei_amount_int
}

chance_of_trade_in_block=$(uint_prob 0.5)
daily_ETH_budget=$(eth_to_wei 9.4)
single_trade_low=$(eth_to_wei 0.006)
single_trade_high=$(eth_to_wei 0.014)

echo "Deploying contracts..."
deployment=$(forge create \
                   --json \
                   --legacy \
                   --constructor-args $chance_of_trade_in_block $daily_ETH_budget $single_trade_low $single_trade_high \
                   --value 1002ether \
                   --rpc-url $ETH_RPC_URL \
                   --private-key $DEPLOYER_KEY \
                   ./src/routers-transformers/Converter.sol:Converter)
converter=$(echo "$deployment" | jq -r .deployedTo)
echo "Deployed to $converter"

1>/dev/null cast send --private-key $DEPLOYER_KEY $converter 'wrap()'

cd demos/glm-converter/
poetry run python3 searcher.py \
    -pk 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    -url $ETH_RPC_URL \
    --converter $converter

kill $anvil_id

wait
