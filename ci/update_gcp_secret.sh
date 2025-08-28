#!/usr/bin/env bash

set -ueo pipefail

ENVIRONMENT=$1

# GCP credentials
echo "$GOOGLE_APPLICATION_CREDENTIALS_B64" | base64 -d >.gcloud-credentials.json
chmod 400 .gcloud-credentials.json
gcloud auth activate-service-account --key-file=.gcloud-credentials.json

jq -Rn '[inputs | select(length > 0) | split("=")] | map({ (.[0]): .[1] }) | add' < contract_addresses.txt > contract_addresses.json

# Update the GCP secret with the new version
gcloud secrets versions add "octant-v2-${ENVIRONMENT}-contracts" --data-file=contract_addresses.json --project="$GCP_PROJECT"

# Clean up
rm .gcloud-credentials.json contract_addresses.json
