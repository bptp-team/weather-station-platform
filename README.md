### Weather Station Platform

<p align="justify">
    <img
        src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/mosquitto.svg"
        width="50"
        height="50"
    />
    <img
        src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/influxdb/influxdb-original.svg"
        width="50"
        height="50"
    />
    <img
        src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/docker-compose.png"
        width="50"
        height="50"
    />
    <img
        src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/terraform/terraform-original.svg"
        width="50"
        height="50"
    />
    <img
        src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/azure/azure-original.svg"
        width="50"
        height="50"
    />
</p>

This repository holds the **infrastructure** the rest of the **Weather Station** system depends on. It carries **no application code**: the **firmware**, the **​backend**, and the **frontend** live in their own repositories and connect to what is defined here.

| Directory | Purpose |
| --------- | ------- |
| `compose/` | **MQTT broker** and **time-series database**, run with **Docker Compose** |
| `terraform/` | **Azure** resources that host the system: **VM**, **network** and **container registry** |
| `edge/` | **Nginx** in front of the **frontend** and **backend**: **TLS** and **routing** |

The two halves are **independent**. `compose/` is what you run for **local
development**; `terraform/` provisions the **machine** where that same stack
runs in **production**. `edge/` runs **only in production**, on that machine.

## Services

| Service | Image | Port | Role |
| ------- | ----- | ---- | ---- |
| `mosquitto` | `eclipse-mosquitto:2.1-alpine` | `1883` | Receives the **sensor readings** published by the **ESP32** boards |
| `influxdb3` | `influxdb:3-core` | `8181` | Stores the **snapshots** written by the **backend** |

The **backend** sits between the two: it **subscribes** to the broker, assembles
**complete snapshots** and **writes** them to **InfluxDB**. Neither service in
this repository talks to the other.

## Local development

### Requirements

**Docker Engine** with the **Compose v2** plugin. Nothing else is installed on
the host: both services run entirely from their **official images**.

### Configuration

The stack reads **one variable**, `MQTT_PORT`, which sets the **host port**
mapped to the broker:

```sh
cp compose/.env.example compose/.env
```

**The file must sit next to `docker-compose.yaml`, inside `compose/`.** Docker
Compose resolves `.env` from the **project directory** — the directory holding
the compose file — **not** from the directory the command runs in. A `.env`
placed in the **repository root is never read**.

That failure is **silent**. An unset `MQTT_PORT` expands to an **empty string**,
and Docker answers an empty host port by publishing the broker on a **random
one**, so the stack reports itself as running while the **ESP32 boards cannot
reach it**. Confirm the mapping instead of assuming it:

```sh
docker compose -f compose/docker-compose.yaml config | grep -A2 'target: 1883'
```

Passing the file explicitly with `--env-file <path>` also works and ignores the
project directory entirely.

> `INFLUXDB_PORT` also appears in `.env.example`, but the compose file publishes
> `8181` directly. Changing that variable has **no effect**.

### Start

```sh
docker compose -f compose/docker-compose.yaml up -d
```

### Verify

```sh
docker compose -f compose/docker-compose.yaml ps        # both services running
docker port mosquitto                                     # must read 1883 -> 0.0.0.0:1883
curl http://localhost:8181/health                        # InfluxDB answering: OK
docker run --rm --network host eclipse-mosquitto:2.1-alpine \
    mosquitto_sub -h 127.0.0.1 -t 'weather/#' -v         # live readings
```

### Stop

```sh
docker compose -f compose/docker-compose.yaml down       # keeps the stored data
docker compose -f compose/docker-compose.yaml down -v    # also deletes it
```

## MQTT broker

The broker is configured by `compose/mosquitto/config/mosquitto.conf`:

```yaml
listener 1883 0.0.0.0

allow_anonymous true

persistence true
persistence_location /mosquitto/data/

log_dest stdout
```

The **explicit listener** matters. **Mosquitto 2.0 and later** accept only
**local connections** under their built-in defaults, so without this line the
**ESP32 boards would be refused**.

**Persistence** writes retained messages and queued **QoS** messages to
`compose/mosquitto/data/`, so they **survive a restart**. Logs go to
**stdout**, where the **Docker logging driver** collects them:

```sh
docker compose -f compose/docker-compose.yaml logs -f mosquitto
```

The **firmware** publishes **one topic per measurement**:

