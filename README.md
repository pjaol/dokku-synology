# dokku-synology

Run [Dokku](https://dokku.com) on a Synology NAS — `git push` deploys with automatic reverse proxy through DSM's native nginx.

## How it works

```
git push :3022 ──► Dokku container (port 8080)
                        │
                        └─ builds image, runs app container, manages nginx vhosts

Browser ──► DSM nginx :80
                │
                └─ *.dokku.home.arpa ──► 127.0.0.1:8080 ──► Dokku nginx ──► app
```

- DSM nginx has one static wildcard conf routing `*.dokku.<zone>` → Dokku on port 8080
- Dokku's own nginx handles per-app routing by `Host:` header — no per-app DSM config needed
- DNS: your router forwards `*.dokku.<zone>` to the NAS (wildcard — works for all apps automatically)

## Requirements

- Synology DSM 7.x
- Container Manager installed
- `git` installed on the NAS (via Synology Package Center or Entware)
- Router configured to forward `dokku.<zone>` DNS queries to the NAS

## Install

Run on your NAS as root:

```bash
curl -fsSL https://raw.githubusercontent.com/pjaol/dokku-synology/main/install.sh -o /tmp/install.sh
sudo bash /tmp/install.sh
```

> Note: `bash <(curl ...)` process substitution is not supported on DSM's ash shell — download first.

The installer:
1. Clones this repo to `/var/lib/dokku-synology`
2. Starts the Dokku container (docker sock + named volume only)
3. Writes `/etc/nginx/sites-enabled/dokku-wildcard.conf` and reloads DSM nginx

## Post-install

**Add your SSH public key** (run from your dev machine):
```bash
cat ~/.ssh/id_rsa.pub | ssh root@<nas-ip> 'docker exec -i dokku dokku ssh-keys:add admin'
```

## Deploy an app

```bash
git remote add dokku ssh://dokku@<nas-ip>:3022/<appname>
git push dokku main
```

App is available at `http://<appname>.dokku.home.arpa` — no extra config needed.

## Managing apps

```bash
docker exec dokku dokku apps:list
docker exec dokku dokku logs <app>
docker exec dokku dokku config:set <app> KEY=value
docker exec dokku dokku ps:report <app>
```

## Optional: synology-dns plugin

The `plugins/synology-dns` directory contains a Dokku plugin that automatically adds/removes DNS A records in DSM's bind9 zone file on deploy. This is only needed if your router cannot forward wildcard DNS for `*.dokku.<zone>` and you need per-app DNS records managed explicitly.

See [`plugins/synology-dns/README.md`](plugins/synology-dns/README.md) for setup instructions.

## Tested on

- Synology DS920+ · DSM 7.2 · Intel Celeron J4125
- Dokku 0.37.10
