#!/usr/bin/env bash
# Runs on the operator workstation:
#
#     scripts/create-influxdb-token.sh <key-vault-name>

set -euo pipefail

readonly INFLUXDB_IMAGE="influxdb:3-core"
readonly SECRET_NAME="influxdb-admin-token"
readonly TOKEN_FILE_NAME="admin-token.json"
readonly USAGE="usage: create-influxdb-token.sh <key-vault-name>"

key_vault_name="${1:?$USAGE}"

token_directory="$(mktemp -d)"
trap 'rm -rf "$token_directory"' EXIT

docker run --rm \
    --user "$(id -u):$(id -g)" \
    --volume "$token_directory:/token" \
    "$INFLUXDB_IMAGE" \
    influxdb3 create token --admin --offline --output-file "/token/$TOKEN_FILE_NAME" >/dev/null

az keyvault secret set --vault-name "$key_vault_name" --name "$SECRET_NAME" \
    --file "$token_directory/$TOKEN_FILE_NAME" --output none

echo "InfluxDB admin token stored in $key_vault_name as $SECRET_NAME"
