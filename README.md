# dokku-synology

Dokku plugins that integrate with Synology DSM's native nginx and bind9 DNS — so you get a full PaaS deploy workflow (`git push` → live app with DNS + reverse proxy) without fighting DSM's web UI.

## What's included

| Plugin | What it does |
|---|---|
| `synology-proxy` | Writes nginx server blocks into DSM's drop-in conf dir (`/usr/local/etc/nginx/conf.d/`) and reloads nginx on deploy/destroy |
| `synology-dns` | Adds/removes A records in DSM DNS Server's bind9 zone file and reloads named via `rndc` on deploy/destroy |

Both plugins use the same stable, DSM-internal mechanisms that Synology's own packages use. No UI scraping. No unofficial APIs. Survives DSM updates.

## Requirements

- Synology DSM 7.x (tested on DS920+, DSM 7.2)
- Dokku 0.30.0+ installed on the NAS
- Synology **DNS Server** package (optional — only needed for the DNS plugin)

## One-line install

Run this on your NAS as root:

```bash
curl -fsSL https://raw.githubusercontent.com/pjaol/dokku-synology/main/install.sh | sudo bash
```

The installer:
1. Clones this repo to `/var/lib/dokku/plugins/src/dokku-synology`
2. Symlinks both plugins into Dokku's plugin directory
3. Auto-detects whether DNS Server is installed
4. Prompts for your zone name and NAS IP if the DNS plugin is enabled

## One-time DSM setup

Move DSM's web UI off ports 80/443 so Dokku can own them:

**DSM → Control Panel → Login Portal → DSM tab**
- HTTP port: `8880`
- HTTPS port: `8443`

After this, access DSM at `http://nas-ip:8880`. This is a one-time change.

## Manual installation

```bash
# Proxy plugin only
dokku plugin:install https://github.com/pjaol/dokku-synology.git synology-proxy --committish main

# DNS plugin (requires Synology DNS Server package)
dokku plugin:install https://github.com/pjaol/dokku-synology.git synology-dns --committish main

# Configure DNS plugin
dokku config:set --global SYNO_DNS_ZONE=home.arpa
dokku config:set --global SYNO_NAS_IP=192.168.0.74
```

## Usage

```bash
# Create and configure an app
dokku apps:create myapp
dokku proxy:set myapp synology
dokku domains:set myapp myapp.home.arpa

# Set environment variables, link databases, etc.
dokku config:set myapp KEY=value

# Deploy
git remote add dokku dokku@nas:myapp
git push dokku main
```

On deploy, the plugins automatically:
- Add `myapp.home.arpa → <NAS IP>` to the DNS zone (if DNS plugin is enabled)
- Write `/usr/local/etc/nginx/conf.d/dokku-myapp.conf` routing `myapp.home.arpa` to the container
- Reload both nginx and named

On `dokku apps:destroy myapp`, both the DNS record and nginx conf are removed.

## How it works

### Proxy plugin

DSM 7 nginx loads `include /usr/local/etc/nginx/conf.d/*.conf;` — the same mechanism Synology uses for its own packages (Photos, Drive, etc.). The proxy plugin writes one file per app there and calls `nginx -s reload`. DSM's UI-managed `server.ReverseProxy.conf` is never touched.

### DNS plugin

DSM's DNS Server package runs a real bind9 instance. Zone files live at:
```
/var/packages/DNSServer/target/named/etc/zone/master/<zone>
```
The DNS plugin appends/removes A records directly and calls `rndc reload <zone>`. The SOA serial is bumped on every change.

## Configuration reference

| Variable | Scope | Description |
|---|---|---|
| `SYNO_DNS_ZONE` | global | bind9 zone name (e.g. `home.arpa`) |
| `SYNO_NAS_IP` | global | IP all app A records resolve to |

## Tested on

- Synology DS920+ · DSM 7.2 · Intel Celeron J4125
- DNS Server 2.2.3
- Dokku 0.34.x
