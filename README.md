# dokku-synology

Run [Dokku](https://dokku.com) on a Synology NAS — `git push` deploys with automatic DNS and reverse proxy, integrated directly into DSM's native nginx and bind9 DNS. No fighting DSM's web UI.

## What's included

| Component | What it does |
|---|---|
| `dokku/dokku-docker-compose.yaml` | Runs Dokku as a Docker container on the NAS |
| `plugins/synology-proxy` | On deploy: writes nginx server block to DSM's drop-in conf dir and reloads nginx. On destroy: removes it. |
| `plugins/synology-dns` | On deploy: adds A record to DSM bind9 zone file and reloads named. On destroy: removes it. |

Both plugins use the same stable drop-in mechanisms Synology's own packages use. No UI scraping, no unofficial APIs, survives DSM updates.

## Requirements

- Synology DSM 7.x (tested on DS920+, DSM 7.2, Intel Celeron J4125)
- Docker / Container Manager installed on the NAS
- Synology **DNS Server** package (optional — enables the DNS plugin)

## One-line install

Run this on your NAS as root:

```bash
curl -fsSL https://raw.githubusercontent.com/pjaol/dokku-synology/main/install.sh | sudo bash
```

This will:
1. Clone this repo to `/var/lib/dokku-synology`
2. Start the Dokku Docker container
3. Install and enable both plugins inside Dokku
4. Write a wildcard nginx proxy conf so `*.dokku.home.arpa` routes to Dokku
5. Prompt for your DNS zone and NAS IP if the DNS Server package is detected

## Architecture

```
git push :3022 ──► Dokku container
                        │
                        ├─ builds app image (from your registry or Dockerfile)
                        ├─ runs app container
                        ├─ synology-proxy: writes /usr/local/etc/nginx/conf.d/dokku-<app>.conf
                        └─ synology-dns:   adds <app>.home.arpa A record

Browser ──► DSM nginx :80/:443
                │
                ├─ *.dokku.home.arpa ──► localhost:8080 ──► Dokku nginx ──► app
                └─ other *.home.arpa ──► existing DSM reverse proxy rules
```

Dokku's internal nginx runs on port 8080 (mapped from the container). DSM's nginx fronts everything on 80/443 and stays in control of TLS.

## After install: one-time steps

**1. Add your SSH public key:**
```bash
cat ~/.ssh/id_rsa.pub | ssh root@<nas-ip> 'docker exec -i dokku dokku ssh-keys:add admin'
```

**2. Add wildcard DNS for Dokku apps** (in DSM DNS Server UI or directly):
```bash
# Append to zone file and reload
echo '*.dokku.home.arpa.  86400  A  192.168.0.74' >> \
  /var/packages/DNSServer/target/named/etc/zone/master/home.arpa
rndc reload home.arpa
```

## Deploy an app

```bash
# On your dev machine
git remote add dokku ssh://dokku@<nas-ip>:3022/myapp
git push dokku main
```

Dokku builds the app, starts it, and the plugins automatically:
- Add `myapp.home.arpa → <NAS IP>` to DNS
- Write an nginx vhost conf routing `myapp.home.arpa` to the container
- Reload nginx and named

On `dokku apps:destroy myapp`, both are removed.

## Managing apps

```bash
docker exec dokku dokku apps:list
docker exec dokku dokku logs myapp
docker exec dokku dokku config:set myapp KEY=value
docker exec dokku dokku ps:report myapp
```

## How the plugins work

### synology-proxy

DSM 7 nginx loads `include /usr/local/etc/nginx/conf.d/*.conf;` — the same drop-in mechanism Synology uses for Photos, Drive, and other packages. The proxy plugin writes one file per Dokku app there and signals nginx via its pid file. DSM's `server.ReverseProxy.conf` is never touched.

The Dokku container mounts:
- `/usr/local/etc/nginx/conf.d` — to write confs
- `/bin/nginx` → `/usr/sbin/nginx` — to call `nginx -s reload`
- `/run/nginx.pid` — so nginx signal delivery works

### synology-dns

DSM's DNS Server package is a real bind9 instance. The plugin writes directly to the zone file at:
```
/var/packages/DNSServer/target/named/etc/zone/master/<zone>
```
It bumps the SOA serial and calls `rndc reload <zone>`. The named directory is mounted into the Dokku container.

## Configuration reference

| Variable | Scope | Description |
|---|---|---|
| `SYNO_DNS_ZONE` | global | bind9 zone name (e.g. `home.arpa`) |
| `SYNO_NAS_IP` | global | IP all Dokku app A records resolve to |

Set via: `docker exec dokku dokku config:set --global SYNO_DNS_ZONE=home.arpa SYNO_NAS_IP=192.168.0.74`

## Manual plugin install (if Dokku is already running)

```bash
docker exec dokku dokku plugin:install https://github.com/pjaol/dokku-synology.git synology-proxy
docker exec dokku dokku plugin:install https://github.com/pjaol/dokku-synology.git synology-dns
docker exec dokku dokku config:set --global SYNO_DNS_ZONE=home.arpa SYNO_NAS_IP=192.168.0.74
```

## Tested on

- Synology DS920+ · DSM 7.2 · Intel Celeron J4125 · Docker 24.0.2
- DNS Server 2.2.3
- Dokku 0.37.10
