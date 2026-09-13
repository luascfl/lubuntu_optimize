#!/usr/bin/env bash
# Update Claude Code through npm, bypassing the CLI updater's registry check.
set -euo pipefail

readonly npm_binary="/usr/bin/npm"
readonly install_prefix="$HOME/.npm-global"

NPM_CONFIG_ALLOW_REMOTE=all npm_config_prefix="$install_prefix" \
    "$npm_binary" install --location=global @anthropic-ai/claude-code@latest --loglevel error
