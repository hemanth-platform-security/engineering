#!/usr/bin/env bash
set -euo pipefail
umask 077

# Local learning helper only. The saved init response contains sensitive keys
# and the initial root token; protect it and never commit it to source control.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ADDR=${VAULT_ADDR:-http://0.0.0.0:8200}
KEY_SHARES=${KEY_SHARES:-1}
KEY_THRESHOLD=${KEY_THRESHOLD:-1}
INIT_FILE=${VAULT_INIT_FILE:-"$SCRIPT_DIR/vault-init-output.json"}

fail() {
	printf 'Error: %s\n' "$*" >&2
	exit 1
}

command -v vault >/dev/null 2>&1 || fail 'Vault CLI is required.'
command -v jq >/dev/null 2>&1 || fail 'jq is required.'
[[ "$KEY_SHARES" =~ ^[1-9][0-9]*$ ]] || fail 'KEY_SHARES must be a positive integer.'
[[ "$KEY_THRESHOLD" =~ ^[1-9][0-9]*$ ]] || fail 'KEY_THRESHOLD must be a positive integer.'
(( KEY_THRESHOLD <= KEY_SHARES )) || fail 'KEY_THRESHOLD cannot exceed KEY_SHARES.'
[[ ! -e "$INIT_FILE" ]] || fail "Refusing to overwrite existing init file: $INIT_FILE"

export VAULT_ADDR
STATUS_CODE=0
STATUS_JSON=$(vault status -format=json 2>/dev/null) || STATUS_CODE=$?
[[ "$STATUS_CODE" -eq 0 || "$STATUS_CODE" -eq 2 ]] || fail "Vault is not reachable at $VAULT_ADDR. Start the server first."

INITIALIZED=$(jq -r '.initialized // false' <<<"$STATUS_JSON")
[[ "$INITIALIZED" == false ]] || fail 'Vault is already initialized; refusing to initialize it again.'

INIT_TMP=$(mktemp "${INIT_FILE}.tmp.XXXXXX")
trap 'rm -f "$INIT_TMP"' EXIT

printf 'Initializing Vault at %s with %s key share(s), threshold %s...\n' \
	"$VAULT_ADDR" "$KEY_SHARES" "$KEY_THRESHOLD"
vault operator init \
	-key-shares="$KEY_SHARES" \
	-key-threshold="$KEY_THRESHOLD" \
	-format=json >"$INIT_TMP"

jq -e --argjson shares "$KEY_SHARES" \
	'.unseal_keys_b64 | length == $shares' "$INIT_TMP" >/dev/null \
	|| fail 'Vault initialization output did not contain the expected unseal keys.'

chmod 600 "$INIT_TMP"
mv "$INIT_TMP" "$INIT_FILE"
trap - EXIT

printf 'Saved the initialization response to %s (permissions: 600).\n' "$INIT_FILE"
printf 'Unsealing Vault...\n'
while IFS= read -r key; do
	vault operator unseal "$key" >/dev/null
done < <(jq -r --argjson threshold "$KEY_THRESHOLD" \
	'.unseal_keys_b64[:$threshold][]' "$INIT_FILE")

vault status
printf '\nVault is initialized and unsealed. Keep %s private and backed up securely.\n' "$INIT_FILE"
