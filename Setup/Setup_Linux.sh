#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)

if ! command -v pwsh >/dev/null 2>&1; then
    echo 'FEHLER: PowerShell 7 (pwsh) fehlt. Zuerst Tools/Setup.sh im Project-Root ausfuehren.' >&2
    exit 1
fi

exec pwsh -NoLogo -NoProfile -File "$script_dir/Setup.ps1" "$@"
