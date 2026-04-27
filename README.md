# dokku-synology

Run [Dokku](https://dokku.com) on a Synology NAS — `git push` deploys with automatic DNS and reverse proxy, integrated directly into DSM's native nginx and bind9 DNS. No fighting DSM's web UI.

## What's included

| Component | What it does |
|---|---|
| `dokku/dokku-docker-compose.yaml` | Runs Dokku + rndc-sidecar as Docker containers |
| `plugins/synology-proxy` | On deploy: writes nginx server block to DSM's conf.d and reloads nginx |
| `plugins/synology-dns` | On deploy: adds A record to DSM bind9 zone file, triggers named reload via rndc-sidecar |

Both plugins use the same drop-in mechanisms Synology's own packages use. No UI scraping, no unofficial APIs, survives DSM updates.

## Requirements

- Synology DSM 7.x (tested on DS920+, DSM 7.2, Intel Celeron J4125)
- Docker / Container Manager installed
- Synology **DNS Server** package (optional — enables the DNS plugin)
- `git` installed on the NAS (via Synology package center or entware)

## Install

Run on your NAS as root:

```bash
curl -fsSL https://raw.githubusercontent.com/pjaol/dokku-synology/main/install.sh -o /tmp/install.sh
sudo bash /tmp/install.sh
```

> Note: `bash <(curl ...)` process substitution is not supported on DSM — download first.

The installer:
1. Clones this repo to `/var/lib/dokku-synology`
2. Starts the Dokku + rndc-sidecar containers
3. Installs and enables both plugins inside Dokku
4. Writes a wildcard nginx proxy conf so `*.dokku.<zone>` routes to Dokku

## Post-install setup

**1. Add your SSH public key** (run from your dev machine):
```bash
cat ~/.ssh/id_rsa.pub | ssh root@<nas-ip> 'docker exec -i dokku dokku ssh-keys:add admin'
```

**2. Configure the DNS plugin:**
```bash
docker exec dokku dokku config:set --global SYNO_DNS_ZONE=home.arpa SYNO_NAS_IP=192.168.0.74
```

**3. Verify both plugins:**
```bash
docker exec dokku dokku synology-proxy:test
docker exec dokku dokku synology-dns:test
```

## Deploy an app

```bash
# On your dev machine
git remote add dokku ssh://dokku@<nas-ip>:3022/<appname>
git push dokku main
```

On each deploy Dokku automatically:
- Adds `<appname>.<zone> → <NAS IP>` to DNS
- Writes an nginx vhost routing `<appname>.<zone>` to the container
- Reloads nginx and named

On `dokku apps:destroy <appname>`, both are cleaned up.

## Architecture

```
git push :3022 ──► Dokku container
                        │
                        ├─ builds app image
                        ├─ runs app container
                        ├─ synology-proxy: writes /usr/local/etc/nginx/conf.d/<app>.conf + nginx reload
                        └─ synology-dns:   writes zone file A record + drops trigger in /reload/<zone>

rndc-sidecar (host network) ──► watches /reload/ ──► rndc reload <zone> ──► DSM named

Browser ──► DSM nginx :80
                │
                ├─ *.dokku.home.arpa ──► localhost:8080 ──► Dokku nginx ──► app
                └─ other DSM services unchanged
```

### Why the rndc-sidecar?

The Dokku container runs on the bridge network and can't reach named's rndc port (127.0.0.1:953) directly. The sidecar runs with `network_mode: host` and shares a Docker volume (`dns-reload`) with Dokku. The DNS plugin drops a trigger file; the sidecar picks it up and calls rndc on behalf of Dokku.

## Configuration

| Variable | Scope | Description |
|---|---|---|
| `SYNO_DNS_ZONE` | global | bind9 zone name (e.g. `home.arpa`) |
| `SYNO_NAS_IP` | global | IP all Dokku app A records point to |
| `SYNO_ATTACH_NETWORKS` | global | Docker networks apps can attach to (e.g. `postgres-network`) |

```bash
docker exec dokku dokku config:set --global SYNO_DNS_ZONE=home.arpa SYNO_NAS_IP=192.168.0.74
```

## Managing apps

```bash
docker exec dokku dokku apps:list
docker exec dokku dokku logs <app>
docker exec dokku dokku config:set <app> KEY=value
docker exec dokku dokku ps:report <app>
```

## Tested on

- Synology DS920+ · DSM 7.2 · Intel Celeron J4125
- DNS Server 2.2.3 (BIND 9.16.34)
- Dokku 0.37.10
