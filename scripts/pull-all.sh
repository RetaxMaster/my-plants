#!/usr/bin/env bash
# Sync the workspace and every submodule to the latest main.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

git -C "$ROOT_DIR" pull --ff-only
git -C "$ROOT_DIR" submodule update --init --recursive

for repo in \
  my-plants-species-schema \
  my-plants-knowledge-engine \
  my-plants-api \
  my-plants-web
do
  echo "== $repo =="
  git -C "$ROOT_DIR/repos/$repo" checkout main
  git -C "$ROOT_DIR/repos/$repo" pull --ff-only origin main
done
