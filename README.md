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
    <img
        src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/ansible/ansible-original.svg"
        width="50"
        height="50"
    />
    <img
        src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/nginx/nginx-original.svg"
        width="50"
        height="50"
    />
    <img
        src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/bash/bash-original.svg"
        width="50"
        height="50"
    />
</p>

This repository holds the **infrastructure** the rest of the **Weather Station** system depends on. It carries **no application code**: the **firmware**, the **backend**, and the **frontend** live in their own repositories and connect to what is defined here.

| Directory | Purpose |
| --------- | ------- |
| `compose/` | The **Docker Compose** files: the local development stack and the whole production stack |
| `terraform/` | **Azure** resources that host the system: **VM**, **network**, **container registry** and **Key Vault** |
| `ansible/` | **Packages** installed on that VM, and the **production stack** it runs |
| `scripts/` | **Operator scripts** that write the broker certificate and passwords to Key Vault |
| `edge/` | **Nginx** in front of the **frontend** and **backend**: **TLS** and **routing** |

The two halves are **independent**. `compose/` is what you run for **local
development**; `terraform/` provisions the **machine** where that same stack
runs in **production**, and `ansible/` installs what that machine needs to run
it. `edge/` runs **only in production**, on that machine.

## Services

| Service | Image | Port | Role |
| ------- | ----- | ---- | ---- |
| `mosquitto` | `eclipse-mosquitto:2.1-alpine` | `1883`, and `8883` with TLS in production | Receives the **sensor readings** published by the **ESP32** boards |
| `influxdb3` | `influxdb:3-core` | `8181` | Stores the **snapshots** written by the **backend** |
| `influxdb-init` | `curlimages/curl:8.12.1` | — | Creates the configured InfluxDB database once, then exits |
| `backend` | Local build or versioned production image | `8000` | Stores snapshots and serves live and historical readings |

The **backend** sits between Mosquitto and InfluxDB: it **subscribes** to the
broker, assembles **complete snapshots** and **writes** them to **InfluxDB**.
The initializer configures the database before the backend starts; it exits
with status `0` after setup, which is expected.
`compose/init-influxdb.sh` runs inside a Linux container and is kept in LF
format by `.gitattributes`, including when checked out on Windows.

## Local development

### Requirements

**Docker Engine** with the **Compose v2** plugin and a sibling checkout of
`weather-station-backend`, because the local backend image is built from source.
For example, the two repositories should be next to each other:

```text
projects/
  weather-station-platform/
  weather-station-backend/
```

Mosquitto and InfluxDB run from their official images; Compose builds the
backend from the sibling checkout.

### Configuration

The local stack reads the variables in `compose/.env.example`:

```sh
cp compose/.env.example compose/.env
```

| Variable | Default | Purpose |
| -------- | ------- | ------- |
| `MQTT_PORT` | `1999` | Host port mapped to the Mosquitto broker |
| `INFLUXDB_PORT` | `2000` | Reserved; the Compose file currently publishes InfluxDB on `8181` directly, so this value has no effect |
| `INFLUXDB_DATABASE` | `weather-station-db` | Database created by the InfluxDB initializer and used by the backend |
| `INFLUXDB_RETENTION_PERIOD` | `15d` | Retention period applied when the database is first created |
| `INFLUXDB_QUERY_FILE_LIMIT` | `600` | InfluxDB server-wide maximum Parquet files accessed by a query |
| `HISTORICAL_CACHE_RETENTION_DAYS` | `15` | Maximum age of cached historical day segments; keep aligned with InfluxDB retention |

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

### Start

```sh
docker compose -f compose/docker-compose.yaml up -d --build
```

### Verify

```sh
docker compose -f compose/docker-compose.yaml ps        # initializer Exited (0) is expected
docker port mosquitto                                     # must read 1883 -> 0.0.0.0:1883
curl http://localhost:8181/health                        # InfluxDB answering: OK
curl "http://localhost:8000/api/v1/readings/station-01?from=2026-09-01T00:00:00Z&to=2026-09-03T00:00:00Z"
docker run --rm --network host eclipse-mosquitto:2.1-alpine \
    mosquitto_sub -h 127.0.0.1 -t 'weather/#' -v         # live readings
```

The backend caches **completed UTC days** in SQLite at
`/var/lib/weather-cache/historical.sqlite3`; requests touching the current UTC
day still query InfluxDB. The dedicated `historical-cache` Docker volume
survives backend container restarts and `docker compose down`. To inspect its
entries while the backend is running:

