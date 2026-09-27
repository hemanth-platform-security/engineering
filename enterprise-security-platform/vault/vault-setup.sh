#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
CONFIG_FILE="$CONFIG_DIR/vault.hcl"
DATA_DIR="$SCRIPT_DIR/data"
VAULT_ADDR="http://127.0.0.1:8200"

if ! command -v vault >/dev/null 2>&1; then
	printf 'Error: Vault CLI is required. Install it before running this script.\n' >&2
	exit 1
fi

mkdir -p "$CONFIG_DIR" "$DATA_DIR"

if [[ ! -f "$CONFIG_FILE" ]]; then
	cat >"$CONFIG_FILE" <<'HCL'
# Local learning configuration only. Do not expose this listener to a network.
disable_mlock = true
ui            = true
api_addr      = "http://127.0.0.1:8200"
log_level     = "info"

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = 1
}

storage "file" {
  path = "./data"
}
HCL
	printf 'Created Vault config: %s\n' "$CONFIG_FILE"
else
	printf 'Keeping existing Vault config: %s\n' "$CONFIG_FILE"
fi

cd "$SCRIPT_DIR"
export VAULT_ADDR

if command -v curl >/dev/null 2>&1 && curl --silent --show-error --max-time 1 \
	"$VAULT_ADDR/v1/sys/health" --output /dev/null 2>/dev/null; then
	printf 'A Vault server is already responding at %s.\n' "$VAULT_ADDR"
	exit 0
fi

printf 'Starting local Vault at %s\n' "$VAULT_ADDR"
printf 'Config: %s\nData: %s\n' "$CONFIG_FILE" "$DATA_DIR"
printf 'Press Ctrl+C to stop the server.\n'
exec vault server -config="$CONFIG_FILE"
