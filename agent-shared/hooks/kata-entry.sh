#!/usr/bin/env bash
# SessionStart hook: 変更作業の入口を kata に向ける。Claude Code では superpowers plugin が毎回
# using-superpowers の全文を差し込むため、ざっくりした依頼で kata を経ずに上流の brainstorming へ進んだり、
# 上流の手順どおり質問だけして止まったりすることがある。skill の選択は description に気づくかに依存するため、
# 入口と優先関係を確定的に差し込む。Codex にも同じ内容を渡し、両 CLI の入口をそろえる。
set -u
cat <<'MSG'
<kata-entry>
変更作業の入口は kata skill。作業の最初に kata を開き、続けて工程 1 の kata-design を開いて目的と方式を固める。既存の設計・計画がある仕事や圧縮後の再開では、kata の該当工程から進める。以降も工程の切替時に kata の工程表を確かめ、kata-plan・kata-build など表に書かれた skill から進める。superpowers の skill は kata の各工程から呼ぶ。上流の手順と kata・AGENTS.md の条件が食い違う場合は kata・AGENTS.md を優先する。
</kata-entry>
MSG
exit 0