```sh
docker compose -f compose/docker-compose.yaml exec backend \
    python -c 'import sqlite3; c=sqlite3.connect("/var/lib/weather-cache/historical.sqlite3"); print(c.execute("SELECT station_id, utc_date FROM historical_days ORDER BY utc_date").fetchall())'
docker compose -f compose/docker-compose.yaml restart backend
```

`docker compose down -v` also deletes the cache. When changing
`INFLUXDB_RETENTION_PERIOD`, set `HISTORICAL_CACHE_RETENTION_DAYS` to the same
number of days so cached data does not outlive its source retention.

### Stop

```sh
docker compose -f compose/docker-compose.yaml down       # keeps local data
docker compose -f compose/docker-compose.yaml down -v    # also removes named volumes
```

Mosquitto and InfluxDB store runtime data in **bind-mounted directories** under
`compose/`. These directories survive both commands above; `down -v` removes
Docker-managed named volumes (including the historical cache), not
bind-mounted host directories.

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
`compose/mosquitto/data/`, so they **survive container restarts and removal**.
The directory is local runtime data and is **excluded from Git**. Logs go to
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

**Authentication is disabled in development.** `allow_anonymous true` lets
**any client on the network** publish and subscribe, which is acceptable on a
**development LAN** and **not** on a public address. Production uses its own
configuration, described below.

### Production broker

The VM runs `compose/mosquitto/config/mosquitto.prod.conf`, installed as
`mosquitto.conf`, with two listeners:

| Listener | Reachable from | Transport | Clients |
| -------- | -------------- | --------- | ------- |
| `8883` | **Internet**, published by Compose | **TLS** | The **ESP32** boards |
| `1883` | The **Compose network** only, never published | Plain TCP | The **backend** |

