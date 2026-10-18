# portfolio-deploy

How my portfolio projects get from GitHub onto one Oracle Cloud Always Free
server, and stay there without anyone logging in.

```
push to main ──► GitHub Actions ──► ghcr.io/nafiz001/<project> ──► server pulls every 10 min
 (any project)    amd64 + arm64        multi-arch image               Caddy serves <project>.$DOMAIN
```

## The pieces

- **[`.github/workflows/image.yml`](.github/workflows/image.yml)**: a reusable
  workflow every project calls on push. It builds the project's Dockerfile on a
  native amd64 runner and a native arm64 runner (no QEMU, so Rust and .NET
  compile at full speed), pushes both by digest and joins them under one tag.
  The same image runs on Oracle's AMD micro shape and its Ampere A1 shape.
- **[`server/compose.yml`](server/compose.yml)**: every project, with a memory
  limit each, behind one Caddy that terminates HTTPS. Only Caddy is published,
  apart from gedis, which speaks the Redis protocol on 6380.
- **[`server/Caddyfile`](server/Caddyfile)**: one site per project at
  `<project>.$DOMAIN`, with certificates fetched and renewed by Caddy.
- **[`server/update.sh`](server/update.sh)**: pulls this repository and the
  latest images, restarts only what changed. A systemd timer runs it every
  10 minutes, so a push to any project is live a few minutes after its image
  is built.
- **[`vernissage/`](vernissage)**: the Ampere server (2 OCPU, 12 GB), for
  [Vernissage](https://github.com/Nafiz001/vernissage): its Go server and
  PostgreSQL behind Caddy at `api.<ip>.sslip.io`. The Next.js site runs on
  Vercel and forwards the API, pictures and posters here; only the live
  rooms' WebSocket connects directly, with a short-lived signed ticket.
- **[`server/install.sh`](server/install.sh)**: one-time setup on a fresh
  Ubuntu server with Docker: clones this repository, writes the stack's
  `.env` with its `init-env.sh` (domains and random secrets), installs the
  timer and starts everything. `STACK=vernissage` sets up the second server.
- **[`oracle/retry_a1.py`](oracle/retry_a1.py)**: free Ampere capacity in a
  busy region is often exhausted. This calls LaunchInstance every three minutes,
  alternating the full and half free size, backs off when rate-limited, and stops on any
  other error or once an Ampere server exists.

## Running now

| Project | What it is | Stack |
|---|---|---|
| [ebru](https://github.com/Nafiz001/ebru) | a shared marbling tray | Rust, axum, WebAssembly, Vue |
| [kirie](https://github.com/Nafiz001/kirie) | a pop-up paper book of live weather | ASP.NET Core, SignalR, SvelteKit |
| [asterism](https://github.com/Nafiz001/asterism) | a stargazing app, web build | Expo, React Native Skia |
| [lumen](https://github.com/Nafiz001/lumen) | a search engine from scratch | Go standard library |
| [gedis](https://github.com/Nafiz001/gedis) | a Redis-compatible store from scratch | Go |

| [vernissage](https://github.com/Nafiz001/vernissage) | curate and walk through a museum, together | Go, PostgreSQL, Next.js on Vercel |
| [noctiluca](https://github.com/Nafiz001/noctiluca) | a deep-sea dive lit by strangers' messages | Django, Channels, SQLite, Next.js on Vercel |
| [kori](https://github.com/Nafiz001/kori) | a double-entry ledger and payments API | TypeScript, PostgreSQL, Redis |
| [quill](https://github.com/Nafiz001/quill) | a SQL database from scratch, read-only demo on :15433 | Go, PostgreSQL wire protocol |

Each micro server has 1 GB of memory. Vernissage started on the second micro
and moved to the Ampere server once Oracle had capacity (a `pg_dump` piped
into the new database, then the site's two environment variables pointed at
the new API); the heavy projects (noctiluca, kori, quill) can follow it.

## Choices worth explaining

- **Nothing builds on the server.** A 1 GB machine cannot compile Next.js or
  Rust, and it should not have to: images are built once in CI and pulled.
- **Domain from the IP.** `DOMAIN=<ip with dashes>.sslip.io` resolves to the
  server with no DNS to manage. Changing to a real domain is one line in
  `.env` and a wildcard DNS record.
- **gedis is public, so it is fenced.** 32 MB with LRU eviction, no
  persistence, a read-only filesystem, a client cap, and its
  `--disable-commands` flag switching off CONFIG, DEBUG, REPLICAOF, SHUTDOWN,
  SAVE and the replication handshake, so nobody can make it write files or
  connect elsewhere.
- **Vernissage trusts forwarded addresses.** Its API sits behind Vercel and
  Caddy, so Caddy is told to append to `X-Forwarded-For` rather than replace
  it, and the server counts two hops back to find the visitor. Anyone
  calling the API directly could pick the address they are rate-limited
  under, as with any appending proxy; the price of keeping visitors apart.
- **Proxied apps trust the proxy.** Apps that rate-limit by visitor IP read
  `X-Forwarded-For`, which is only safe because their ports are never
  published; Caddy is the only way in.
