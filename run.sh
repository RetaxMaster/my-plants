#!/usr/bin/env bash
# Development runner — starts the MyPlants services with "npm run dev" in parallel,
# with colored, prefixed output. Requires a local MariaDB server already running.
#
# Services (local dev):
#   my-plants-api   NestJS backend
#   my-plants-web   Nuxt 3 frontend
#
# Usage:
#   ./run.sh            Start API + web
#   ./run.sh --api      Start only the API
#   ./run.sh --web      Start only the web
#
# Flags can be combined: ./run.sh --api --web
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

START_API=false
START_WEB=false
if [[ $# -eq 0 ]]; then
  START_API=true
  START_WEB=true
else
  for arg in "$@"; do
    case "$arg" in
      --api) START_API=true ;;
      --web) START_WEB=true ;;
      *) echo "Unknown flag: $arg" >&2; exit 2 ;;
    esac
  done
fi

pids=()
cleanup() {
  trap - INT TERM EXIT
  for pid in "${pids[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup INT TERM EXIT

# Prefix each service's output with a colored label.
run_service() {
  local label="$1" color="$2" dir="$3"
  ( npm --prefix "$dir" run dev 2>&1 | sed -u "s/^/$(printf '\033[%sm[%s]\033[0m ' "$color" "$label")/" ) &
  pids+=("$!")
}

if $START_API; then
  run_service "api" "36" "$ROOT_DIR/repos/my-plants-api"
fi
if $START_WEB; then
  run_service "web" "32" "$ROOT_DIR/repos/my-plants-web"
fi

wait