Both listeners require a **username and password**: `allow_anonymous false`
applies to every listener. The password file is generated on the VM from Key
Vault on each deployment; see [Secrets](#secrets).

`compose/mosquitto/config/aclfile` decides what each user may do:

| Rule | Effect |
| ---- | ------ |
| `pattern write weather/%u/+` | Each station publishes **only under its own username**: `station-01` writes `weather/station-01/airTemperature` and cannot write `weather/station-02/...` |
| `user weather-station-backend` + `topic read weather/+/+` | Only the backend **subscribes** to the readings |

A station's **MQTT username is its `DEVICE_ID`**. Adding a station means adding
its ID to `weather_platform_mqtt_station_ids` in the `weather-platform` role
defaults and creating its password.

## InfluxDB

The service runs **InfluxDB 3 Core** with **authorization turned off**:

```yaml
--node-id influxdb3
--object-store file
--data-dir /var/lib/influxdb3
--without-auth
```

Data is stored in the **bind-mounted directory** `compose/influxdb3-data/` on
the host, mapped to `/var/lib/influxdb3` in the container. The directory is
**excluded from Git** and survives container restarts, `docker compose down`,
and `docker compose down -v`; remove it from the host only when you intend to
delete the local database data.

The `influxdb-init` one-shot service creates the configured database through the
InfluxDB API before the production backend starts. In local development, `docker
compose up` runs the same initializer. It sets a **15-day data retention period**
by default; points older than 15 days expire under this policy. If the database
already exists, the initializer accepts the conflict and leaves it unchanged.
Changing retention on an existing database requires a separate migration.

The server's Parquet file-access limit is **600 files per query** by default
(InfluxDB 3 Core's default is 432). This is a server-wide startup setting, not a
per-database property. A higher limit can increase query latency and memory use.
Adjust `INFLUXDB_QUERY_FILE_LIMIT` cautiously and recreate/restart InfluxDB for
the setting to take effect.

Local settings live in `compose/.env`:

```text
INFLUXDB_DATABASE=weather-station-db
INFLUXDB_RETENTION_PERIOD=15d
INFLUXDB_QUERY_FILE_LIMIT=600
```

Copy `compose/.env.example` to create the local file. Production values are
managed by the `weather-platform` Ansible role defaults. The backend receives
the configured database name from Compose and no longer creates or configures
the database itself.

Write and read a point by hand:

```sh
curl -X POST "http://localhost:8181/api/v3/write_lp?db=weather-station-db" \
    --data-binary 'weather_reading,station_id=station-01 temperature=21.5'

curl -X POST "http://localhost:8181/api/v3/query_sql" \
    -H 'Content-Type: application/json' \
    -d '{"db":"weather-station-db","q":"SELECT * FROM weather_reading LIMIT 5"}'
```

## Infrastructure

The `terraform/` module provisions the **Azure** host in `mexicocentral`. The
**Azure for Students** subscription only allows deployments in a fixed list of
regions (`az policy assignment list`), and **none of them is in Brazil**; Mexico
Central is the closest. It requires **Terraform 1.9 or later (1.x)** and the
**azurerm provider 5.5 or later (5.x)**.

### Resources

| Resource | Name | Notes |
| -------- | ---- | ----- |
| Resource group | `weather-station-rg` | Holds everything below |
| Container registry | `var.acr_name` | **Basic**, **globally unique**; admin account **disabled** |
| Virtual network | `weather-station-vnet` | `10.10.0.0/16` |
| Subnet | `weather-station-subnet` | `10.10.1.0/24` |
| Network security group | `weather-station-nsg` | Rules below |
| Public IP | `weather-station-pip` | **Standard** SKU, **static**, with a **DNS label** |
| Network interface | `weather-station-nic` | |
| Virtual machine | `weather-station-vm` | **Ubuntu 24.04 LTS**, `Standard_B2ats_v2`, 30 GB disk |
| Role assignment | — | Grants the VM **`AcrPull`** on the registry |
| Key Vault | `var.key_vault_name` | **Standard**, **globally unique**, **RBAC** authorization, reachable only from the VM's public IP and `ssh_allowed_cidrs` |
| Role assignment | | Grants the VM **`Key Vault Secrets User`** on the vault: it reads the broker secrets |
| Role assignment | | Grants the operator running `apply` **`Key Vault Secrets Officer`** on the vault: it writes them |

The VM carries a **system-assigned managed identity**, and that identity is what
holds `AcrPull`. The registry needs **no stored credentials**: the VM pulls
images using its **own identity**, and `admin_enabled = false` keeps the
registry's shared account **switched off**.

**Password authentication is disabled** on the VM. Access is by **SSH key
only**, taken from `ssh_public_key`. The key is set **by value**, not read from
a local path, so every operator plans against the **same key** — a different
key would force the VM to be **replaced**.

**The VM has `prevent_destroy`.** Its OS disk holds the **InfluxDB data**, the
**broker state** and the **ACME certificate**, so any plan that would destroy
or replace it **fails** instead. Remove the `lifecycle` block deliberately if
that is really intended.

### Firewall

| Port | Priority | Source | Purpose |
| ---- | -------- | ------ | ------- |
| `22` | 100 | `ssh_allowed_cidrs` — **no default** | Administrative access |
| `80`, `443` | 110 | `Internet` | Frontend, backend **API over TLS** and **ACME HTTP-01** |
| `8883` | 120 | `Internet` | **MQTT over TLS** from the ESP32 boards (dynamic addresses) |

`ssh_allowed_cidrs` **must** be set — the module refuses an empty list and
`0.0.0.0/0`. Use **your own address with a `/32` mask**; get it with
`curl -4 -s ifconfig.me`. The same list opens the **Key Vault firewall**, so
when your address changes, update it and run `apply` again before using the
scripts in [Secrets](#secrets).

### State

State is stored in an **Azure Storage Account**, declared in the `backend`
block of `versions.tf`. The blob lease **locks** the state during every
operation, and access uses **Entra ID** (`use_azuread_auth`), so the account
keeps **shared keys disabled**.

The account is **created once, outside Terraform**, because it must exist before
`init`. Its name is **globally unique**: if `weatherstationtfstate` is taken,
pick another and update `storage_account_name` in `versions.tf`.

```sh
az provider register --namespace Microsoft.Storage --wait

az group create -n weather-station-tfstate-rg -l mexicocentral

az storage account create -n weatherstationtfstate -g weather-station-tfstate-rg \
    -l mexicocentral --sku Standard_LRS --min-tls-version TLS1_2 \
    --allow-blob-public-access false --allow-shared-key-access false

az storage account blob-service-properties update \
    --account-name weatherstationtfstate -g weather-station-tfstate-rg \
    --enable-versioning true --enable-delete-retention true --delete-retention-days 30

az role assignment create --role "Storage Blob Data Contributor" \
    --assignee "$(az ad signed-in-user show --query id -o tsv)" \
    --scope "$(az storage account show -n weatherstationtfstate -g weather-station-tfstate-rg --query id -o tsv)"

az storage container create -n tfstate --account-name weatherstationtfstate --auth-mode login
```

The **first command** registers the storage resource provider: new
subscriptions, such as **Azure for Students**, start without it, and every
other command fails with `SubscriptionNotFound` until it is registered.

**Blob versioning** keeps every previous state, so a corrupted or overwritten
state can be **restored**. The role assignment may take **a minute** to
propagate. Every other operator needs the same **`Storage Blob Data
Contributor`** role on the account.

### Usage

```sh
az login
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Fill in `subscription_id`, `ssh_allowed_cidrs`, `ssh_public_key`, `dns_label`,
`acr_name` and `key_vault_name`. The example file carries the command for each
value. Then:

```sh
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=main.tfplan
terraform -chdir=terraform apply main.tfplan
```

`terraform.tfvars` is **ignored by Git** and **must not be committed**.

### Outputs

```sh
terraform -chdir=terraform output
```

| Output | Used for |
| ------ | -------- |
| `public_ip_address` | The target of the **A record** of the project domain; see [Domain](#domain) |
| `public_fqdn` | `<dns_label>.mexicocentral.cloudapp.azure.com`, the name Azure generates; a second name in the broker certificate |
| `acr_login_server` | **Registry hostname** used in image tags |
| `acr_name` | `az acr login --name <value>` |
| `key_vault_name` | The scripts in [Secrets](#secrets) and `weather_platform_key_vault_name` in the `weather-platform` role |
| `resource_group_name` | Scoping `az` commands |
| `vm_name` | Scoping `az` commands |

### Domain

The system answers on **`weather-station.thomaspalma.com.br`**: the website, the
API under `/api/` and the MQTT broker on port `8883` all use that name. It is a
subdomain of `thomaspalma.com.br`, whose DNS is hosted by **Registro.br**, so
the record is created **by hand** in the Registro.br panel, not by Terraform:

| Name | Type | Value |
| ---- | ---- | ----- |
| `weather-station` | `A` | The `public_ip_address` output |

The public IP is **static**, and deallocating the VM keeps it, so the record
only changes if the public IP resource is destroyed and created again. Check
the record from the operator workstation:

```sh
dig +short A weather-station.thomaspalma.com.br
```

The answer must be the `public_ip_address` output. The same name appears in
`server_name` in `edge/nginx.conf`, in `ansible_host` in
`ansible/inventory/azure.yaml`, in the broker certificate, in `MQTT_HOSTS` in
the firmware and in the `PUBLIC_FQDN` variable of the backend and frontend
repositories.

### What is not automated

Terraform provisions the **host and nothing more**. Everything above it comes
from `ansible/`: the packages, the production stack and each release. See
[Host configuration](#host-configuration).

## Secrets

The broker secrets live in the **Key Vault** created by `terraform/`. Their
**values never enter Terraform or Git**: the operator writes them with the two
scripts below, and the `weather-platform` role reads them on the VM with the
**managed identity**, the same way it signs in to the registry.

| Secret | Written by | Read by |
| ------ | ---------- | ------- |
| `mqtt-server-certificate` | `scripts/issue-mqtt-certificate.sh` | Mosquitto, as `certs/server.crt` |
| `mqtt-server-private-key` | `scripts/issue-mqtt-certificate.sh` | Mosquitto, as `certs/server.key` |
| `mqtt-password-<username>` | `scripts/create-mqtt-password.sh` | Mosquitto's password file, the backend's `.env` and, for stations, `secrets.h` in the firmware |

Both scripts run on the **operator workstation**, after `terraform apply`, with
`az login` done and your address in `ssh_allowed_cidrs`. The `Key Vault Secrets
Officer` role may take **a few minutes** to propagate after the first `apply`.

### Broker certificate

The broker uses a certificate signed by a **private Certificate Authority
(CA)**. The firmware trusts that CA directly, so the certificate does not
depend on Let's Encrypt or on the edge proxy. On the operator workstation, from
the repository root:

```sh
scripts/issue-mqtt-certificate.sh "$(terraform -chdir=terraform output -raw key_vault_name)" \
    weather-station.thomaspalma.com.br \
    "$(terraform -chdir=terraform output -raw public_fqdn)"
```

The script creates the CA in `certificates/` on the **first run only**, issues
a new server certificate for every hostname passed, and stores the certificate
and its key in Key Vault. `certificates/` is **ignored by Git**.

**Keep `certificates/ca.key` safe and backed up.** Running the script again
reuses it, so the stations keep trusting the new server certificate. Losing it
means creating a new CA and **flashing every station again** with the new
`ca.crt`.

### Broker passwords

One password per MQTT user: each station, by its `DEVICE_ID`, and the backend.
On the operator workstation, from the repository root:

```sh
key_vault_name="$(terraform -chdir=terraform output -raw key_vault_name)"
scripts/create-mqtt-password.sh "$key_vault_name" weather-station-backend
scripts/create-mqtt-password.sh "$key_vault_name" station-01
```

Each run **generates a new password**, stores it and prints it. Copy the
station's password into `MQTT_PASSWORD` in the firmware's `secrets.h`; the
backend's needs no copy, because Ansible writes it to `.env`. Passwords are
hexadecimal, so they need no quoting in `.env` or in C strings.

Rotating a password is the same command followed by `deploy.yaml`, plus a new
firmware upload for a station.

## Host configuration

`ansible/` prepares the VM created by `terraform/`. `configure.yaml` installs
packages; `deploy.yaml` copies the production files and starts the stack.

| Role | What it does |
| ---- | ------------ |
| `update-os` | Upgrades every package, removes orphans and cleans the **apt cache** |
| `base-packages` | Installs `git`, `curl`, `jq` and other utilities, and sets the **timezone** |
| `docker-install` | Installs **Docker Engine** with **Compose v2** and **Buildx** from **Docker's repository**, rotates container logs and adds `azureuser` to the `docker` group |
| `azure-cli` | Installs the **Azure CLI** from **Microsoft's repository** |
| `weather-platform` | Installs the **production stack** and starts it — run by `deploy.yaml`, not by `configure.yaml` |

The **Azure CLI** is what lets the VM pull from the registry with its **managed
identity**, without any stored password:

```sh
az login --identity
az acr login --name <acr_name>
```

The **registry token** lasts about **3 hours**. Log in again **before each
deployment**; containers that are already running are not affected.

### Usage

It requires **ansible-core 2.15 or later**. SSH reaches the VM only from
`ssh_allowed_cidrs`, as `azureuser`, with the key set in `ssh_public_key`.

`ansible_host` in `ansible/inventory/azure.yaml` is the project domain, so its
**A record must already exist**; see [Domain](#domain). Then:

```sh
cd ansible
ansible-galaxy collection install -r requirements.yaml
ansible-playbook playbooks/configure.yaml
```

Run the commands **from `ansible/`**: Ansible reads `ansible.cfg` from the
**current directory**, and that file points at the inventory and the roles.

The **first connection** records the VM's host key in `~/.ssh/known_hosts`. A
**different key later** stops the run. That is expected only if the VM was
**replaced**: then remove the old entry with
`ssh-keygen -R weather-station.thomaspalma.com.br`.

The VM **reboots on its own** when an upgrade needs it, for example after a
**new kernel**, and only then: the role checks for `/var/run/reboot-required`
first. Set `update_os_reboot_if_required` to `false` in the role's defaults to
keep the reboot manual.

### Deployment

`playbooks/deploy.yaml` runs the `weather-platform` role, which puts the whole
stack in `/opt/weather-station/` on the VM:

| File | Contents |
| ---- | -------- |
| `docker-compose.yaml` | Copied from `compose/docker-compose.prod.yaml`: the **six services** |
| `.env` | The **registry** and application image versions, the InfluxDB settings and the backend's broker credentials; readable by `root` only |
| `init-influxdb.sh` | Copied from `compose/`; creates the database on startup, then the `influxdb-init` service exits |
| `nginx.conf` | Copied from `edge/` |
| `mosquitto/config/mosquitto.conf` | Copied from `compose/mosquitto/config/mosquitto.prod.conf` |
| `mosquitto/config/aclfile` | Copied from `compose/mosquitto/config/` |
| `mosquitto/config/passwordfile` | Generated from the Key Vault passwords and hashed with `mosquitto_passwd` |
| `mosquitto/config/certs/` | The broker certificate and key, from Key Vault |
| `deploy.sh` | Puts **one new version** in production |

Every file is copied **as it is in this repository**, and the role renders no
templates, so what you read here is what runs on the VM. The only generated
files are the secrets above. The two application images are named by
**version**, never `latest`:

```yaml
image: ${ACR_LOGIN_SERVER}/weather-station-backend:${BACKEND_VERSION:?}
```

The `:?` makes Docker Compose **refuse to start** when the variable is missing,
instead of quietly falling back to `latest`.

The **first run** needs the broker certificate and every password already in
Key Vault (see [Secrets](#secrets)), and both versions already published to
the registry:

```sh
ansible-playbook playbooks/deploy.yaml \
    -e weather_platform_backend_version=1.0.0 \
    -e weather_platform_frontend_version=1.0.0
```

After that, the pipelines own the **backend and frontend version lines** in
`.env`; Ansible leaves those unchanged. The role reconciles
`INFLUXDB_DATABASE`, `INFLUXDB_RETENTION_PERIOD`, `INFLUXDB_QUERY_FILE_LIMIT`,
`HISTORICAL_CACHE_RETENTION_DAYS` and the backend's `MQTT_BACKEND_USERNAME`
and `MQTT_BACKEND_PASSWORD` on every deployment.

The **password file is regenerated only when a password changes**: the role
keeps a SHA-256 digest of the credentials next to it and compares it on each
run. A new certificate, password or ACL **restarts only Mosquitto**; the ESP32
boards reconnect on their own within seconds.

### Releases

`deploy.sh` is what the **application pipelines** call, through
**`az vm run-command`**, so the VM needs **no inbound SSH** for a release:

```sh
/opt/weather-station/deploy.sh backend 1.0.2
```

It rewrites that version in `.env`, signs in to the registry with the VM's
**managed identity**, pulls the image and recreates **only that service**. It
**builds nothing**: the image must already exist in the registry.

Each application is released on its own, by **tagging its repository**. To roll
back, run the script with the **previous version** — the image is still in the
registry, so nothing is rebuilt.

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

- `server_name` in `edge/nginx.conf` is the project domain,
  `weather-station.thomaspalma.com.br`, and its **A record must already resolve** to the
  VM: Let's Encrypt validates the name over port `80` before issuing the
  certificate. See [Domain](#domain).
- Build the **frontend** **without** `VITE_WEATHER_API_URL`. Its empty default
  leaves the API calls **relative**, so they resolve against the page's own
  origin — which the edge serves. The same image then works behind **any
  domain**, and `WEATHER_ALLOWED_ORIGINS` can stay empty.
- The production Compose file sets `FORWARDED_ALLOW_IPS: "*"`. Without it, the
  server **ignores** the `X-Forwarded-*` headers the edge sends, because
  requests arrive from the **Docker bridge**, not from `127.0.0.1`. Trusting
  every address is safe only because the backend port is **bound to
  `127.0.0.1`**.

### Start

The edge is **one of the services** in the production stack, so
[`deploy.yaml`](#deployment) starts it along with the rest. Its two settings
that matter are already in the compose file:

- **`network_mode: host`** lets it reach `127.0.0.1:8000` and `127.0.0.1:8080`
  and listen on ports `80` and `443` of the VM directly.
- The **`edge-acme` volume must be kept**. It stores the **ACME account**, the
  **certificate** and its **private key**. Without it, every restart requests a
  **new certificate**, and Let's Encrypt allows only **5 identical
  certificates per week**. `docker compose down -v` deletes it.

On the **first deployment**, point `uri` in `edge/nginx.conf` at the
**staging** directory, `https://acme-staging-v02.api.letsencrypt.org/directory`,
and switch back to production once the certificate is issued. Delete the
`edge-acme` volume when switching, so the staging account and certificate are
discarded.

### Verify

```sh
curl -I http://weather-station.thomaspalma.com.br                                    # 301 to https
curl https://weather-station.thomaspalma.com.br/healthz                              # ok, from the frontend
curl -N https://weather-station.thomaspalma.com.br/api/v1/readings/station-01/stream # live readings
docker logs edge                                                                     # access log, real client addresses
```

## Security

The **production broker is closed**: port `8883` is open to the internet,
because the ESP32 boards connect from **dynamic addresses**, but every client
needs **TLS**, a **password** and an **ACL** entry. See
[Production broker](#production-broker).

The **development** broker keeps `allow_anonymous true` on port `1883`, which
is acceptable only on a **development LAN**.

One setting is still **open** and must be changed before this stack serves
real users:

- **`--without-auth`**: the InfluxDB API accepts **any request**, including
  deletes. Its port is bound to `127.0.0.1`, so only processes on the VM reach
  it. Remove the flag and issue an **admin token**.
