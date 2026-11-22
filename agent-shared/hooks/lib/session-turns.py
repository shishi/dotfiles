"""会話記録から、利用者の発言ごとのターンを組み立てて出力する。kata-completion.sh が読み込む。

使い方: session-turns.py <会話記録> turns|last|mark|replied|interactive

turns: 各ターンの利用者の発言と、そのターンでエージェントが最後に書いた文を、古い順に出す。
  計画の無いセッションでは、前のターンの依頼が終わったか・一時停止されたかを判定役が知る手掛かりになる。
  長い発言は先頭と末尾を残す (貼り付けた資料の後に指示を書くことがあるため)。
  全体が上限を超えたら古いターンから省き、省いた数を書く。
last: 最後の利用者の発言を、先頭と末尾を残して出す。
mark: 利用者の発言の数を出す。同じ文面を送り直しても、新しい発言だと見分けるために使う。
replied: Stop の最後の応答 (標準入力) より後に利用者の発言が届いたかを見分ける。空白を除いて、最後の応答が
  最後の利用者の発言のターンの最後の文と一致すれば yes、それより前のターンの最後の文とだけ一致すれば no
  (後から発言が届いた)、どれとも一致しなければ unknown (会話記録への書き込みが追いついていない) を出す。
  前の報告を引用しただけの文を一致と見ないよう、一部ではなく全文で比べる。
interactive: 利用者が対話している会話なら yes、プログラムから起動した非対話の実行 (Claude Code の claude -p、
  Codex の codex exec) なら no を出す。

Claude の会話記録は利用者の入力を type=user・isMeta でない行に残し、ツール結果も同じ type で残す。
バックグラウンドのタスクの完了通知も同じ形で残るが、promptSource が system (origin.kind が task-notification) に
なるので外す (利用者が打った行は typed。古い記録にはこの欄が無い)。圧縮後の要約 (isCompactSummary) と、
/model などのコマンドの出力 (<local-command-stdout> などで始まる行) も、利用者の発言ではないので外す。
エージェントの作業中に利用者が送った発言は queued_command の attachment に残るので、これも発言として拾う。
Codex の rollout (0.167.0) は role=user の message に残し、AGENTS.md・環境・hook の差し戻しと同じ形になるため、
provenance が user の要素だけを取る。
"""
import json
import re
import sys

# 直近 300 セッションの利用者の発言 411 件は、中央値 193 字、95 パーセンタイル 6,535 字だった。長いものは
# 貼り付けた資料や試行の依頼文なので、先頭と末尾を残して前後に書いた指示を落とさない
USER_CLIP = 1500
# 最後の文は報告で、何を作って何を終えたかが中ほどに書かれることも多い。直近のセッションの報告は長いもので
# 約 3,000 字だったので、その長さまではそのまま渡し、それより長いものは結論 (冒頭) と申し出 (末尾) を残す
REPLY_CLIP = 1500
# 圧縮を 2 回挟んだ 67 ターンのセッションで、発言と最後の応答の合計が約 6 万字だった。それが全部入る量にする
BUDGET = 60000


LOCAL_COMMAND_OUTPUT = ("<local-command-stdout>", "<local-command-stderr>", "<local-command-caveat>")


def clip(text, n):
    text = re.sub(r"\s+", " ", text).strip()
    return text if len(text) <= 2 * n + 3 else text[:n] + " … " + text[-n:]


def user_text(d):
    if d.get("promptSource") == "system" or (d.get("origin") or {}).get("kind") == "task-notification":
        return None
    if d.get("isCompactSummary") or d.get("isVisibleInTranscriptOnly"):
        return None
    # エージェントの作業中に利用者が送った発言は、queued_command の attachment として届く (origin.kind が human。
    # 作業中に立てた /goal は auto-continuation。古い記録には origin が無い)。完了通知 (commandMode が
    # task-notification) と、子エージェント・別のセッションからの報告 (origin.kind が peer) も同じ形で届く。
    # 知らない種類が増えても発言に数えないよう、拾う種類を決めて拾う
    attachment = d.get("attachment") if d.get("type") == "attachment" else None
    if isinstance(attachment, dict) and attachment.get("type") == "queued_command":
        kind = (attachment.get("origin") or {}).get("kind")
        if attachment.get("commandMode") != "prompt" or kind not in (None, "human", "auto-continuation"):
            return None
        prompt = attachment.get("prompt")
        if isinstance(prompt, list):
            prompt = " ".join(c.get("text", "") for c in prompt if isinstance(c, dict))
        return prompt if isinstance(prompt, str) else None
    if d.get("type") == "user" and not d.get("isMeta"):
        content = d.get("message", {}).get("content")
        if isinstance(content, str):
            return None if content.lstrip().startswith(LOCAL_COMMAND_OUTPUT) else content
        if isinstance(content, list) and not any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content):
            return " ".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
    payload = d.get("payload", {}) if d.get("type") == "response_item" else {}
    if payload.get("type") == "message" and payload.get("role") == "user":
        meta = payload.get("internal_chat_message_metadata_passthrough", {}).get("content_item_metadata") or []
        items = payload.get("content") or []
        return " ".join(item.get("text", "") for item, m in zip(items, meta)
                        if isinstance(m, dict) and (m.get("provenance") or {}).get("type") == "user")
    return None


def agent_text(d):
    if d.get("type") == "assistant":
        content = d.get("message", {}).get("content") or []
        return "".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
    payload = d.get("payload", {}) if d.get("type") == "response_item" else {}
    if payload.get("type") == "message" and payload.get("role") == "assistant":
        return "".join(c.get("text", "") for c in payload.get("content") or [] if isinstance(c, dict))
    return None


def turns(path):
    result = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if not isinstance(d, dict):
                continue
            text = user_text(d)
            if text is not None and text.strip():
                result.append([text, ""])
                continue
            reply = agent_text(d)
            if reply and reply.strip() and result:
                result[-1][1] = reply
    return result


def interactive(path):
    # Claude Code は各行の entrypoint に、claude -p なら sdk-cli を残す。Codex は session_meta の originator に、
    # codex exec なら codex_exec を残す。同じ会話を別の起動方法で再開できるため、最後の記録で決める
    result = True
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if not isinstance(d, dict):
                continue
            if "entrypoint" in d:
                result = d["entrypoint"] != "sdk-cli"
            elif d.get("type") == "session_meta":
                result = (d.get("payload") or {}).get("originator") != "codex_exec"
    return result


def main():
    path, mode = sys.argv[1], sys.argv[2]
    if mode == "interactive":
        print("yes" if interactive(path) else "no")
        return
    all_turns = turns(path)
    if mode == "mark":
        print(len(all_turns))
        return
    if mode == "replied":
        final = re.sub(r"\s+", "", sys.stdin.read())
        replies = [re.sub(r"\s+", "", r) for _, r in all_turns]
        if final and replies and final == replies[-1]:
            print("yes")
        elif final and final in replies[:-1]:
            print("no")
        else:
            print("unknown")
        return
    if mode == "last":
        print(clip(all_turns[-1][0], USER_CLIP) if all_turns else "")
        return
    blocks = [f"USER: {clip(u, USER_CLIP)}\nAGENT (last text of that turn): {clip(r, REPLY_CLIP) or '(none)'}"
              for u, r in all_turns]
    kept, size = [], 0
    for block in reversed(blocks):
        if kept and size + len(block) > BUDGET:
            break
        kept.append(block)
        size += len(block)
    omitted = len(blocks) - len(kept)
    if omitted:
        print(f"({omitted} older turns omitted)")
    print("\n\n".join(reversed(kept)))


if __name__ == "__main__":
    main()
