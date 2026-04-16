#!/usr/bin/env bash

set -Eeuo pipefail

timestamp() {
  date +"%Y-%m-%d %H:%M:%S%z"
}

log() {
  local level="$1"
  shift
  printf "%s [%s] %s\n" "$(timestamp)" "$level" "$*"
}

die() {
  log ERROR "$*"
  exit 1
}

is_true() {
  case "${1:-false}" in
    1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn])
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

lower() {
  printf "%s" "$1" | tr "[:upper:]" "[:lower:]"
}

require_integer_in_range() {
  local name="$1"
  local value="$2"
  local min="$3"
  local max="$4"

  [[ "$value" =~ ^[0-9]+$ ]] || die "$name must be an integer. Got: $value"

  if (( value < min || value > max )); then
    die "$name must be between $min and $max. Got: $value"
  fi
}

require_number_in_range() {
  local name="$1"
  local value="$2"
  local min="$3"
  local max="$4"

  [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "$name must be a number. Got: $value"

  if ! awk -v value="$value" -v min="$min" -v max="$max" 'BEGIN { exit(value >= min && value <= max ? 0 : 1) }'; then
    die "$name must be between $min and $max. Got: $value"
  fi
}

scaled_inventory_slots() {
  local multiplier="$1"

  awk -v multiplier="$multiplier" 'BEGIN {
    slots = int((60 * multiplier) + 0.5)
    if (slots < 30) {
      slots = 30
    }
    if (slots > 256) {
      slots = 256
    }
    print slots
  }'
}

ensure_writable_dir() {
  local path="$1"
  local label="$2"
  local probe=""

  mkdir -p "$path" 2>/dev/null || die "$label directory '$path' could not be created by uid $(id -u):gid $(id -g). Adjust host ownership or PUID/PGID."

  probe="$path/.write-test-$$"
  : >"$probe" 2>/dev/null || die "$label directory '$path' is not writable by uid $(id -u):gid $(id -g). Adjust host ownership or PUID/PGID."
  rm -f "$probe"
}

seed_gameplay_config_from_example() {
  local host_config_file="$1"
  local exact_example_file="${host_config_file}.example"
  local generic_example_file="$SOULMASK_CONFIG_ROOT_DIR/GameXishu.json.example"
  local generic_template_example_file=""

  generic_template_example_file="$SOULMASK_CONFIG_ROOT_DIR/$(basename "$host_config_file").example"

  if [[ -f "$host_config_file" ]]; then
    return
  fi

  if [[ -f "$exact_example_file" ]]; then
    cp -f "$exact_example_file" "$host_config_file"
    log INFO "Seeded gameplay config from $exact_example_file"
    return
  fi

  if [[ -f "$generic_template_example_file" ]]; then
    cp -f "$generic_template_example_file" "$host_config_file"
    log INFO "Seeded gameplay config from $generic_template_example_file"
    return
  fi

  if [[ -f "$generic_example_file" ]]; then
    cp -f "$generic_example_file" "$host_config_file"
    log INFO "Seeded gameplay config from $generic_example_file"
  fi
}

initialize_minimal_gameplay_config_for_cluster() {
  local host_config_file="$1"
  local cluster_value="$2"

  if [[ -f "$host_config_file" ]]; then
    return
  fi

  cat >"$host_config_file" <<EOF
{
  "0": {
    "KaiQiKuaFu": $cluster_value
  },
  "1": {
    "KaiQiKuaFu": $cluster_value
  },
  "2": {
    "KaiQiKuaFu": $cluster_value
  }
}
EOF

  log WARN "Created a minimal gameplay config at $host_config_file to persist the cluster toggle"
}

sync_gameplay_config() {
  local host_config_file="$1"
  local target_config_file="$2"

  mkdir -p "$(dirname "$target_config_file")"

  if [[ -f "$host_config_file" ]]; then
    cp -f "$host_config_file" "$target_config_file"
    log INFO "Synced gameplay config from $host_config_file to $target_config_file"
    return
  fi

  if [[ -f "$target_config_file" ]]; then
    cp -f "$target_config_file" "$host_config_file"
    log WARN "Seeded missing host gameplay config at $host_config_file from existing server file"
    return
  fi

  log WARN "No gameplay config found at '$host_config_file' or '$target_config_file'. Allowing the server to generate defaults."
}

