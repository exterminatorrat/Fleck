#!/bin/sh
set -eu

if [ "$#" -eq 0 ]; then
  printf '%s\n' 'usage: Scripts/evaluate-local-dictation.sh COMMAND OPTIONS' >&2
  exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
cd "$repo_root"
exec swift run --package-path Tools/LocalDictationEvaluation local-dictation-evaluation "$@"
