# dokku-synology-dns

A [Dokku](https://dokku.com) DNS plugin for Synology DSM. Automatically adds and removes A records in DSM's bind9 zone file when apps are deployed or destroyed, then reloads named via `rndc`.

## How it works

- On `post-deploy`: adds an A record for each app vhost that belongs to your configured zone, bumps the SOA serial, and calls `rndc reload <zone>`
- On `pre-delete`: removes the A record(s), bumps serial, reloads

DSM's DNS Server package runs a real bind9 instance. The zone files are plain text at a known path. No UI interaction required.

## Requirements

- Synology DSM 7.x with the **DNS Server** package installed and running
- Dokku 0.30.0+
- `rndc` available on the host (included with the DNS Server package)

## Installation

```bash
dokku plugin:install https://github.com/pjaol/dokku-synology-dns.git synology-dns
```

## Configuration

Set these globally once:

```bash
dokku config:set --global SYNO_DNS_ZONE=home.arpa
dokku config:set --global SYNO_NAS_IP=192.168.0.74
```

| Variable | Description | Example |
|---|---|---|
| `SYNO_DNS_ZONE` | The bind9 zone name managed by DSM DNS Server | `home.arpa` |
| `SYNO_NAS_IP` | IP address all app A records should point to | `192.168.0.74` |

All apps route to the same NAS IP — the proxy (e.g. dokku-synology-proxy or DSM's reverse proxy) differentiates by hostname.

## Zone file location

The plugin writes to:
```
/var/packages/DNSServer/target/named/etc/zone/master/<SYNO_DNS_ZONE>
```

This is where DSM DNS Server stores its master zone files.

## Usage

```bash
# Set domain for an app
dokku domains:set myapp myapp.home.arpa

# Deploy — DNS record is created automatically
git push dokku main

# Destroy — DNS record is removed automatically
dokku apps:destroy myapp
```

## Pair with dokku-synology-proxy

Use [dokku-synology-proxy](https://github.com/pjaol/dokku-synology-proxy) to automatically configure DSM's nginx reverse proxy when you deploy.

## Tested on

- Synology DS920+ (DSM 7.2, Intel Celeron J4125, DNS Server 2.2.3)
