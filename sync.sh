#!/bin/bash
# Pull latest config and apply (merge mode)
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"
git pull
exec "$REPO_DIR/install.sh" "$@"
