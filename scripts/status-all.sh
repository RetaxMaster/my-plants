#!/usr/bin/env bash
# Show the working-tree status of the workspace and every submodule.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Workspace:"
git -C "$ROOT_DIR" status --short

echo ""
echo "Submodules:"
for repo in \
  my-plants-species-schema \
  my-plants-knowledge-engine \
  my-plants-api \
  my-plants-web
do
  echo "-- $repo --"
  git -C "$ROOT_DIR/repos/$repo" status --short
done
