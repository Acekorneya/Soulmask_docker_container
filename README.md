# Soulmask Docker Container

Linux-native Soulmask dedicated server container for Steam app `3017300`.

License: Apache-2.0. Attribution to `POK` must be preserved through the included [NOTICE](/mnt/j/Coding_980/Soulmask_docker_container/NOTICE) file when redistributing this project or derivatives.

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
- any multiplier values you want to change from the defaults
- optional published ports if you do not want the defaults

For a normal single server, leave:

- `ENABLE_CLUSTER=false`
- `SOULMASK_GAME_MODE=pve` or `pvp`, whichever you want

### 2. Start the server

The repo already includes the required bind-mount folders. Before first start, make sure `./shared`, `./config`, and `./instances/server_1` are owned by the same Linux user and group as `PUID` and `PGID`.

Example if you use `PUID=1000` and `PGID=1000`:

```bash
sudo chown -R 1000:1000 shared config instances
```

```bash
docker compose pull
docker compose up -d
```

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

If Docker reports `Pool overlaps with other one on this address space`, the problem is the Docker subnet, not the cluster port. Change `SOULMASK_CLUSTER_SUBNET` in `.env` to an unused private `/24` and start again.

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

If you want different multipliers on server 2, add the same `SOULMASK_*_MULTIPLIER` variables to `server_2.env`.
Anything not set there keeps the shared value from `.env`.

### 4. Start server 1 first

```bash
docker compose pull
docker compose up -d
```

### 5. Start server 2 second

Before first start of server 2, make sure `./instances/server_2` is owned by the same Linux user and group as `PUID` and `PGID`.

```bash
docker compose -f docker-compose_server_2.yaml pull
docker compose -f docker-compose_server_2.yaml up -d
```

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

## Gameplay Multipliers

You do not need to edit the Chinese keys in `GameXishu.json` for the common rate settings.

Set the English env vars in `.env`:

- `SOULMASK_EXP_MULTIPLIER`
- `SOULMASK_YIELD_MULTIPLIER`
- `SOULMASK_TAMING_SPEED_MULTIPLIER`
- `SOULMASK_HATCHING_SPEED_MULTIPLIER`
- `SOULMASK_ANIMAL_GROWTH_SPEED_MULTIPLIER`
- `SOULMASK_CROP_GROWTH_SPEED_MULTIPLIER`
- `SOULMASK_TRAINING_GROUND_EXP_MULTIPLIER`
- `SOULMASK_MAX_LOAD_MULTIPLIER`
- `SOULMASK_INVENTORY_SLOTS_MULTIPLIER`

At container startup, the entrypoint writes those values into the live file before the server launches:

- server 1: `./instances/server_1/saved/GameplaySettings/GameXishu.json`
- server 2: `./instances/server_2/saved/GameplaySettings/GameXishu.json`

The image also keeps the per-instance config copy in sync under:

- `config/server_1/GameXishu.json`
- `config/server_2/GameXishu.json`

Public defaults in `.env.example` match the April 2026 official-style PvE profile:

- EXP: `x3`
- Yield: `x3`
- Taming, Hatching, Animal Growth, Crop Growth: `x1.5`
- Training Ground XP: `x3`
- Max Load: `x1`
- Inventory Slots: `x1`

`SOULMASK_INVENTORY_SLOTS_MULTIPLIER` uses the base 60 inventory slots and converts that multiplier into the actual slot count written into `GameXishu.json`.

## Maintenance / Admin CLI

The validated admin/control path for Soulmask in this project is the maintenance port on `SOULMASK_ECHO_PORT`, using the built-in `soulmask-maint` client.

Use `docker exec` from the host:

```bash
docker exec -it soulmask soulmask-maint -t 5 help
docker exec -it soulmask soulmask-maint -t 5 lp
docker exec -it soulmask soulmask-maint saveworld 1
docker exec -it soulmask soulmask-maint fps
```

For server 2:

```bash
docker exec -it soulmask-server-2 soulmask-maint -t 5 help
```

`-t 5` is useful for commands like `help` and `lp` that may take a little longer to return output.

If you still have old `SOULMASK_RCON_*` variables in an existing `.env`, the image now ignores them and logs a warning at startup. Use `soulmask-maint` instead.

## Graceful Shutdown

Container shutdown now uses Soulmask's maintenance port before falling back to process signals.

On `docker compose down` or a normal Docker stop:

1. the entrypoint sends `saveworld 1`
2. it waits for `world.db` to advance when possible
3. it sends `quit <seconds>`
4. if maintenance-port shutdown fails, it falls back to the direct process signal path

The defaults are in [.env.example](/mnt/j/Coding_980/Soulmask_docker_container/.env.example):

- `SOULMASK_SHUTDOWN_DELAY_SECONDS=30`
- `SOULMASK_SAVEWORLD_WAIT_SECONDS=30`

The maintenance client is also available directly:

```bash
docker exec -it soulmask soulmask-maint help
docker exec -it soulmask soulmask-maint saveworld 1
docker exec -it soulmask soulmask-maint quit 30
```

The world save file used for timestamp checks is:

- `WS/Saved/Worlds/Dedicated/Level01_Main/world.db`
- `WS/Saved/Worlds/Dedicated/DLC_Level01_Main/world.db`

## Health Monitoring

The image now includes a built-in health probe at `soulmask-health`.

Docker uses that same probe for the container `healthcheck`, so Docker health status and the direct probe stay aligned.

What the probe checks:

- `WSServer-Linux` is running
- the shared install still exists
- the expected `WS/Saved` path exists
- the game UDP port is listening
- the query UDP port is listening
- the Echo TCP port is listening
- the internal cluster main TCP port is listening on server 1 when cluster mode is enabled

Useful commands:

```bash
docker inspect --format '{{.State.Health.Status}}' soulmask
docker inspect --format '{{range .State.Health.Log}}{{println .Output}}{{end}}' soulmask
docker exec soulmask soulmask-health
```

For server 2:

```bash
docker inspect --format '{{.State.Health.Status}}' soulmask-server-2
docker exec soulmask-server-2 soulmask-health
```

That gives you two layers:

- quick status from Docker: `healthy`, `starting`, or `unhealthy`
- detailed failure reason from `soulmask-health`

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

## Common Maintenance Commands

The authoritative command list is `help` from the running server, because command names and aliases can change between builds.

Common commands that are useful for manual testing and automation:

- `help`
- `lp` to list online players
- `lap` to list all players
- `lg` to list guilds
- `qi` to query the invitation code
- `fps` for server frame rate
- `saveworld 1` to force a save
- `backup my_backup_name` to write a named backup
- `shutdown 60` or `quit 60` to save and stop after a countdown
- `cancelclose` to cancel a pending shutdown
- `sl 0` to pause new logins
- `sl 1` to allow logins again

These are the commands the built-in shutdown path depends on:

- `saveworld 1`
- `quit 30`

Sources:

- Soulmask wiki maintenance port docs: https://soulmask.fandom.com/wiki/Private_Server
- Nitrado save path docs: https://server.nitrado.net/en-US/guides/how-to-upload-a-local-soulmask-save-to-your-nitrado-server
