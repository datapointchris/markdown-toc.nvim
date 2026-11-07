#!/usr/bin/env bash
# Regenerate the README's own ToC in a copy and fail when it differs from the
# committed one. --clean keeps a user config, and any installed copy of the
# plugin, out of the run. The README's lists use '-' markers, so the setup
# call asks for them.
set -euo pipefail

cd "$(dirname "$0")/.."
copy=$(mktemp --suffix=.md)
trap 'rm -f "$copy"' EXIT
cp README.md "$copy"
nvim --clean --headless --cmd 'set rtp^=.' \
  -c 'lua require("mtoc").setup({ toc_list = { markers = "-" } })' \
  -c 'Mtoc update' -c 'wq' "$copy"
diff README.md "$copy"
