#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
powershell -NoProfile -ExecutionPolicy Bypass -File "${SCRIPT_DIR}/windows-swift-env.ps1" -CheckOnly
