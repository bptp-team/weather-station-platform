#!/usr/bin/env bash
# Runs on the operator workstation:
#
#     scripts/create-mqtt-password.sh <key-vault-name> <mqtt-username>

set -euo pipefail

readonly PASSWORD_BYTES=24
readonly USAGE="usage: create-mqtt-password.sh <key-vault-name> <mqtt-username>"

key_vault_name="${1:?$USAGE}"
mqtt_username="${2:?$USAGE}"

[[ "$mqtt_username" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo "invalid username: $mqtt_username" >&2; exit 1; }

password="$(openssl rand -hex "$PASSWORD_BYTES")"

az keyvault secret set --vault-name "$key_vault_name" --name "mqtt-password-$mqtt_username" --value "$password" --output none

printf '%s\n' "$password"
