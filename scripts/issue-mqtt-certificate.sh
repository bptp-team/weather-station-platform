#!/usr/bin/env bash
# Runs on the operator workstation:
#
#     scripts/issue-mqtt-certificate.sh <key-vault-name> <broker-hostname> [<broker-hostname>...]

set -euo pipefail

readonly CERTIFICATES_DIR="$(readlink -f "$(dirname "$(readlink -f "$0")")/..")/certificates"
readonly KEY_ALGORITHM="rsa:2048"
readonly CA_VALIDITY_DAYS=3650
readonly SERVER_VALIDITY_DAYS=825
readonly CA_SUBJECT="/CN=Weather Station MQTT CA"
readonly USAGE="usage: issue-mqtt-certificate.sh <key-vault-name> <broker-hostname> [<broker-hostname>...]"

key_vault_name="${1:?$USAGE}"
shift
[[ $# -gt 0 ]] || { echo "$USAGE" >&2; exit 1; }

broker_hostnames=("$@")
subject_alternative_names="$(printf 'DNS:%s,' "${broker_hostnames[@]}")"
subject_alternative_names="${subject_alternative_names%,}"

mkdir -p "$CERTIFICATES_DIR"
chmod 700 "$CERTIFICATES_DIR"
cd "$CERTIFICATES_DIR"

if [[ ! -f ca.key ]]; then
    openssl req -x509 -new -nodes \
        -newkey "$KEY_ALGORITHM" -keyout ca.key -out ca.crt \
        -days "$CA_VALIDITY_DAYS" -subj "$CA_SUBJECT" \
        -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,keyCertSign,cRLSign"
    chmod 600 ca.key
fi

openssl req -new -nodes \
    -newkey "$KEY_ALGORITHM" -keyout server.key -out server.csr \
    -subj "/CN=${broker_hostnames[0]}"
chmod 600 server.key

openssl x509 -req -in server.csr \
    -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out server.crt -days "$SERVER_VALIDITY_DAYS" \
    -extfile <(printf '%s\n' \
        "basicConstraints=critical,CA:FALSE" \
        "keyUsage=critical,digitalSignature,keyEncipherment" \
        "extendedKeyUsage=serverAuth" \
        "subjectAltName=$subject_alternative_names")
rm server.csr

az keyvault secret set --vault-name "$key_vault_name" --name mqtt-server-certificate --file server.crt --output none
az keyvault secret set --vault-name "$key_vault_name" --name mqtt-server-private-key --file server.key --output none

echo "Broker certificate stored in $key_vault_name for: ${broker_hostnames[*]}"
echo "CA certificate for the firmware: $CERTIFICATES_DIR/ca.crt"
