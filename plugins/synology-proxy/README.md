# synology-proxy

A Dokku proxy plugin for Synology DSM. Writes nginx server blocks directly into DSM's drop-in conf directory (`/usr/local/etc/nginx/conf.d/`) and reloads DSM's nginx — the same mechanism DSM itself uses for packages like Synology Photos and SynologyDrive.

## How it works

- On `proxy-build-config` (after deploy): writes `/usr/local/etc/nginx/conf.d/dokku-<appname>.conf` and signals nginx to reload
- On `proxy-clear-config` (on destroy/disable): removes the conf file and reloads nginx

DSM nginx proxies `*.dokku.<zone>` → Dokku container on port 8080. The per-app conf inside Dokku routes by hostname to the app container.

No DSM UI interaction. No fragile API scraping. Survives DSM updates.

## Requirements

- Synology DSM 7.x
- Dokku 0.30.0+
- Installed via [dokku-synology](https://github.com/pjaol/dokku-synology)

## Installation

Installed automatically by the [dokku-synology](https://github.com/pjaol/dokku-synology) installer. To install manually:

```bash
docker exec dokku bash -c "
  curl -fsSL https://github.com/pjaol/dokku-synology/releases/latest/download/synology-proxy.tar.gz \
    | tar -xz -C /tmp --one-top-level=synology-proxy &&
  cp -r /tmp/synology-proxy /var/lib/dokku/plugins/available/synology-proxy &&
  dokku plugin:enable synology-proxy &&
  bash /var/lib/dokku/plugins/available/synology-proxy/install
"
docker exec dokku dokku proxy:set --global synology
```

## Configuration

The installer sets the global proxy type automatically:

```bash
docker exec dokku dokku proxy:set --global synology
```

No per-app configuration needed. The plugin reads vhosts from `dokku domains` automatically.

## Verify

```bash
docker exec dokku dokku synology-proxy:test
```

## Pair with synology-dns

Use the [synology-dns](../synology-dns/) plugin to automatically create DNS records in DSM's bind9 zone on deploy.

## Tested on

- Synology DS920+ · DSM 7.2 · Intel Celeron J4125
- Dokku 0.37.10
