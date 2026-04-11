# Soulmask Docker Container

Linux-native Soulmask dedicated server container for Steam app `3017300`, designed for two consumers:

- `docker-compose.yaml` for direct self-hosted use
- a future Rust backend + React frontend manager that renders the same Compose and config contract

The image includes a non-root user named `pokuser`. Compose still sets `user: "${PUID}:${PGID}"` so host volume ownership stays correct, and the entrypoint uses `libnss_wrapper` to map the active numeric UID:GID to the username `pokuser` inside the container.

## Layout

```text
.
├── Dockerfile
├── docker-compose.yaml
├── docker-compose.build.yaml
├── entrypoint.sh
├── .env
├── config/
│   └── GameXishu.json.example
├── data/
└── schema/
    └── soulmask-server.schema.json
```

## Quick Start

This repo supports two workflows:

- Publisher workflow: you build and push `acekorneya/soul_server`
- Consumer workflow: users only get the Compose file, `.env`, and `config/`, then pull and run the published image

The main `docker-compose.yaml` is intentionally runtime-only. It pulls `acekorneya/soul_server` and is the same contract the future manager should use.

1. Review `.env` and set both the host wiring values and the server startup values you care about.
2. Leave `config/GameXishu.json` alone unless you want advanced gameplay tuning later.
3. Pull and start the container with `docker compose pull && docker compose up -d`.
4. Inspect logs with `docker compose logs -f soulmask`.

Keep `.env` in the same directory as `docker-compose.yaml` unless you explicitly pass `--env-file`. Compose does not auto-read `config/.env`.

The first boot downloads SteamCMD and the Soulmask Linux dedicated server into `./data`, so later restarts reuse the same files and world state.

The process still runs with the numeric UID:GID from `.env`, but inside the container the username resolves to `pokuser` regardless of which `PUID` and `PGID` you set.

The runtime identity wrapper is applied only to the game process, not to SteamCMD bootstrap/update steps. That keeps the `pokuser` identity visible to the dedicated server while avoiding noisy preload warnings from 32-bit SteamCMD.

`.env` supports comment lines beginning with `#`, and this repo includes annotated comments directly in `.env` and `.env.example` so users can understand each setting without opening the Compose file.

## Persistence

`./data` is the writable host mount used for:

- SteamCMD bootstrap files
- Soulmask server install
- `WS/Saved` data, including world saves and backups
- runtime home directory used by Steam

`./config` is the manager-facing mount used for:

- `GameXishu.json` for gameplay settings
- `GameXishu_<template>.json` when `SOULMASK_COEF_TEMPLATE` is set

The entrypoint copies the host gameplay file into the server tree before launch. If the host gameplay file is missing but the server already has one, the container seeds the host file once and then stops overwriting it.

## Configuration Contract

`.env` is the only file normal users should edit. It contains both Compose wiring and Soulmask startup flags:

- `PUID`, `PGID`
- host bind mount paths
- image name and tag
- restart policy
- published ports
- the internal game, query, echo, and RCON ports
- `AUTO_UPDATE` and `VALIDATE_ON_UPDATE`
- server and admin passwords
- map and game mode
- max players
- save and backup intervals
- RCON settings
- mods
- cluster settings
- template selection and extra args

`config/GameXishu.json` is optional and is only for deeper gameplay settings. It is the canonical gameplay settings file unless `SOULMASK_COEF_TEMPLATE` is set, in which case the canonical filename becomes `config/GameXishu_<template>.json`.

## Manager Mapping

The later Rust manager should treat [`schema/soulmask-server.schema.json`](schema/soulmask-server.schema.json) as the source of truth and render:

- `.env`
- `config/GameXishu*.json`
- `docker-compose.yaml`

Important mappings:

- `compose.puid` -> `PUID`
- `compose.pgid` -> `PGID`
- `compose.hostDataDir` -> `HOST_DATA_DIR`
- `compose.hostConfigDir` -> `HOST_CONFIG_DIR`
- `compose.publishedPorts.*` -> `SOULMASK_PUBLISHED_*`
- `startup.*` -> `SOULMASK_*`
- `gameplay` -> `config/GameXishu*.json`

`startup.mods` is serialized as a comma-separated string into `SOULMASK_MOD_IDS`.

`startup.extraArgs` is serialized as a space-separated string into `SOULMASK_EXTRA_ARGS`. Keep those values shell-safe because they are appended as raw flags.

## Notes

- The container uses bridge networking with explicit port mappings instead of host networking.
- `SOULMASK_ECHO_PORT` is still passed to the server, but the telnet listener is not published by default because Soulmask binds it locally.
- If `AUTO_UPDATE=false`, the container skips SteamCMD updates and expects an existing install under `./data/server`.
- `VALIDATE_ON_UPDATE=true` is supported, but disabled by default because it slows normal restarts.

## Build And Push

If your Linux box stores this project at `/home/factorioserver/Soul_Docker`, build and push with:

```bash
docker build -t acekorneya/soul_server:latest /home/factorioserver/Soul_Docker
docker push acekorneya/soul_server:latest
```

For local image development with Compose instead of raw `docker build`, use:

```bash
docker compose -f docker-compose.yaml -f docker-compose.build.yaml build soulmask
```

For end users and the future manager, keep `SOULMASK_IMAGE=acekorneya/soul_server` and `SOULMASK_TAG=latest`, then run:

```bash
docker compose pull
docker compose up -d
docker compose logs -f soulmask
```
