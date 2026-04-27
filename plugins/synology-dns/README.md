# synology-dns

A Dokku plugin that automatically adds and removes DNS A records in DSM's bind9 zone file when apps are deployed or destroyed, then reloads named via the rndc-sidecar.

## How it works

- On `post-deploy`: adds an A record for each app vhost in your configured zone, bumps the SOA serial, and drops a trigger file for the rndc-sidecar to reload named
- On `pre-delete`: removes the A record(s), bumps serial, triggers reload

DSM's DNS Server package runs a real bind9 instance. Zone files are plain text at a known path. No UI interaction required.

## Requirements

- Synology DSM 7.x with the **DNS Server** package installed and running
- Installed via [dokku-synology](https://github.com/pjaol/dokku-synology) — the rndc-sidecar container must be running alongside Dokku

## Installation

Installed automatically by the [dokku-synology](https://github.com/pjaol/dokku-synology) installer. To install manually:

```bash
docker exec dokku bash -c "
  curl -fsSL https://github.com/pjaol/dokku-synology/releases/latest/download/synology-dns.tar.gz \
    | tar -xz -C /tmp --one-top-level=synology-dns &&
  cp -r /tmp/synology-dns /var/lib/dokku/plugins/available/synology-dns &&
  dokku plugin:enable synology-dns &&
  bash /var/lib/dokku/plugins/available/synology-dns/install
"
```

## Configuration

Set these once after install:

```bash
docker exec dokku dokku config:set --global SYNO_DNS_ZONE=home.arpa SYNO_NAS_IP=192.168.0.74
```

| Variable | Description | Example |
|---|---|---|
| `SYNO_DNS_ZONE` | The bind9 zone name managed by DSM DNS Server | `home.arpa` |
| `SYNO_NAS_IP` | IP address all app A records point to | `192.168.0.74` |

All apps route to the same NAS IP — DSM nginx (via synology-proxy) routes by hostname.

## Router setup

Dokku apps are served under `<app>.dokku.<zone>` — a subdomain of a subdomain. Your router's DNS forwarder must cover both:

- `home.arpa` → NAS IP
- `dokku.home.arpa` → NAS IP

If your router only forwards `home.arpa`, queries for `*.dokku.home.arpa` may not reach the NAS.

## Verify

```bash
docker exec dokku dokku synology-dns:test
```

## Zone file location

```
/var/packages/DNSServer/target/named/etc/zone/master/<SYNO_DNS_ZONE>
```

## Tested on

- Synology DS920+ · DSM 7.2 · DNS Server 2.2.3 (BIND 9.16.34)
- Dokku 0.37.10
