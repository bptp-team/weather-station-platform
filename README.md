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
| `compose/` | The **Docker Compose** files: the two services for **local development**, and the **whole stack** for production |
| `terraform/` | **Azure** resources that host the system: **VM**, **network** and **container registry** |
| `ansible/` | **Packages** installed on that VM, and the **production stack** it runs |
| `edge/` | **Nginx** in front of the **frontend** and **backend**: **TLS** and **routing** |

The two halves are **independent**. `compose/` is what you run for **local
development**; `terraform/` provisions the **machine** where that same stack
runs in **production**, and `ansible/` installs what that machine needs to run
it. `edge/` runs **only in production**, on that machine.

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

At backend startup, the configured database is created with a **15-day data
retention period**. Points older than 15 days expire under this policy. This
applies only to newly created databases; an existing database is left unchanged
and requires a separate migration to adopt the policy. The **backend** defaults
already target this service:

Retention is configured by the **backend**, not by Docker Compose. The production
Compose file starts the backend, which requests the 15-day policy at startup when
creating a new database. The development Compose file starts only Mosquitto and
InfluxDB, so the backend must be run separately for this initialization to occur.
No Compose retention setting is needed; deploy the updated backend to apply the
policy to databases created from then on.

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
| `1883` | 120 | `Internet` | **MQTT ingestion** from the ESP32 boards (dynamic addresses) |

`ssh_allowed_cidrs` **must** be set — the module refuses an empty list and
`0.0.0.0/0`. Use **your own address with a `/32` mask**; get it with
`curl -4 -s ifconfig.me`.

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

Fill in `subscription_id`, `ssh_allowed_cidrs`, `ssh_public_key`, `dns_label`
and `acr_name`. The example file carries the command for each value. Then:

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
| `public_ip_address` | Reaching the VM |
| `public_fqdn` | `<dns_label>.mexicocentral.cloudapp.azure.com` — the **broker address** the firmware connects to and `server_name` in `edge/nginx.conf` |
| `acr_login_server` | **Registry hostname** used in image tags |
| `acr_name` | `az acr login --name <value>` |
| `resource_group_name` | Scoping `az` commands |
| `vm_name` | Scoping `az` commands |

### What is not automated

Terraform provisions the **host and nothing more**. Everything above it comes
from `ansible/`: the packages, the production stack and each release. See
[Host configuration](#host-configuration).

## Host configuration

`ansible/` prepares the VM created by `terraform/`. It **installs packages
only**: it does not copy files or start containers.

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

`ansible_host` in `ansible/inventory/azure.yaml` **must match** the
`public_fqdn` output. Then:

```sh
cd ansible
ansible-galaxy collection install -r requirements.yaml
ansible-playbook playbooks/configure.yaml
```

Run the commands **from `ansible/`**: Ansible reads `ansible.cfg` from the
**current directory**, and that file points at the inventory and the roles.

The **first connection** records the VM's host key in `~/.ssh/known_hosts`. A
**different key later** stops the run. That is expected only if the VM was
**replaced**: then remove the old entry with `ssh-keygen -R <public_fqdn>`.

The VM **reboots on its own** when an upgrade needs it, for example after a
**new kernel**, and only then: the role checks for `/var/run/reboot-required`
first. Set `update_os_reboot_if_required` to `false` in the role's defaults to
keep the reboot manual.

### Deployment

`playbooks/deploy.yaml` runs the `weather-platform` role, which puts the whole
stack in `/opt/weather-station/` on the VM:

| File | Contents |
| ---- | -------- |
| `docker-compose.yaml` | Copied from `compose/docker-compose.prod.yaml`: the **five services** |
| `.env` | The **registry** and the **version** of each application image |
| `nginx.conf` | Copied from `edge/` |
| `mosquitto/config/mosquitto.conf` | Copied from `compose/` |
| `deploy.sh` | Puts **one new version** in production |

Every file is copied **as it is in this repository** — the role renders no
templates, so what you read here is what runs on the VM. The two application
images are named by **version**, never `latest`:

```yaml
image: ${ACR_LOGIN_SERVER}/weather-station-backend:${BACKEND_VERSION:?}
```

The `:?` makes Docker Compose **refuse to start** when the variable is missing,
instead of quietly falling back to `latest`.

The **first run** needs both versions, which must already be published to the
registry:

```sh
ansible-playbook playbooks/deploy.yaml \
    -e weather_platform_backend_version=1.0.0 \
    -e weather_platform_frontend_version=1.0.0
```

After that, `.env` is **never rewritten** by Ansible — the template carries
`force: false`. **The pipelines own those two lines.** Rendering them again
would roll production back to whatever the defaults say.

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

- `server_name` in `edge/nginx.conf` **must match** the `public_fqdn` output.
  The file carries `weather-station.mexicocentral.cloudapp.azure.com`, the name
  produced by the example `dns_label`.
- Build the **frontend** **without** `VITE_WEATHER_API_URL`. Its empty default
  leaves the API calls **relative**, so they resolve against the page's own
  origin — which the edge serves. The same image then works behind **any
  domain**, and `WEATHER_ALLOWED_ORIGINS` can stay empty.
- Run the **backend** with `-e FORWARDED_ALLOW_IPS='*'`. Without it, the server
  **ignores** the `X-Forwarded-*` headers the edge sends, because requests
  arrive from the **Docker bridge**, not from `127.0.0.1`. Trusting every
  address is safe only because the backend port is **bound to `127.0.0.1`**.

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
