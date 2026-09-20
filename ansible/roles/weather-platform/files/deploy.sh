#!/usr/bin/env bash
# Installed by Ansible. The application pipelines call it through az vm run-command:
#
#     deploy.sh <backend|frontend> <version>
#
# It rewrites the version in .env, pulls that image from the registry and recreates
# the service. It never builds anything.

set -euo pipefail

service="${1:?usage: deploy.sh <backend|frontend> <version>}"
version="${2:?usage: deploy.sh <backend|frontend> <version>}"

case "$service" in
    backend) variable=BACKEND_VERSION ;;
    frontend) variable=FRONTEND_VERSION ;;
    *) echo "unknown service: $service" >&2; exit 1 ;;
esac

cd "$(dirname "$(readlink -f "$0")")"

sed -i "s|^${variable}=.*|${variable}=${version}|" .env
grep -qx "${variable}=${version}" .env

set -a
# shellcheck disable=SC1091
. ./.env
set +a

# The VM pulls with its own managed identity, and the token lasts about three hours.
az login --identity --output none
az acr login --name "$ACR_NAME"

docker compose pull "$service"
docker compose up -d --wait --wait-timeout 180 "$service"

echo "$service is running ${version}"
