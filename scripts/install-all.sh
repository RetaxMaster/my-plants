#!/usr/bin/env bash
# Run `npm install` in every submodule.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for repo in \
  my-plants-species-schema \
  my-plants-knowledge-engine \
  my-plants-api \
  my-plants-web
do
  echo "== npm install: $repo =="
  npm --prefix "$ROOT_DIR/repos/$repo" install
done
