# Soulmask Docker Container

Linux-native Soulmask dedicated server container for Steam app `3017300`.

This repo is meant to be easy to run in two ways:

1. Single server with `docker-compose.yaml`
2. Two-map PvE cluster with `docker-compose.yaml` plus `docker-compose_server_2.yaml`

The image includes a non-root user named `pokuser`. Compose still runs with `user: "${PUID}:${PGID}"` so bind-mounted files stay owned by the Linux user you choose on the host.

## Repo Layout

```text
.
├── Dockerfile
├── docker-compose.yaml
├── docker-compose_server_2.yaml
├── entrypoint.sh
├── .env.example
├── server_2.env.example
├── config/
│   ├── GameXishu.json.example
│   ├── server_1/
│   └── server_2/
├── instances/
│   ├── server_1/
│   └── server_2/
└── shared/
```

## Single Server

Use this when you only want one Soulmask server.

### 1. Prepare the config

```bash
cp .env.example .env
```

Edit `.env` and set at least:

- `PUID` and `PGID`
- `TZ`
- `SOULMASK_ADMIN_PASSWORD`
- `SOULMASK_SERVER_NAME`
- `SOULMASK_LEVEL_NAME`
- optional published ports if you do not want the defaults

For a normal single server, leave:

- `ENABLE_CLUSTER=false`
- `SOULMASK_GAME_MODE=pve` or `pvp`, whichever you want

### 2. Start the server

```bash
docker compose pull
docker compose up -d
```

Docker creates the needed runtime folders under `./shared`, `./config`, and `./instances/server_1` on first start.

### 3. Watch logs

```bash
docker compose logs -f soulmask
```

### 4. Stop the server

```bash
docker compose down
```

## Two-Map PvE Cluster

Use this when you want one server for `Level01_Main` and one server for `DLC_Level01_Main`, with character transfer between them.

Cluster mode in this project is intentionally `pve`-only right now.

### What users edit

- `.env` controls server 1 and shared cluster settings
- `server_2.env` controls server 2 only

You do not need to manually set:

- `SOULMASK_SERVER_ID`
- `SOULMASK_CLUSTER_CLIENT_SERVER_CONNECT`
- any internal cluster port

The compose files handle that automatically.

### 1. Prepare the config files

```bash
cp .env.example .env
cp server_2.env.example server_2.env
```

### 2. Edit `.env`

Set these values for the cluster:

- `ENABLE_CLUSTER=true`
- `SOULMASK_GAME_MODE=pve`
- `SOULMASK_SERVER_PASSWORD=` and keep the same password for both maps if you use one
- `SOULMASK_SERVER_NAME`
- `SOULMASK_LEVEL_NAME`

Server 1 is the main cluster node. It can use either map:

- `SOULMASK_LEVEL_NAME=Level01_Main`
- `SOULMASK_LEVEL_NAME=DLC_Level01_Main`

### 3. Edit `server_2.env`

Set the second server to the opposite map from server 1:

- if server 1 uses `Level01_Main`, set server 2 to `DLC_Level01_Main`
- if server 1 uses `DLC_Level01_Main`, set server 2 to `Level01_Main`

You can also change:

- `SOULMASK_SERVER_NAME`
- server 2 optional gameplay overrides

Server 2 already defaults to `AUTO_UPDATE=false` so it reuses the shared install instead of updating it directly.
The internal cluster link port is already handled inside the compose files and does not need host port forwarding.

### 4. Start server 1 first

```bash
docker compose pull
docker compose up -d
```

### 5. Start server 2 second

```bash
docker compose -f docker-compose_server_2.yaml pull
docker compose -f docker-compose_server_2.yaml up -d
```

Docker creates the server 2 runtime folders under `./instances/server_2` on first start.

### 6. Watch logs

```bash
docker compose logs -f soulmask
docker compose -f docker-compose_server_2.yaml logs -f soulmask_server_2
```

### 7. Stop in reverse order

```bash
docker compose -f docker-compose_server_2.yaml down
docker compose down
```

## How The Cluster Works

- `docker-compose.yaml` is server 1 and the main cluster node
- `docker-compose_server_2.yaml` is server 2 and the client node
- server 2 automatically connects to server 1 through the Docker network alias `soulmask-main`
- both containers share one SteamCMD directory and one game install in `./shared`
- each container keeps its own runtime files and save data in its own `./instances/server_X` folder

That means the game files download once, but each map keeps separate saves.

## Storage

`./shared` stores:

- the shared SteamCMD files
- the shared Soulmask server install
- the shared install/update lock

`./instances/server_1` and `./instances/server_2` store:

- per-instance runtime home
- logs
- per-instance `WS/Saved` data

`./config` stores:

- `config/server_1/GameXishu.json`
- `config/server_2/GameXishu.json`
- `config/GameXishu.json.example`

If a per-instance `GameXishu.json` does not exist yet, the entrypoint seeds it from the example file when possible.

## RCON / Admin CLI

If you set `SOULMASK_RCON_PASSWORD`, the image includes a built-in `soulmask-rcon` client that the container manager can call with `docker exec`.

Recommended setup:

- leave `SOULMASK_RCON_ADDRESS=` blank
- set `SOULMASK_RCON_PASSWORD` to enable RCON
- use `docker exec` to run commands from the host or from a future manager

That keeps RCON bound to `127.0.0.1` inside the container by default instead of exposing it broadly on the network.

Examples:

```bash
docker exec -it soulmask soulmask-rcon help
docker exec -it soulmask soulmask-rcon saveworld 1
docker exec -it soulmask soulmask-rcon shutdown 60
docker exec -it soulmask soulmask-rcon --interactive
```

For server 2:

```bash
docker exec -it soulmask-server-2 soulmask-rcon help
```

If you intentionally want network-reachable RCON outside the container, set:

```bash
SOULMASK_RCON_ADDRESS=0.0.0.0
```

and make sure you also restrict access with the Soulmask RCON IP whitelist.

## Cluster Toggle

Soulmask 1.0 stores `KaiQiKuaFu` in sections `"0"`, `"1"`, and `"2"` of `GameXishu.json`.

The container keeps that in sync automatically:

- `ENABLE_CLUSTER=true` writes `KaiQiKuaFu=1`
- `ENABLE_CLUSTER=false` writes `KaiQiKuaFu=0`

Users do not need to edit the JSON by hand just to enable cluster transfers.

## Important Cluster Rules

- Cluster mode is `pve`-only in this project right now
- start server 1 before server 2
- stop server 2 before server 1
- use different maps on server 1 and server 2
- use the same server password on both nodes if you want the smoothest transfer flow
- the internal cluster link stays inside the Docker network and does not need router port forwarding

## Common RCON Commands

The authoritative command list is `help` from the running server, because command names and aliases can change between builds.

Common commands used by managers and admins include:

- `help`
- `saveworld 1`
- `shutdown 60`
- `cancelclose`
- `bk my_backup_name`
- `lp` to list online players
- `fps` for server frame rate
- `qi` for the invitation code
- `lc` to list coefficient values
- `sc <name> <value>` to change a coefficient
- `Update_RconClientAddress 1 <ip>` to add an RCON-safe IP temporarily
