#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_file="$script_dir/.env"

if [[ -f "$env_file" ]]; then
  while IFS='=' read -r key value; do
    key="${key#${key%%[![:space:]]*}}"
    key="${key%${key##*[![:space:]]}}"
    [[ -z "$key" || "$key" == \#* ]] && continue
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    value="${value#${value%%[![:space:]]*}}"
    value="${value%${value##*[![:space:]]}}"
    value="${value%\"}"; value="${value#\"}"
    value="${value%\'}"; value="${value#\'}"
    export "$key=$value"
  done < "$env_file"
fi

command -v k6 >/dev/null 2>&1 || { echo "k6 is not installed or not in PATH." >&2; exit 1; }

export TARGET_URL="${TARGET_URL:-https://example.com}"
export MODE="${MODE:-vus}"
export VUS="${VUS:-10}"
export RAMP_UP="${RAMP_UP:-1m}"
export HOLD="${HOLD:-3m}"
export RAMP_DOWN="${RAMP_DOWN:-1m}"
export SLEEP="${SLEEP:-1}"
export PATHS="${PATHS:-/}"

case "${USE_PROXY:-false}" in
  1|true|TRUE|yes|YES|on|ON)
    command -v python3 >/dev/null 2>&1 || { echo "python3 is required for proxy mode." >&2; exit 1; }
    command -v curl >/dev/null 2>&1 || { echo "curl is required for proxy mode." >&2; exit 1; }

    cache_file="$script_dir/.proxy-cache/working-proxies.txt"
    cache_minutes="${PROXY_CACHE_MINUTES:-60}"
    refresh_cache=true
    if [[ -s "$cache_file" ]]; then
      cache_age_seconds=$(( $(date +%s) - $(stat -c %Y "$cache_file") ))
      (( cache_age_seconds < cache_minutes * 60 )) && refresh_cache=false
    fi

    if [[ "$refresh_cache" == true ]]; then
      provider_file="${PROXY_PROVIDERS_FILE:-proxy-providers.json}"
      [[ "$provider_file" = /* ]] || provider_file="$script_dir/$provider_file"
      python3 "$script_dir/proxy_pool.py" \
        --providers "$provider_file" \
        --test-url "${PROXY_TEST_URL:-$TARGET_URL}" \
        --output "$cache_file" \
        --max-candidates "${MAX_PROXY_CANDIDATES:-30}" \
        --max-working "${MAX_WORKING_PROXIES:-5}" \
        --concurrency "${PROXY_TEST_CONCURRENCY:-10}"
    fi

    mapfile -t compatible_proxies < <(grep -E '^(http|socks5)://' "$cache_file" || true)
    (( ${#compatible_proxies[@]} > 0 )) || {
      echo "No k6-compatible HTTP or SOCKS5 proxy is available; SOCKS4 is validation-only." >&2
      exit 1
    }
    selected_proxy="${compatible_proxies[RANDOM % ${#compatible_proxies[@]}]}"
    export HTTP_PROXY="$selected_proxy" HTTPS_PROXY="$selected_proxy"
    export http_proxy="$selected_proxy" https_proxy="$selected_proxy"
    export NO_PROXY="" no_proxy=""
    echo "Using proxy for this k6 run: $selected_proxy"
    ;;
esac

exec k6 run "$script_dir/site-load-test.js"
