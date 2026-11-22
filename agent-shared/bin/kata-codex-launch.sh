#!/usr/bin/env bash
set -eu

native() {
  exec codex --no-daemon "$@"
}

if [ ! -t 0 ] || [ ! -t 1 ]; then
  native "$@"
fi

terminal_args=()
subcommand=
value_pending=
literal=
for arg in "$@"; do
  if [ -n "$literal" ] || [ -n "$value_pending" ]; then
    value_pending=
    terminal_args+=("$arg")
    continue
  fi
  case "$arg" in
    --) literal=1 ;;
    --no-daemon) continue ;;
    -h|--help|-V|--version|--remote|--remote=*|--remote-auth-token-env|--remote-auth-token-env=*)
      native "$@"
      ;;
    -c|--config|-C|--cd|-m|--model|-p|--profile|-s|--sandbox|-a|--ask-for-approval|-i|--image|--enable|--disable|--add-dir|--local-provider)
      value_pending=1
      ;;
    -*)
      ;;
    *)
      if [ -z "$subcommand" ]; then
        subcommand=1
        case "$arg" in
          agents|tcp-tunnel|exec|e|review|login|git-credential|logout|mcp|plugin|app-server|remote-control|app|completion|update|doctor|sandbox|debug|execpolicy|apply|a|queue|archive|delete|migrate-rollouts|migrate-nfs-db|unarchive|cloud|cloud-tasks|responses-api-proxy|stdio-to-uds|exec-server|features|help)
            native "$@"
            ;;
        esac
      fi
      ;;
  esac
  terminal_args+=("$arg")
done

script_directory=$(cd -P -- "$(dirname "$0")" && pwd -P)
exec bun "$script_directory/kata-codex.mjs" "${terminal_args[@]}"
