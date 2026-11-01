import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, TurnStepChunk, TurnStepInput } from 'claude-code'

// 出力ゲートの Claude Code 側: モデルの応答の文字列を止め、共通の検査処理
// (~/.agent-shared/bin/output-gate-check.py) で検査し、訂正した文字列だけを流す。
// 流した文字列が画面と会話記録になる。検査できなければ、原文の先頭に理由を添えて流す。

const holding = atom({ plugin: 'output-gate', key: 'holding' } as const, 0)

const UNCHECKED = (reason: string) => `[出力ゲート: 検査できませんでした — ${reason}]\n\n`
const RECENT_MESSAGES = 10
// 検査処理の中の締切 (gitleaks 30 秒 + 検査役 45 秒) より長くし、締切切れは検査処理が理由付きで返すようにする。
const CHECK_TIMEOUT_MS = 90_000

type Run = { index: number; text: string }
type Payload = {
  cli: 'claude'
  latest_user: string
  conversation: { role: string; text: string }[]
  draft: string
  cyber_program: null
  compacted_note: false
}

// 起動できた Python の名前。モジュールの読み直しで消えてよい。
let python: string | undefined

async function findPython($: EngineInterface): Promise<string> {
  if (python !== undefined) return python
  for (const candidate of ['python3', 'python']) {
    try {
      const { exitCode } = await $.process.run([candidate, '-I', '-c', ''], { timeoutMs: 10_000 })
      if (exitCode === 0) return (python = candidate)
    } catch {
      // この名前では起動できない。次の名前を試す。
    }
  }
  throw new Error('Python を起動できない')
}

async function conversation($: EngineInterface) {
  const messages = await $.session.messages()
  const said = 'deny' in messages ? [] : messages.filter(m => m.text.trim() !== '')
  const users = said.filter(m => m.role === 'user')
  return {
    latest_user: users.at(-1)?.text ?? '',
    conversation: said.slice(-RECENT_MESSAGES).map(m => ({ role: m.role, text: m.text })),
  }
}

async function runChecker($: EngineInterface, payload: Payload): Promise<string> {
  const home = await homeDir($)
  if (!home) throw new Error('ホームディレクトリが分からない')
  const argv = [await findPython($), '-I', `${home}/.agent-shared/bin/output-gate-check.py`]
  let result
  try {
    result = await $.process.run(argv, { stdin: JSON.stringify(payload), timeoutMs: CHECK_TIMEOUT_MS })
  } catch {
    throw new Error('検査処理を実行できなかった')
  }
  if (result.exitCode !== 0) throw new Error(`検査処理が失敗した (終了コード ${result.exitCode})`)
  const out = JSON.parse(result.stdout) as { status?: unknown; text?: unknown; reason?: unknown }
  const hasReason = typeof out.reason === 'string' && out.reason.trim() !== ''
  if (typeof out.text !== 'string' || !(out.status === 'checked' || (out.status === 'unchecked' && hasReason))) {
    throw new Error('検査処理の答えの形が違う')
  }
  return out.text
}

async function check($: EngineInterface, draft: string): Promise<string> {
  if (draft.trim() === '') return draft
  try {
    const context = await conversation($)
    return await runChecker($, { cli: 'claude', ...context, draft, cyber_program: null, compacted_note: false })
  } catch (error) {
    return UNCHECKED(error instanceof Error ? error.message : '検査できなかった') + draft
  }
}

// 本文の断片を、続けて届いた区間ごとにまとめる。一つのブロックの本文は続けて届くため、同じ index でも
// 別の断片 (再試行の印など) を挟んで届いたものは別の区間にする。owner[i] は i 番目の断片が属する区間。
function runs(held: readonly TurnStepChunk[]): { runs: Run[]; owner: (number | undefined)[] } {
  const result: Run[] = []
  const owner: (number | undefined)[] = []
  held.forEach((chunk, i) => {
    if (chunk.kind !== 'text') {
      owner.push(undefined)
      return
    }
    const previous = i > 0 ? held[i - 1] : undefined
    if (previous?.kind !== 'text' || previous.index !== chunk.index) result.push({ index: chunk.index, text: '' })
    result[result.length - 1].text += chunk.text
    owner.push(result.length - 1)
  })
  return { runs: result, owner }
}

// 上位の hook が読む answer を作る。エンジンの answer は採用した試行の本文だけを持ち、採用した試行は最後に
// 届く。そこで、区間の列の末尾から何個かをつないだものが answer と完全に一致するとき、その区間の訂正版を
// つなぐ。文字列の部分一致で区間を探すと、捨てた試行の訂正を採用した本文の別の箇所に当ててしまうため使わない。
// 一致する並びが無ければ (エンジンが区切りを足した場合など)、全区間の訂正版をつなぐ。訂正前の文字列は返さない。
function correctedAnswer(answer: string, original: Run[], checked: string[]): string {
  // first が区間の数と等しいとき、空の並び ('') と照合する (採用した試行に本文が無い場合)。
  for (let first = 0; first <= original.length; first++) {
    if (original.slice(first).map(run => run.text).join('') === answer) return checked.slice(first).join('')
  }
  return checked.join('')
}

// 各区間の最初の text の断片の位置に訂正版を入れ、残りの断片は流さない。
function* rebuilt(held: readonly TurnStepChunk[], owner: (number | undefined)[], checked: string[]):
    Generator<TurnStepChunk> {
  const sent = new Set<number>()
  for (const [i, chunk] of held.entries()) {
    const run = owner[i]
    if (run === undefined) {
      yield chunk
    } else if (!sent.has(run) && chunk.kind === 'text') {
      sent.add(run)
      yield { kind: 'text', index: chunk.index, text: checked[run] }
    }
  }
}

