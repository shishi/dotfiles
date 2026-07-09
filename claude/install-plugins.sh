#!/usr/bin/env bash
#
# Install the Claude Code plugins declared in settings.json (enabledPlugins).
#
# settings.json は dotfiles に追跡されているが、それを解決する
# known_marketplaces.json / installed_plugins.json は .gitignore 対象なので、
# 新しいマシンでは「enabledPlugins では有効なのに marketplace 未登録 →
# install 失敗」という状態が起きる。このスクリプトはその差分を埋める。
#
# enabledPlugins の値が true のものだけを対象にする。false のものは触らない:
# `claude plugin install` には「インストールと同時に enabledPlugins=true へ
# する」副作用があるため、意図的に無効化したプラグインを install すると
# 勝手に有効化されてしまう。
#
# 冪等: 既に登録済みの marketplace / インストール済みの plugin はスキップする。

set -uo pipefail

# shishi の gitconfig は https://github.com/ を ssh:// に書き換え (insteadOf) し、
# さらに claude の git サブプロセスは ~/.ssh/config の StrictHostKeyChecking=no を
# 読まない。新しいホスト鍵を受理して、clone (または claude の HTTPS フォールバック)
# が無人で成功するようにする。
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o StrictHostKeyChecking=accept-new}"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
KNOWN_MKTS="$CLAUDE_DIR/plugins/known_marketplaces.json"
INSTALLED="$CLAUDE_DIR/plugins/installed_plugins.json"

# marketplace 名 -> GitHub repo。新しい marketplace を使い始めたら 1 行足す。
# (この対応情報だけは settings.json / 追跡対象ファイルに無いのでここで保持する)
declare -A MARKETPLACE_REPO=(
  [superpowers-marketplace]="obra/superpowers-marketplace"
  [claude-plugins-official]="anthropics/claude-plugins-official"
  [openai-codex]="openai/codex-plugin-cc"
  [karpathy-skills]="forrestchang/andrej-karpathy-skills"
  [claude-code-herdr-plugin]="yigitkonur/claude-code-herdr-plugin"
)

command -v claude >/dev/null 2>&1 || { echo "install-plugins: claude CLI not found; skip"; exit 0; }
command -v jq     >/dev/null 2>&1 || { echo "install-plugins: jq not found; skip"; exit 0; }
[ -f "$SETTINGS" ] || { echo "install-plugins: $SETTINGS not found; skip"; exit 0; }

marketplace_known() {
  [ -f "$KNOWN_MKTS" ] && jq -e --arg m "$1" 'has($m)' "$KNOWN_MKTS" >/dev/null 2>&1
}

plugin_installed() {
  [ -f "$INSTALLED" ] && jq -e --arg p "$1" '.plugins | has($p)' "$INSTALLED" >/dev/null 2>&1
}

added=0 installed=0 present=0 unresolved=0 failed=0

# enabledPlugins のうち値がちょうど true のものだけ ("plugin@marketplace")
while IFS= read -r plugin; do
  [ -n "$plugin" ] || continue

  if plugin_installed "$plugin"; then
    present=$((present + 1))
    continue
  fi

  marketplace="${plugin##*@}"
  repo="${MARKETPLACE_REPO[$marketplace]:-}"
  if [ -z "$repo" ]; then
    echo "install-plugins: WARN no repo mapping for marketplace '$marketplace' (plugin $plugin) — add it to MARKETPLACE_REPO"
    unresolved=$((unresolved + 1))
    continue
  fi

  if ! marketplace_known "$marketplace"; then
    echo "install-plugins: adding marketplace $marketplace ($repo)"
    if claude plugin marketplace add "$repo"; then
      added=$((added + 1))
    else
      echo "install-plugins: WARN failed to add marketplace $marketplace; skip $plugin"
      failed=$((failed + 1))
      continue
    fi
  fi

  echo "install-plugins: installing $plugin"
  if claude plugin install "$plugin"; then
    installed=$((installed + 1))
  else
    echo "install-plugins: WARN failed to install $plugin"
    failed=$((failed + 1))
  fi
# Windows 版 jq は stdout をテキストモードで開き改行を CRLF にするため、
# tr -d '\r' で末尾の CR を落とす (Unix では no-op)。これを怠ると marketplace 名に
# \r が残り MARKETPLACE_REPO のキーと一致せず全 plugin が unresolved になる。
done < <(jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' "$SETTINGS" | tr -d '\r')

echo "install-plugins: done (marketplaces added: $added, plugins installed: $installed, already present: $present, unresolved: $unresolved, failed: $failed)"

[ "$failed" -eq 0 ]
