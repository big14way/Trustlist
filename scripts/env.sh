#!/usr/bin/env bash
# Load .env files without letting them override the real environment.
#
# .env.example documents optional settings as empty placeholders. `source`
# would let an empty placeholder win over a value the caller exported, and
# that is exactly how CI lost its snapshot address: the gate reported
# "TRUST_SNAPSHOT is not set" no matter what the workflow set, so the whole
# M6 snapshot check never ran there.
#
# Precedence, highest first: the process environment, then .env, then
# .env.example. Only simple KEY=value lines are read, which is all these
# files contain.
load_env() {
  local file=$1 line name
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '' | '#'*) continue ;; esac
    name=${line%%=*}
    case "$name" in *[!A-Za-z0-9_]*) continue ;; esac
    [ -n "${!name:-}" ] && continue
    export "$name=${line#*=}"
  done < "$file"
}

# The usual pair, in the usual order. Call from the repository root.
load_env_files() {
  load_env .env
  load_env .env.example
}