```yaml
weather/<device-id>/airTemperature
weather/<device-id>/airPressure
weather/<device-id>/airHumidity
weather/<device-id>/daylight
weather/<device-id>/waterLevel
weather/<device-id>/airQuality
```

In `secrets.h`, the **ESP32** must point at the **LAN address of the machine
running this stack** — **never** `localhost`, which from the board means the
**board itself**.

**Authentication is disabled.** `allow_anonymous true` lets **any client on the
network** publish and subscribe, which is acceptable on a **development LAN**
and **not** on a public address. See [Security](#security).

## InfluxDB

The service runs **InfluxDB 3 Core** with **authorization turned off**:

```yaml
--node-id influxdb3
--object-store file
--data-dir /var/lib/influxdb3
--without-auth
```

Data is kept in the **named volume** `influxdb3-data`, which **survives**
`docker compose down` and is removed only by `down -v`.

**Databases are created on first write** — no setup step is required. The
**backend** defaults already target this service:

```text
WEATHER_INFLUX_URL=http://127.0.0.1:8181
WEATHER_INFLUX_DATABASE=weather-station-db
WEATHER_INFLUX_MEASUREMENT=weather_reading
```

Write and read a point by hand:

```sh
curl -X POST "http://localhost:8181/api/v3/write_lp?db=weather-station-db" \
    --data-binary 'weather_reading,station_id=station-01 temperature=21.5'

curl -X POST "http://localhost:8181/api/v3/query_sql" \
    -H 'Content-Type: application/json' \
    -d '{"db":"weather-station-db","q":"SELECT * FROM weather_reading LIMIT 5"}'
```

## Infrastructure

The `terraform/` module provisions the **Azure** host. It requires
**Terraform 1.9.0 or later** and the **azurerm provider 5.5 or later**.

### Resources

With the default `project_name` and `environment`, every name is prefixed
`weather-station-dev`:

| Resource | Name | Notes |
| -------- | ---- | ----- |
| Resource group | `weather-station-dev-rg` | Holds everything below |
| Container registry | `var.acr_name` | **Globally unique**; admin account **disabled** |
| Virtual network | `weather-station-dev-vnet` | `10.10.0.0/16` |
| Subnet | `weather-station-dev-subnet` | `10.10.1.0/24` |
| Network security group | `weather-station-dev-nsg` | Rules below |
| Public IP | `weather-station-dev-pip` | **Standard** SKU, **static**, with a **DNS label** |
| Network interface | `weather-station-dev-nic` | |
| Virtual machine | `weather-station-dev-vm` | **Ubuntu 24.04 LTS**, `Standard_B1s` |
| Role assignment | — | Grants the VM **`AcrPull`** on the registry |

The VM carries a **system-assigned managed identity**, and that identity is what
holds `AcrPull`. The registry needs **no stored credentials**: the VM pulls
images using its **own identity**, and `admin_enabled = false` keeps the
registry's shared account **switched off**.

**Password authentication is disabled** on the VM. Access is by **SSH key
only**, injected from `ssh_public_key_path`.

### Firewall

The NSG opens **four inbound ports**:

| Port | Priority | Default source | Purpose |
| ---- | -------- | -------------- | ------- |
| `22` | 100 | `ssh_allowed_cidrs` — **no default** | Administrative access |
| `80` | 110 | `0.0.0.0/0` | Frontend and **ACME HTTP-01** challenge |
| `443` | 120 | `0.0.0.0/0` | Frontend and backend **API over TLS** |
| `1883` | 130 | `0.0.0.0/0` | **MQTT ingestion** from the ESP32 boards |

`ssh_allowed_cidrs` has **no default** and **must** be set — the module refuses
an empty list. Use **your own address with a `/32` mask**; get it with
`curl -s ifconfig.me`.

### Usage

```sh
az login
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Fill in `subscription_id`, `ssh_allowed_cidrs`, `acr_name` and `dns_label`. The
example file carries the command for each value. Then:

```sh
terraform -chdir=terraform init
terraform -chdir=terraform plan
terraform -chdir=terraform apply
```

`terraform.tfvars` is **ignored by Git** and **must not be committed**.

### Outputs

```sh
terraform -chdir=terraform output
```

| Output | Used for |
| ------ | -------- |
| `public_ip_address` | Reaching the VM |
| `public_fqdn` | `<dns_label>.<region>.cloudapp.azure.com` — the **broker address** the firmware connects to |
| `acr_login_server` | **Registry hostname** used in image tags |
| `acr_name` | `az acr login --name <value>` |
| `resource_group_name` | Scoping `az` commands |
| `vm_name` | Scoping `az` commands |
| `vm_identity_principal_id` | The identity holding `AcrPull` |

### State

**State is local.** `versions.tf` carries **no backend block** — the comment
there records the reason: the **Storage Account** that would host the state
**does not exist yet**. `terraform.tfstate` is **ignored by Git**, so it lives
on **one machine only**. Back it up before destroying anything.

### What is not automated

Terraform provisions the **host and nothing more**. It does **not** install
**Docker**, copy this compose file, or start the services on the VM. There is
**no cloud-init and no configuration management** in this repository — those
steps are **manual** after `apply`.

## Edge proxy

`edge/nginx.conf` is the **only public entry** to the web application. It
answers on ports `80` and `443`, **obtains and renews** the **Let's Encrypt**
certificate by itself, and routes each request:

| Path | Destination | Container |
| ---- | ----------- | --------- |
| `/api/` | `127.0.0.1:8000` | **backend** |
| everything else | `127.0.0.1:8080` | **frontend** |

The **frontend** and the **backend** are published on `127.0.0.1` only, as their
own READMEs describe, so they are **reachable only through the edge**. FastAPI's
`/docs` and `/openapi.json` are **not exposed**: only `/api/` reaches the backend.

It **does not run locally**. Let's Encrypt must reach a **public domain** on
port `80`, which only the VM has.

### Before starting

- `server_name` in `edge/nginx.conf` **must match** the `public_fqdn` output.
  The file carries `weather-station.brazilsouth.cloudapp.azure.com`, the name
  produced by the example `dns_label`.
- Build the **frontend** with
  `--build-arg VITE_WEATHER_API_URL=https://<public_fqdn>`. The API is then on
  the **same origin** as the page, so `WEATHER_ALLOWED_ORIGINS` can stay empty.
- Run the **backend** with `-e FORWARDED_ALLOW_IPS='*'`. Without it, the server
  **ignores** the `X-Forwarded-*` headers the edge sends, because requests
  arrive from the **Docker bridge**, not from `127.0.0.1`. Trusting every
  address is safe only because the backend port is **bound to `127.0.0.1`**.

### Start

```sh
docker run -d --name edge --restart unless-stopped --network host \
    -v "$PWD/edge/nginx.conf:/etc/nginx/nginx.conf:ro" \
    -v edge-acme:/var/cache/nginx \
    nginx:1.30.4
```

- `--network host` lets the edge reach `127.0.0.1:8000` and `127.0.0.1:8080`
  and listen on ports `80` and `443` of the VM directly.
- The `edge-acme` volume **must be kept**. It stores the **ACME account**, the
  **certificate** and its **private key**. Without it, every restart requests a
  **new certificate**, and Let's Encrypt allows only **5 identical
  certificates per week**.

On the **first deployment**, point `uri` in `edge/nginx.conf` at the
**staging** directory, `https://acme-staging-v02.api.letsencrypt.org/directory`,
and switch back to production once the certificate is issued. Delete the
`edge-acme` volume when switching, so the staging account and certificate are
discarded.

### Verify

```sh
curl -I http://<public_fqdn>                                    # 301 to https
curl https://<public_fqdn>/healthz                              # ok, from the frontend
curl -N https://<public_fqdn>/api/v1/readings/station-01/stream # live readings
docker logs edge                                                # access log, real client addresses
```

## Security

Three settings are **deliberately open for development** and must be changed
before this stack faces a **public address**:

- **`allow_anonymous true`** — any client that reaches port `1883` can publish
  and subscribe. Configure a **password file** and set `allow_anonymous false`.
- **`--without-auth`** — the InfluxDB API accepts **any request**, including
  deletes. Remove the flag and issue an **admin token**.
- **`mqtt_allowed_cidrs = ["0.0.0.0/0"]`** — port `1883` is open to the
  **internet**, because the ESP32 boards connect from **dynamic addresses**.
  This is only tolerable **while the broker itself requires authentication**.

The first two are harmless on a **development LAN**. Combined with the third,
they leave the **broker fully open**.
