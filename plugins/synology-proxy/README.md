# dokku-synology-proxy

A [Dokku](https://dokku.com) proxy plugin for Synology DSM. Instead of using Dokku's built-in nginx or requiring you to fight DSM for port 80/443, this plugin writes nginx server blocks directly into DSM's drop-in conf directory (`/usr/local/etc/nginx/conf.d/`) and reloads DSM's nginx — the same mechanism DSM itself uses for packages like Synology Photos and SynologyDrive.

## How it works

- On `proxy-build-config` (after deploy): writes `/usr/local/etc/nginx/conf.d/dokku-<appname>.conf` and runs `nginx -s reload`
- On `proxy-clear-config` (on destroy/disable): removes the conf file and reloads nginx

No DSM UI interaction. No fragile API scraping. Survives DSM updates.

## Requirements

- Synology DSM 7.x
- Dokku 0.30.0+
- Dokku running on the NAS host (or in a container with host network access)

## Installation

```bash
dokku plugin:install https://github.com/pjaol/dokku-synology-proxy.git synology-proxy
```

Then set it as the proxy for your app:

```bash
dokku proxy:set <app> synology
```

## DSM port setup (one-time)

DSM uses ports 80 and 443 by default for its own web UI. Move DSM off those ports so Dokku can own them:

DSM → Control Panel → Login Portal → DSM tab → change HTTP port to `8880`, HTTPS to `8443`.

After this change, access DSM at `http://nas-ip:8880`.

## Configuration

No per-plugin configuration needed. The plugin reads vhosts from `dokku domains` automatically.

Ensure your app has a domain set:

```bash
dokku domains:set <app> myapp.home.arpa
```

## Pair with dokku-synology-dns

Use [dokku-synology-dns](https://github.com/pjaol/dokku-synology-dns) to automatically create DNS records in DSM's bind9 zone when you deploy.

## Tested on

- Synology DS920+ (DSM 7.2, Intel Celeron J4125)
