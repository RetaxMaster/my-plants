#!/usr/bin/env bash
# Run the test/verification command of every submodule.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "== species-schema =="
npm --prefix "$ROOT_DIR/repos/my-plants-species-schema" test

echo ""
echo "== knowledge-engine =="
npm --prefix "$ROOT_DIR/repos/my-plants-knowledge-engine" test

echo ""
echo "== api =="
npm --prefix "$ROOT_DIR/repos/my-plants-api" test

echo ""
echo "== web (build + typecheck) =="
npm --prefix "$ROOT_DIR/repos/my-plants-web" run build
