#!/bin/sh

set -eu

request_url="${INFLUXDB_URL%/}/api/v3/configure/database"
request_body=$(printf '{"db":"%s","retention_period":"%s"}' \
    "$INFLUXDB_DATABASE" "$INFLUXDB_RETENTION_PERIOD")
attempt=0

while [ "$attempt" -lt 30 ]; do
    if status=$(curl --silent --connect-timeout 2 --max-time 5 \
        --output /dev/null --write-out '%{http_code}' \
        --request POST \
        --header 'Content-Type: application/json' \
        --data "$request_body" \
        "$request_url"); then
        case "$status" in
            2??)
                printf 'Created InfluxDB database %s with retention %s\n' \
                    "$INFLUXDB_DATABASE" "$INFLUXDB_RETENTION_PERIOD"
                exit 0
                ;;
            409)
                printf 'InfluxDB database %s already exists\n' "$INFLUXDB_DATABASE"
                exit 0
                ;;
            5??|000)
                ;;
            *)
                printf 'InfluxDB database configuration failed with HTTP %s\n' \
                    "$status" >&2
                exit 1
                ;;
        esac
    fi

    attempt=$((attempt + 1))
    sleep 2
done

printf 'InfluxDB database %s was not reachable after %s attempts\n' \
    "$INFLUXDB_DATABASE" "$attempt" >&2
exit 1