apply_gameplay_overrides() {
  local config_file="$1"
  local cluster_value="$2"
  local inventory_slots="$3"
  local tmp_file=""

  [[ -f "$config_file" ]] || return 0

  tmp_file="${config_file}.tmp.$$"

  if ! jq \
    --argjson cluster "$cluster_value" \
    --argjson exp "$SOULMASK_EXP_MULTIPLIER" \
    --argjson yield "$SOULMASK_YIELD_MULTIPLIER" \
    --argjson taming "$SOULMASK_TAMING_SPEED_MULTIPLIER" \
    --argjson hatching "$SOULMASK_HATCHING_SPEED_MULTIPLIER" \
    --argjson animal_growth "$SOULMASK_ANIMAL_GROWTH_SPEED_MULTIPLIER" \
    --argjson crop_growth "$SOULMASK_CROP_GROWTH_SPEED_MULTIPLIER" \
    --argjson training "$SOULMASK_TRAINING_GROUND_EXP_MULTIPLIER" \
    --argjson max_load "$SOULMASK_MAX_LOAD_MULTIPLIER" \
    --argjson inventory_slots "$inventory_slots" '
    def apply_group:
      . + {
        "KaiQiKuaFu": $cluster,
        "ExpRatio": $exp,
        "ChengZhangExpRatio": $exp,
        "MJExpRatio": $exp,
        "ShuLianDuExpRatio": $exp,
        "CaiJiExpRatio": $exp,
        "ZhiZuoExpRatio": $exp,
        "ShaGuaiExpRatio": $exp,
        "QiTaExpRatio": $exp,
        "CaiJiDiaoLuoRatio": $yield,
        "FaMuDiaoLuoRatio": $yield,
        "CaiKuangDiaoLuoRatio": $yield,
        "DongWuShiTiDiaoLuoRatio": $yield,
        "DongWuShiTiZhongYaoDiaoLuoRatio": $yield,
        "CaiJiShengChanJianZhuDiaoLuoRatio": $yield,
        "ZuoWuDropRatio": $yield,
        "AddRenKeDuRatio": $taming,
        "FuHuaSpeed": $hatching,
        "DongWuShengZhangRatio": $animal_growth,
        "ZuoWuShengZhangRatio": $crop_growth,
        "TrainingExpRatio": $training,
        "MaxFuZhongRatio": $max_load,
        "RoleBagCapacity": $inventory_slots
      };
    .["0"] = ((.["0"] // {}) | apply_group) |
    .["1"] = ((.["1"] // {}) | apply_group) |
    .["2"] = ((.["2"] // {}) | apply_group)
  ' "$config_file" >"$tmp_file"; then
    rm -f "$tmp_file"
    die "Failed to update gameplay overrides in $config_file"
  fi

  mv -f "$tmp_file" "$config_file"
  log INFO "Applied cluster and English multiplier overrides in $config_file"
}

seed_gameplay_config_if_missing() {
  local host_config_file="$1"
  local target_config_file="$2"

  if [[ ! -f "$host_config_file" && -f "$target_config_file" ]]; then
    cp -f "$target_config_file" "$host_config_file"
    log WARN "Seeded missing host gameplay config at $host_config_file after the server generated defaults"
  fi
}

RUNTIME_IDENTITY_WRAPPER_LIB=""
RUNTIME_IDENTITY_PASSWD=""
RUNTIME_IDENTITY_GROUP=""

prepare_runtime_identity() {
  local uid
  local gid
  local runtime_dir
  local passwd_file
  local group_file

  uid="$(id -u)"
  gid="$(id -g)"

  runtime_dir="$SOULMASK_DATA_DIR/runtime"
  ensure_writable_dir "$runtime_dir" "Runtime identity"

  for candidate in \
    /usr/lib/x86_64-linux-gnu/libnss_wrapper.so \
    /usr/lib/libnss_wrapper.so \
    /lib/x86_64-linux-gnu/libnss_wrapper.so
  do
    if [[ -r "$candidate" ]]; then
      RUNTIME_IDENTITY_WRAPPER_LIB="$candidate"
      break
    fi
  done

  if [[ -z "$RUNTIME_IDENTITY_WRAPPER_LIB" ]]; then
    log WARN "libnss_wrapper.so was not found. Username mapping may not resolve to pokuser for uid $uid"
    export USER="pokuser"
    export LOGNAME="pokuser"
    return
  fi

  passwd_file="$runtime_dir/passwd"
  group_file="$runtime_dir/group"

  awk -F: -v uid="$uid" '$1 != "pokuser" && $3 != uid { print }' /etc/passwd >"$passwd_file"
  printf 'pokuser:x:%s:%s:POK Runtime User:%s:/bin/bash\n' "$uid" "$gid" "$HOME" >>"$passwd_file"

  awk -F: -v gid="$gid" '$1 != "pokuser" && $3 != gid { print }' /etc/group >"$group_file"
  printf 'pokuser:x:%s:\n' "$gid" >>"$group_file"

  RUNTIME_IDENTITY_PASSWD="$passwd_file"
  RUNTIME_IDENTITY_GROUP="$group_file"
  export USER="pokuser"
  export LOGNAME="pokuser"
}

with_install_lock() {
  local lock_dir=""
  local lock_fd=""

  lock_dir="$(dirname "$SOULMASK_INSTALL_LOCK_FILE")"
  ensure_writable_dir "$lock_dir" "Shared install lock"

  # shellcheck disable=SC3045
  exec {lock_fd}>"$SOULMASK_INSTALL_LOCK_FILE"
  flock "$lock_fd"
  "$@"
  flock -u "$lock_fd"
  # shellcheck disable=SC3045
  exec {lock_fd}>&-
}

run_with_runtime_identity() {
  if [[ -n "$RUNTIME_IDENTITY_WRAPPER_LIB" ]]; then
    env \
      NSS_WRAPPER_PASSWD="$RUNTIME_IDENTITY_PASSWD" \
      NSS_WRAPPER_GROUP="$RUNTIME_IDENTITY_GROUP" \
      LD_PRELOAD="$RUNTIME_IDENTITY_WRAPPER_LIB${LD_PRELOAD:+ $LD_PRELOAD}" \
      USER="${USER:-pokuser}" \
      LOGNAME="${LOGNAME:-pokuser}" \
      "$@"
    return
  fi

  "$@"
}

# shellcheck disable=SC2317
install_steamcmd_if_needed() {
  local steamcmd_bin="$SOULMASK_STEAMCMD_DIR/steamcmd.sh"
  local steamcmd_url_primary="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
  local steamcmd_url_fallback="https://media.steampowered.com/installer/steamcmd_linux.tar.gz"

  if [[ -x "$steamcmd_bin" ]]; then
    return
  fi

  ensure_writable_dir "$SOULMASK_STEAMCMD_DIR" "SteamCMD"

  log INFO "Bootstrapping SteamCMD into $SOULMASK_STEAMCMD_DIR"
  if ! curl -fsSL "$steamcmd_url_primary" | tar -xz -C "$SOULMASK_STEAMCMD_DIR"; then
    log WARN "Primary SteamCMD download failed, trying fallback URL"
    curl -fsSL "$steamcmd_url_fallback" | tar -xz -C "$SOULMASK_STEAMCMD_DIR"
  fi

  chmod 0755 "$steamcmd_bin"
  "$steamcmd_bin" +quit >/dev/null
}

sync_steam_runtime_files() {
  local steam_sdk_dir="$HOME/.steam/sdk64"

  ensure_writable_dir "$steam_sdk_dir" "Steam runtime"

  if [[ -f "$SOULMASK_STEAMCMD_DIR/linux64/steamclient.so" ]]; then
    cp -f "$SOULMASK_STEAMCMD_DIR/linux64/steamclient.so" "$steam_sdk_dir/steamclient.so"
  fi
}

# shellcheck disable=SC2317
update_server_if_needed() {
  local steamcmd_bin="$SOULMASK_STEAMCMD_DIR/steamcmd.sh"
  local validate_requested=false
  local update_args=()

  if ! is_true "${AUTO_UPDATE:-true}" && [[ -x "$SOULMASK_INSTALL_DIR/WSServer.sh" ]]; then
    log INFO "AUTO_UPDATE=false and an existing install was found. Skipping SteamCMD update."
    return
  fi

  if ! is_true "${AUTO_UPDATE:-true}" && [[ ! -x "$SOULMASK_INSTALL_DIR/WSServer.sh" ]]; then
    if [[ -n "${SOULMASK_CLUSTER_CLIENT_SERVER_CONNECT:-}" ]]; then
      die "AUTO_UPDATE=false but no shared Soulmask install exists at $SOULMASK_INSTALL_DIR. Start the main server first so it can install the game files."
    fi

    die "AUTO_UPDATE=false but no Soulmask install exists at $SOULMASK_INSTALL_DIR"
  fi

  ensure_writable_dir "$SOULMASK_INSTALL_DIR" "Soulmask install"

  if is_true "${VALIDATE_ON_UPDATE:-false}"; then
    validate_requested=true
  fi

  update_args=(
    +force_install_dir "$SOULMASK_INSTALL_DIR"
    +login anonymous
    +app_update "$SOULMASK_APP_ID"
  )

  if [[ -n "${SOULMASK_STEAM_BRANCH:-}" ]]; then
    update_args+=(-beta "$SOULMASK_STEAM_BRANCH")
    if [[ -n "${SOULMASK_STEAM_BETA_PASSWORD:-}" ]]; then
      update_args+=(-betapassword "$SOULMASK_STEAM_BETA_PASSWORD")
    fi
  fi

  if $validate_requested; then
    update_args+=(validate)
  fi

  update_args+=(+quit)

  log INFO "Running SteamCMD update for app $SOULMASK_APP_ID"
  "$steamcmd_bin" "${update_args[@]}"

  [[ -x "$SOULMASK_INSTALL_DIR/WSServer.sh" ]] || die "SteamCMD completed but $SOULMASK_INSTALL_DIR/WSServer.sh was not found"
  chmod 0755 "$SOULMASK_INSTALL_DIR/WSServer.sh"
}

wait_for_server_binary() {
  local launcher_pid="$1"
  local attempts=0
  local max_attempts=36

  SERVER_BINARY_PID=""

  while (( attempts < max_attempts )); do
    SERVER_BINARY_PID="$(pgrep -n -f "WSServer-Linux" || true)"
    if [[ -n "$SERVER_BINARY_PID" ]]; then
      log INFO "Detected WSServer-Linux pid $SERVER_BINARY_PID"
      return 0
    fi

    if ! kill -0 "$launcher_pid" 2>/dev/null; then
      return 1
    fi

    sleep 5
    (( attempts += 1 ))
  done

  return 1
}

world_db_path() {
  local map_name="${SOULMASK_LEVEL_NAME%%\?*}"
  printf "%s\n" "$SOULMASK_INSTALL_DIR/WS/Saved/Worlds/Dedicated/$map_name/world.db"
}

world_db_mtime() {
  local world_db="$1"

  if [[ -f "$world_db" ]]; then
    stat -c %Y "$world_db" 2>/dev/null || true
  fi
}

wait_for_world_db_save() {
  local world_db="$1"
  local before_mtime="${2:-}"
  local wait_seconds="$3"
  local waited=0
  local current_mtime=""

  while (( waited < wait_seconds )); do
    current_mtime="$(world_db_mtime "$world_db")"

    if [[ -n "$current_mtime" ]]; then
      if [[ -z "$before_mtime" || "$current_mtime" != "$before_mtime" ]]; then
        log INFO "Detected world save update at $world_db (mtime $current_mtime)"
        return 0
      fi
    fi

    sleep 1
    (( waited += 1 ))
  done

  return 1
}

maintenance_command() {
  local command=("$@")

  if ! [[ -x /usr/local/bin/soulmask-maint ]]; then
    return 1
  fi

  /usr/local/bin/soulmask-maint "${command[@]}"
}

graceful_server_shutdown() {
  local world_db=""
  local before_mtime=""
  local shutdown_delay="${SOULMASK_SHUTDOWN_DELAY_SECONDS:-30}"
  local save_wait="${SOULMASK_SAVEWORLD_WAIT_SECONDS:-30}"

  if [[ -z "$SERVER_BINARY_PID" ]] || ! kill -0 "$SERVER_BINARY_PID" 2>/dev/null; then
    return 1
  fi

  world_db="$(world_db_path)"
  before_mtime="$(world_db_mtime "$world_db")"

  if maintenance_command saveworld 1; then
    log INFO "Requested saveworld 1 through the maintenance port"

    if wait_for_world_db_save "$world_db" "$before_mtime" "$save_wait"; then
      log INFO "World save completed before shutdown"
    else
      log WARN "Did not observe a world.db timestamp change within ${save_wait}s at $world_db"
    fi
  else
    log WARN "Failed to send saveworld 1 through the maintenance port"
  fi

  if maintenance_command quit "$shutdown_delay"; then
    log INFO "Requested quit $shutdown_delay through the maintenance port"
    return 0
  fi

  log WARN "Failed to send quit through the maintenance port"
  return 1
}

direct_signal_shutdown() {
  if [[ -n "$SERVER_BINARY_PID" ]] && kill -0 "$SERVER_BINARY_PID" 2>/dev/null; then
    log INFO "Forwarding SIGINT to WSServer-Linux pid $SERVER_BINARY_PID"
    kill -INT "$SERVER_BINARY_PID" 2>/dev/null || true
    return
  fi

  if [[ -n "$SOULMASK_LAUNCHER_PID" ]] && kill -0 "$SOULMASK_LAUNCHER_PID" 2>/dev/null; then
    log INFO "Forwarding SIGTERM to WSServer.sh pid $SOULMASK_LAUNCHER_PID"
    kill -TERM "$SOULMASK_LAUNCHER_PID" 2>/dev/null || true
  fi
}

prepare_server_install() {
  prepare_shared_install
  sync_steam_runtime_files
}

prepare_shared_install() {
  with_install_lock prepare_shared_install_locked
}

# shellcheck disable=SC2317
prepare_shared_install_locked() {
  install_steamcmd_if_needed
  update_server_if_needed
}

SOULMASK_APP_ID="${SOULMASK_APP_ID:-3017300}"
SOULMASK_DATA_DIR="${SOULMASK_DATA_DIR:-/home/pokuser/soulmask/instances/server_1}"
SOULMASK_CONFIG_DIR="${SOULMASK_CONFIG_DIR:-/home/pokuser/soulmask/config/server_1}"
SOULMASK_SHARED_DIR="${SOULMASK_SHARED_DIR:-/home/pokuser/soulmask/shared}"
SOULMASK_STEAMCMD_DIR="${SOULMASK_STEAMCMD_DIR:-$SOULMASK_SHARED_DIR/steamcmd}"
SOULMASK_INSTALL_DIR="${SOULMASK_INSTALL_DIR:-$SOULMASK_SHARED_DIR/server}"
HOME="${HOME:-$SOULMASK_DATA_DIR/home}"
export HOME
SOULMASK_CONFIG_ROOT_DIR="${SOULMASK_CONFIG_ROOT_DIR:-$(dirname "$SOULMASK_CONFIG_DIR")}"
SOULMASK_INSTALL_LOCK_FILE="${SOULMASK_INSTALL_LOCK_FILE:-$SOULMASK_SHARED_DIR/.install.lock}"

SOULMASK_SERVER_NAME="${SOULMASK_SERVER_NAME:-POK Soulmask Server}"
SOULMASK_SERVER_PASSWORD="${SOULMASK_SERVER_PASSWORD:-}"
SOULMASK_ADMIN_PASSWORD="${SOULMASK_ADMIN_PASSWORD:-AdminChangeMePlease!}"
SOULMASK_LEVEL_NAME="${SOULMASK_LEVEL_NAME:-Level01_Main}"
SOULMASK_GAME_MODE="$(lower "${SOULMASK_GAME_MODE:-pve}")"
SOULMASK_GAME_PORT="${SOULMASK_GAME_PORT:-8777}"
SOULMASK_QUERY_PORT="${SOULMASK_QUERY_PORT:-27015}"
SOULMASK_ECHO_PORT="${SOULMASK_ECHO_PORT:-18888}"
SOULMASK_MAX_PLAYERS="${SOULMASK_MAX_PLAYERS:-50}"
SOULMASK_LISTEN_ADDRESS="${SOULMASK_LISTEN_ADDRESS:-0.0.0.0}"
SOULMASK_SAVE_INTERVAL_SECONDS="${SOULMASK_SAVE_INTERVAL_SECONDS:-600}"
SOULMASK_BACKUP_INTERVAL_SECONDS="${SOULMASK_BACKUP_INTERVAL_SECONDS:-900}"
SOULMASK_SHUTDOWN_DELAY_SECONDS="${SOULMASK_SHUTDOWN_DELAY_SECONDS:-30}"
SOULMASK_SAVEWORLD_WAIT_SECONDS="${SOULMASK_SAVEWORLD_WAIT_SECONDS:-30}"
SOULMASK_INIT_BACKUP="${SOULMASK_INIT_BACKUP:-false}"
SOULMASK_LOG_ENABLED="${SOULMASK_LOG_ENABLED:-true}"
SOULMASK_ONLINE_MODE="${SOULMASK_ONLINE_MODE:-Steam}"
SOULMASK_ENABLE_CLUSTER="${SOULMASK_ENABLE_CLUSTER:-${ENABLE_CLUSTER:-${SOULMASK_ENABLE_CROSSPLAY:-${ENABLE_CROSSPLAY:-false}}}}"
SOULMASK_EXP_MULTIPLIER="${SOULMASK_EXP_MULTIPLIER:-3}"
SOULMASK_YIELD_MULTIPLIER="${SOULMASK_YIELD_MULTIPLIER:-3}"
SOULMASK_TAMING_SPEED_MULTIPLIER="${SOULMASK_TAMING_SPEED_MULTIPLIER:-1.5}"
SOULMASK_HATCHING_SPEED_MULTIPLIER="${SOULMASK_HATCHING_SPEED_MULTIPLIER:-1.5}"
SOULMASK_ANIMAL_GROWTH_SPEED_MULTIPLIER="${SOULMASK_ANIMAL_GROWTH_SPEED_MULTIPLIER:-1.5}"
SOULMASK_CROP_GROWTH_SPEED_MULTIPLIER="${SOULMASK_CROP_GROWTH_SPEED_MULTIPLIER:-1.5}"
SOULMASK_TRAINING_GROUND_EXP_MULTIPLIER="${SOULMASK_TRAINING_GROUND_EXP_MULTIPLIER:-3}"
SOULMASK_MAX_LOAD_MULTIPLIER="${SOULMASK_MAX_LOAD_MULTIPLIER:-1}"
SOULMASK_INVENTORY_SLOTS_MULTIPLIER="${SOULMASK_INVENTORY_SLOTS_MULTIPLIER:-1}"

export SOULMASK_APP_ID
export SOULMASK_DATA_DIR
export SOULMASK_CONFIG_DIR
export SOULMASK_CONFIG_ROOT_DIR
export SOULMASK_SHARED_DIR
export SOULMASK_STEAMCMD_DIR
export SOULMASK_INSTALL_DIR

log INFO "Starting Soulmask container as uid $(id -u):gid $(id -g)"
log INFO "Data dir: $SOULMASK_DATA_DIR"
log INFO "Config dir: $SOULMASK_CONFIG_DIR"
log INFO "Install dir: $SOULMASK_INSTALL_DIR"

ensure_writable_dir "$SOULMASK_DATA_DIR" "Data"
ensure_writable_dir "$SOULMASK_CONFIG_DIR" "Config"
ensure_writable_dir "$HOME" "Runtime home"
prepare_runtime_identity

case "$SOULMASK_GAME_MODE" in
  pve|pvp)
    ;;
  *)
    die "SOULMASK_GAME_MODE must be 'pve' or 'pvp'. Got: $SOULMASK_GAME_MODE"
    ;;
esac

require_integer_in_range "SOULMASK_GAME_PORT" "$SOULMASK_GAME_PORT" 1024 65535
require_integer_in_range "SOULMASK_QUERY_PORT" "$SOULMASK_QUERY_PORT" 1024 65535
require_integer_in_range "SOULMASK_ECHO_PORT" "$SOULMASK_ECHO_PORT" 1024 65535
require_integer_in_range "SOULMASK_MAX_PLAYERS" "$SOULMASK_MAX_PLAYERS" 1 255
require_integer_in_range "SOULMASK_SAVE_INTERVAL_SECONDS" "$SOULMASK_SAVE_INTERVAL_SECONDS" 1 86400
require_integer_in_range "SOULMASK_BACKUP_INTERVAL_SECONDS" "$SOULMASK_BACKUP_INTERVAL_SECONDS" 1 86400
require_integer_in_range "SOULMASK_SHUTDOWN_DELAY_SECONDS" "$SOULMASK_SHUTDOWN_DELAY_SECONDS" 1 600
require_integer_in_range "SOULMASK_SAVEWORLD_WAIT_SECONDS" "$SOULMASK_SAVEWORLD_WAIT_SECONDS" 1 600

if [[ -n "${SOULMASK_BACKUP_INTERVAL_MINUTES:-}" ]]; then
  require_integer_in_range "SOULMASK_BACKUP_INTERVAL_MINUTES" "$SOULMASK_BACKUP_INTERVAL_MINUTES" 1 10080
fi

if [[ -n "${SOULMASK_SERVER_ID:-}" ]]; then
  require_integer_in_range "SOULMASK_SERVER_ID" "$SOULMASK_SERVER_ID" 1 2147483647
fi

if [[ -n "${SOULMASK_CLUSTER_MAIN_SERVER_PORT:-}" ]]; then
  require_integer_in_range "SOULMASK_CLUSTER_MAIN_SERVER_PORT" "$SOULMASK_CLUSTER_MAIN_SERVER_PORT" 1 65535
fi

if [[ -n "${SOULMASK_TRIBE_MAX_MEMBERS:-}" ]]; then
  require_integer_in_range "SOULMASK_TRIBE_MAX_MEMBERS" "$SOULMASK_TRIBE_MAX_MEMBERS" 1 2000
fi

require_number_in_range "SOULMASK_EXP_MULTIPLIER" "$SOULMASK_EXP_MULTIPLIER" 0.1 100
require_number_in_range "SOULMASK_YIELD_MULTIPLIER" "$SOULMASK_YIELD_MULTIPLIER" 0.1 100
require_number_in_range "SOULMASK_TAMING_SPEED_MULTIPLIER" "$SOULMASK_TAMING_SPEED_MULTIPLIER" 0.1 100
require_number_in_range "SOULMASK_HATCHING_SPEED_MULTIPLIER" "$SOULMASK_HATCHING_SPEED_MULTIPLIER" 0.1 100
require_number_in_range "SOULMASK_ANIMAL_GROWTH_SPEED_MULTIPLIER" "$SOULMASK_ANIMAL_GROWTH_SPEED_MULTIPLIER" 0.1 100
require_number_in_range "SOULMASK_CROP_GROWTH_SPEED_MULTIPLIER" "$SOULMASK_CROP_GROWTH_SPEED_MULTIPLIER" 0.1 100
require_number_in_range "SOULMASK_TRAINING_GROUND_EXP_MULTIPLIER" "$SOULMASK_TRAINING_GROUND_EXP_MULTIPLIER" 0.1 100
require_number_in_range "SOULMASK_MAX_LOAD_MULTIPLIER" "$SOULMASK_MAX_LOAD_MULTIPLIER" 0.1 100
require_number_in_range "SOULMASK_INVENTORY_SLOTS_MULTIPLIER" "$SOULMASK_INVENTORY_SLOTS_MULTIPLIER" 0.1 100

if [[ -n "${SOULMASK_CLUSTER_MAIN_SERVER_PORT:-}" && -n "${SOULMASK_CLUSTER_CLIENT_SERVER_CONNECT:-}" ]]; then
  die "Set either SOULMASK_CLUSTER_MAIN_SERVER_PORT or SOULMASK_CLUSTER_CLIENT_SERVER_CONNECT, not both"
fi

if is_true "$SOULMASK_ENABLE_CLUSTER" && [[ "$SOULMASK_GAME_MODE" != "pve" ]]; then
  die "ENABLE_CLUSTER requires SOULMASK_GAME_MODE=pve. PvP cross-map clustering is not supported yet."
fi

if is_true "$SOULMASK_ENABLE_CLUSTER" && [[ -z "${SOULMASK_CLUSTER_MAIN_SERVER_PORT:-}" && -z "${SOULMASK_CLUSTER_CLIENT_SERVER_CONNECT:-}" ]]; then
  die "ENABLE_CLUSTER=true requires an internal cluster role. The compose files should provide this automatically."
fi

if [[ -n "${UMASK:-}" ]]; then
  umask "$UMASK"
fi

prepare_server_install

GAMEPLAY_FILENAME="GameXishu.json"
if [[ -n "${SOULMASK_COEF_TEMPLATE:-}" ]]; then
  GAMEPLAY_FILENAME="GameXishu_${SOULMASK_COEF_TEMPLATE}.json"
fi

HOST_GAMEPLAY_CONFIG="$SOULMASK_CONFIG_DIR/$GAMEPLAY_FILENAME"
TARGET_GAMEPLAY_CONFIG="$SOULMASK_INSTALL_DIR/WS/Saved/GameplaySettings/$GAMEPLAY_FILENAME"
CLUSTER_VALUE=0

if is_true "$SOULMASK_ENABLE_CLUSTER"; then
  CLUSTER_VALUE=1
fi

GAMEPLAY_ROLE_BAG_CAPACITY="$(scaled_inventory_slots "$SOULMASK_INVENTORY_SLOTS_MULTIPLIER")"

seed_gameplay_config_from_example "$HOST_GAMEPLAY_CONFIG"

if (( CLUSTER_VALUE == 1 )) && [[ ! -f "$HOST_GAMEPLAY_CONFIG" && ! -f "$TARGET_GAMEPLAY_CONFIG" ]]; then
  initialize_minimal_gameplay_config_for_cluster "$HOST_GAMEPLAY_CONFIG" "$CLUSTER_VALUE"
fi

sync_gameplay_config "$HOST_GAMEPLAY_CONFIG" "$TARGET_GAMEPLAY_CONFIG"

if [[ -f "$HOST_GAMEPLAY_CONFIG" ]]; then
  apply_gameplay_overrides "$HOST_GAMEPLAY_CONFIG" "$CLUSTER_VALUE" "$GAMEPLAY_ROLE_BAG_CAPACITY"
  cp -f "$HOST_GAMEPLAY_CONFIG" "$TARGET_GAMEPLAY_CONFIG"
fi

export SteamAppId=2646460

LAUNCH_ARGS=(
  "$SOULMASK_LEVEL_NAME"
  "-server"
  "-UTF8Output"
  "-forcepassthrough"
  "-online=${SOULMASK_ONLINE_MODE}"
  "-SteamServerName=${SOULMASK_SERVER_NAME}"
  "-Port=${SOULMASK_GAME_PORT}"
  "-QueryPort=${SOULMASK_QUERY_PORT}"
  "-EchoPort=${SOULMASK_ECHO_PORT}"
  "-MULTIHOME=${SOULMASK_LISTEN_ADDRESS}"
  "-MaxPlayers=${SOULMASK_MAX_PLAYERS}"
  "-backup=${SOULMASK_BACKUP_INTERVAL_SECONDS}"
  "-saving=${SOULMASK_SAVE_INTERVAL_SECONDS}"
  "-${SOULMASK_GAME_MODE}"
)

if is_true "$SOULMASK_LOG_ENABLED"; then
  LAUNCH_ARGS+=("-log")
fi

if [[ -n "$SOULMASK_SERVER_PASSWORD" ]]; then
  LAUNCH_ARGS+=("-PSW=${SOULMASK_SERVER_PASSWORD}")
fi

if [[ -n "$SOULMASK_ADMIN_PASSWORD" ]]; then
  LAUNCH_ARGS+=("-adminpsw=${SOULMASK_ADMIN_PASSWORD}")
fi

if [[ -n "${SOULMASK_MOD_IDS:-}" ]]; then
  LAUNCH_ARGS+=("-mod=${SOULMASK_MOD_IDS}")
fi

if is_true "$SOULMASK_INIT_BACKUP"; then
  LAUNCH_ARGS+=("-initbackup")
fi

if [[ -n "${SOULMASK_BACKUP_INTERVAL_MINUTES:-}" ]]; then
  LAUNCH_ARGS+=("-backupinterval=${SOULMASK_BACKUP_INTERVAL_MINUTES}")
fi

if is_true "$SOULMASK_ENABLE_CLUSTER" && [[ -n "${SOULMASK_SERVER_ID:-}" ]]; then
  LAUNCH_ARGS+=("-serverid=${SOULMASK_SERVER_ID}")
fi

if is_true "$SOULMASK_ENABLE_CLUSTER" && [[ -n "${SOULMASK_CLUSTER_MAIN_SERVER_PORT:-}" ]]; then
  LAUNCH_ARGS+=("-mainserverport=${SOULMASK_CLUSTER_MAIN_SERVER_PORT}")
fi

if is_true "$SOULMASK_ENABLE_CLUSTER" && [[ -n "${SOULMASK_CLUSTER_CLIENT_SERVER_CONNECT:-}" ]]; then
  LAUNCH_ARGS+=("-clientserverconnect=${SOULMASK_CLUSTER_CLIENT_SERVER_CONNECT}")
fi

if [[ -n "${SOULMASK_COEF_TEMPLATE:-}" ]]; then
  LAUNCH_ARGS+=("-coef=${SOULMASK_COEF_TEMPLATE}")
fi

if [[ -n "${SOULMASK_TRIBE_MAX_MEMBERS:-}" ]]; then
  LAUNCH_ARGS+=("-GongHuiMaxMember=${SOULMASK_TRIBE_MAX_MEMBERS}")
fi

if [[ -n "${SOULMASK_PERMISSION_MASK:-}" ]]; then
  LAUNCH_ARGS+=("-serverpm=${SOULMASK_PERMISSION_MASK}")
fi

if [[ -n "${SOULMASK_EXTRA_ARGS:-}" ]]; then
  read -r -a EXTRA_ARGS_ARRAY <<<"$SOULMASK_EXTRA_ARGS"
  LAUNCH_ARGS+=("${EXTRA_ARGS_ARRAY[@]}")
fi

log INFO "Launching Soulmask server"
log INFO "Map: $SOULMASK_LEVEL_NAME"
log INFO "Mode: $SOULMASK_GAME_MODE"
log INFO "Game port: $SOULMASK_GAME_PORT"
log INFO "Query port: $SOULMASK_QUERY_PORT"
log INFO "Cluster enabled: $([[ "$CLUSTER_VALUE" -eq 1 ]] && printf yes || printf no)"
log INFO "Gameplay multipliers: EXP x$SOULMASK_EXP_MULTIPLIER, Yield x$SOULMASK_YIELD_MULTIPLIER, Taming x$SOULMASK_TAMING_SPEED_MULTIPLIER, Hatching x$SOULMASK_HATCHING_SPEED_MULTIPLIER, Animal Growth x$SOULMASK_ANIMAL_GROWTH_SPEED_MULTIPLIER, Crop Growth x$SOULMASK_CROP_GROWTH_SPEED_MULTIPLIER, Training x$SOULMASK_TRAINING_GROUND_EXP_MULTIPLIER, Max Load x$SOULMASK_MAX_LOAD_MULTIPLIER, Inventory x$SOULMASK_INVENTORY_SLOTS_MULTIPLIER (${GAMEPLAY_ROLE_BAG_CAPACITY} slots)"

if [[ -n "${SOULMASK_RCON_PASSWORD:-}" || -n "${SOULMASK_RCON_ADDRESS:-}" || -n "${SOULMASK_RCON_PORT:-}" ]]; then
  log WARN "RCON settings are ignored by this image. Use the maintenance port through soulmask-maint instead."
fi

SOULMASK_LAUNCHER_PID=""
SERVER_BINARY_PID=""
SHUTDOWN_REQUESTED=0

# shellcheck disable=SC2317
forward_shutdown() {
  if (( SHUTDOWN_REQUESTED != 0 )); then
    log WARN "Received another shutdown signal while shutdown is already in progress"
    direct_signal_shutdown
    return
  fi

  SHUTDOWN_REQUESTED=1
  log INFO "Shutdown signal received. Requesting graceful world save before stop."

  if graceful_server_shutdown; then
    return
  fi

  log WARN "Falling back to direct process signal shutdown"
  direct_signal_shutdown
}

trap forward_shutdown TERM INT

run_with_runtime_identity "$SOULMASK_INSTALL_DIR/WSServer.sh" "${LAUNCH_ARGS[@]}" &
SOULMASK_LAUNCHER_PID="$!"

if ! wait_for_server_binary "$SOULMASK_LAUNCHER_PID"; then
  launcher_exit_code=0
  wait "$SOULMASK_LAUNCHER_PID" || launcher_exit_code=$?
  die "WSServer-Linux did not start successfully. WSServer.sh exit code: $launcher_exit_code"
fi

launcher_exit_code=0
wait "$SOULMASK_LAUNCHER_PID" || launcher_exit_code=$?

if [[ -n "$SERVER_BINARY_PID" ]] && kill -0 "$SERVER_BINARY_PID" 2>/dev/null; then
  log INFO "Launcher exited but WSServer-Linux is still running. Waiting for pid $SERVER_BINARY_PID to exit."
  tail --pid="$SERVER_BINARY_PID" -f /dev/null || true
fi

seed_gameplay_config_if_missing "$HOST_GAMEPLAY_CONFIG" "$TARGET_GAMEPLAY_CONFIG"

log INFO "Soulmask server stopped with exit code $launcher_exit_code"
exit "$launcher_exit_code"