// Windows では USERPROFILE を先に見る。代わりの hook (Python の Path.home()) と同じ場所を指すため。
async function homeDir($: EngineInterface): Promise<string | undefined> {
  return (await $.env.get('USERPROFILE')) ?? (await $.env.get('HOME'))
}

async function stateDir($: EngineInterface): Promise<string | undefined> {
  const home = await homeDir($)
  // 空文字は未設定として扱う (シェルの ${XDG_STATE_HOME:-...} と同じ)。
  const base = (await $.env.get('XDG_STATE_HOME')) || (home ? `${home}/.local/state` : undefined)
  return base === undefined ? undefined : `${base}/output-gate`
}

// 使うかはマシンごとの印 (output-gate-claude.sh enable が書く claude-enabled) で決める。Codex 側と同じく既定は無効。
async function enabledOnMachine($: EngineInterface) {
  const dir = await stateDir($)
  if (dir === undefined) return false
  try {
    await $.fs.read(`${dir}/claude-enabled`)
    return true
  } catch {
    return false
  }
}

async function skip($: EngineInterface, e: TurnStepInput) {
  // 副エージェントの出力は親の Claude が読む。委譲の子セッションの出力は呼び出し側が読む。
  if (e.agentId !== undefined || (await $.env.get('AGENT_DELEGATED_SESSION')) === '1') return true
  return !(await enabledOnMachine($))
}

async function setHolding($: EngineInterface, change: number) {
  try {
    await update($, holding, n => Math.max(0, (n ?? 0) + change))
  } catch {
    // 表示のための値なので、書けなくても検査は続ける。
  }
}

// mod が動いたセッションに印を残す。mod を使えない環境向けの MessageDisplay hook
// (agent-shared/hooks/output-gate-claude.sh) は、印に書かれたターンの回答では何もしない (同じ回答を二度
// 検査しない)。以前のターンの印で検査を飛ばさないよう、モデルへの要求ごとに今のターンの識別子を書く。
async function markSession($: EngineInterface, e: TurnStepInput) {
  try {
    const id = await $.session.id()
    const dir = await stateDir($)
    if (dir === undefined) return
    await $.fs.write(`${dir}/claude-mod/${id}`, e.turnId)
  } catch {
    // 印を書けなくても検査は続ける。代わりの hook が同じ回答をもう一度検査するだけになる。
  }
}

// 本文より前にそのまま流した断片の数。hook が失敗したとき、.catch の処理が同じ断片を重複して流さないために
// 使う。正常に終わったときと、.catch の処理が読んだときに消す。
const yielded = new Map<string, number>()
const stepKey = (e: TurnStepInput) => `${e.agentId ?? ''}:${e.turnId}:${e.index}`

export const register: Register = on => {
  on('turn.step', async function* ($, e, next) {
    if (await skip($, e)) return yield* next(e)
    await markSession($, e)
    const key = stepKey(e)
    yielded.set(key, 0)
    const stream = next(e)
    const held: TurnStepChunk[] = []
    let isHolding = false
    let completed = false
    try {
      while (true) {
        const step = await stream.next()
        if (step.done) {
          if (!isHolding) {
            completed = true
            return step.value
          }
          const split = runs(held)
          const checked = await Promise.all(split.runs.map(run => check($, run.text)))
          // 検査の間に同じセッションの別のステップが印を書き換えることがあるため、流す直前にも書き直す。
          await markSession($, e)
          yield* rebuilt(held, split.owner, checked)
          completed = true
          return { ...step.value, answer: correctedAnswer(step.value.answer, split.runs, checked) }
        }
        // 最初の本文の断片から応答の終わりまでを止める。それより前の推論やツール呼び出しはすぐ流す。
        if (!isHolding && step.value.kind === 'text') {
          isHolding = true
          await setHolding($, 1)
        }
        if (isHolding) {
          held.push(step.value)
        } else {
          yielded.set(key, (yielded.get(key) ?? 0) + 1)
          yield step.value
        }
      }
    } finally {
      if (completed) yielded.delete(key)
      if (isHolding) await setHolding($, -1)
    }
  }).catch(async function* ($, e, next) {
    // hook 自体が失敗した場合 (時間超過を含む): 原文に理由を添えて流す。すでに流した断片は飛ばす。
    const reason = UNCHECKED('出力ゲートの処理が失敗した')
    let skipped = yielded.get(stepKey(e)) ?? 0
    yielded.delete(stepKey(e))
    let marked = false
    const stream = next(e)
    while (true) {
      const step = await stream.next()
      if (step.done) return step.value
      if (skipped > 0) {
        skipped -= 1
        continue
      }
      if (!marked && step.value.kind === 'text') {
        marked = true
        yield { ...step.value, text: reason + step.value.text }
      } else {
        yield step.value
      }
    }
  })

  // 止めている間に中断や読み直しが起きて減らせなかった値を、メインのターンの終わりで 0 に戻す。
  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined) {
      try {
        await update($, holding, () => 0)
      } catch {
        // 表示のための値なので、書けなくても続ける。
      }
    }
    return next(e)
  })

  on('ui.render', { component: 'Spinner' }, async ($, e, next) => {
    if ((await read($, holding)) > 0) {
      return next({ ...e, props: { ...e.props, suffix: `${e.props.suffix} 出力ゲートで回答を確認中` } })
    }
    return next(e)
  })
}
