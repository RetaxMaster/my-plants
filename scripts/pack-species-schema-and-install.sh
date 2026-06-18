#!/usr/bin/env bash
# Shared-package-first mechanic: test, build, and pack the species-schema package,
# then install the fresh tarball into every consumer. Run this whenever the schema
# changes, BEFORE the consumers depend on the new contract.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$ROOT_DIR/repos/my-plants-species-schema"

echo "== Testing species-schema package =="
npm --prefix "$PKG_DIR" test

echo "== Building + packing species-schema =="
(
  cd "$PKG_DIR"
  npm run build
  TARBALL="$(npm pack | tail -1)"
  # Keep only the tarball we just produced.
  find "$PKG_DIR" -maxdepth 1 -name 'retaxmaster-my-plants-species-schema-*.tgz' \
    ! -name "$(basename "$TARBALL")" -delete
)

TARBALL="$(ls -1t "$PKG_DIR"/retaxmaster-my-plants-species-schema-*.tgz | head -1)"

for consumer in \
  my-plants-knowledge-engine \
  my-plants-api
do
  if [ ! -d "$ROOT_DIR/repos/$consumer" ]; then
    echo "== Skipping $consumer (not present yet) =="
    continue
  fi
  echo "== Installing species-schema into $consumer =="
  npm --prefix "$ROOT_DIR/repos/$consumer" install "$TARBALL"
done

echo "Done. Commit package.json/package-lock.json in each consumer."
