import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, ToolCallInput, ToolCallResult, TurnStepChunk, TurnStepInput } from 'claude-code'
import type { HoldingEvidence, HoldingMessage, HoldingTurn } from '../types/index.d.ts'

// 出力ゲートの Claude Code 側: モデルの応答の文字列を止め、共通の検査処理
// (~/.agent-shared/bin/output-gate-check.py) で検査し、訂正した文字列だけを流す。
// 流した文字列が画面と会話記録になる。検査できなければ、原文の先頭に理由を添えて流す。
// 最終回答 (end_turn・stop_sequence の段) に未達があれば、1 回だけ本文を gate_findings の呼び出しに差し替え、
// 指摘をツールの結果として返して同じターンで直させる。証拠は tool.call で記録した呼び出しと結果。

const holding = atom({ plugin: 'output-gate', key: 'holding' } as const, 0)

const UNCHECKED = (reason: string) => `[出力ゲート: 検査できませんでした — ${reason}]\n\n`
const RECENT_MESSAGES = 10
// 検査全体の締切 (秒)。秘密情報の検査 (gitleaks) と二つの系統の検査役が、この中に収まる。先に試す系統には
// 残りの半分、次の系統には残り全てを渡す (検査処理と同じ分け方)。環境変数 OUTPUT_GATE_TIMEOUT で変えられる。
const DEFAULT_TIMEOUT_S = 45
// 検査処理を待つ上限は、渡した締切に、止まらない子の後始末 (最大 30 秒) と余裕を足したもの。締切切れは
// 検査処理が理由付きで返すため、ここで切るのは検査処理そのものが止まった場合だけ。
const CLEANUP_MS = 30_000 + 10_000
// Claude の検査役 ($.model.complete) の返答の上限 (トークン)。仮の値で、時間と利用枠を測ってから決め直す。
const CLAUDE_MAX_TOKENS = 8_192
const GATE_TOOL_NAME = 'gate_findings'
const GATE_TOOL = 'mcp__output-gate__gate_findings'
const NOT_ISSUED = '出力ゲートが出した呼び出しではなく、検査は行われていない'
const FINAL_STOPS = new Set(['end_turn', 'stop_sequence'])
// 最終回答の段を経ずに終わったターンの表示済みの文章を判定する終わり方。利用者の中断 (aborted) では判定しない。
const JUDGED_ENDS = new Set(['answer', 'refusal', 'error'])
const KEEP_TURNS = 10
const KEEP_MS = 24 * 3600 * 1000
// 1 件の出力の上限 (バイト)。中ほどを省いて先頭と末尾を残す (検査処理の切り詰めと同じ規則)。
// ターンのファイルが $.fs.read の上限 (4 MiB) を超えるときは、収まるまで上限を半分にする。
const OUTPUT_CAP = 64 * 1024
const FILE_LIMIT = 3 * 1024 * 1024
const ENDED_UNFIXED = '[出力ゲート: 直させている途中でターンが終わったため、検査した回答を表示します]\n\n'
// 一時ファイルを置き換え、古いターンのファイルと空になったセッションのディレクトリを消す ($.fs には名前の
// 変更と削除が無い)。
const FILE_OPS = [
  'import json, os, sys',
  'ops = json.loads(sys.argv[1])',
  'for source, target in ops["replace"]:',
  '    os.replace(source, target)',
  'for path in ops["remove"]:',
  '    try:',
  '        os.remove(path)',
  '    except FileNotFoundError:',
  '        pass',
  'for path in ops.get("rmdir", []):',
  '    try:',
  '        os.rmdir(path)',
  '    except OSError:',
  '        pass',
].join('\n')

type Run = { index: number; text: string }
type Turn = NonNullable<HoldingTurn>
type Evidence = NonNullable<HoldingEvidence>
type Item = { id: string; tool?: string; command?: string; input?: unknown; output?: string; failed?: boolean;
  exit_code?: number; unavailable?: boolean; note?: string }
type PreviousTurn = { turn_id: string; time: string | null; items: Item[] }
type Payload = {
  origin: 'claude'
  bodies: string[]
  latest_user: string
  recent_messages: HoldingMessage[]
  turn_start_context: HoldingMessage[]
  shown_text: string
  evidence: Item[]
  previous_evidence: PreviousTurn[]
  previous_findings: unknown[] | null
  round: 0 | 1
  final: boolean
  continuation: 'withhold' | 'none'
  engines: ['codex']
  cyber_program: null
}
type Failure = { family: string | null; reason: string }
type CheckResult = {
  status: 'checked' | 'unchecked'
  text: string | null
  bodies: string[] | null
  findings: unknown[]
  agent_message: string | null
  fallback_text: string | null
  fallback_bodies: string[] | null
  reason: string | null
  engine: unknown
  engine_failures: Failure[]
  dropped: unknown[]
  unmet_text: string | null
  display_text: string | null
}
type Effort = 'low' | 'medium' | 'high' | 'xhigh' | 'max'
type Settings = { first: 'opposite' | 'same'; claude: { model: string; effort: Effort } }

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

// 副エージェントの出力は親の Claude が読む。委譲の子セッションの出力は呼び出し側が読む。
async function skip($: EngineInterface, agentId: string | undefined) {
  if (agentId !== undefined || (await $.env.get('AGENT_DELEGATED_SESSION')) === '1') return true
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
// (agent-shared/hooks/output-gate-claude.sh) は、印があるセッションでは何もしない (同じ回答を二度検査しない)。
// その UserPromptSubmit hook が利用者の入力のたびに印を消すため、モデルへの要求ごとに書き直す。中身の
// ターンの識別子は記録のためだけで、hook は照合しない (MessageDisplay の turn_id は別に作られる値)。
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

// --- 会話とターンの記録 ---

type Said = { role: string; text: string; toolUses: { tool_use_id: string; tool: string }[] }

async function sessionMessages($: EngineInterface): Promise<Said[]> {
  const messages = await $.session.messages()
  return 'deny' in messages ? [] : messages
}

const spoken = (messages: Said[]) => messages.filter(m => m.text.trim() !== '').map(m => ({ role: m.role, text: m.text }))

// 利用者の入力の直前の 1 往復 (最後の利用者の発言とその後の回答)。今の入力が記録の末尾にあれば除く。
function lastExchange(messages: Said[], prompt: string): HoldingMessage[] {
  const said = spoken(messages)
  if (said.at(-1)?.role === 'user' && said.at(-1)?.text === prompt) said.pop()
  const lastUser = said.map(m => m.role).lastIndexOf('user')
  return lastUser < 0 ? said.slice(-2) : said.slice(lastUser)
}

const newTurn = (latestUser: string, context: HoldingMessage[], now: number): Turn => ({
  latest_user: latestUser, turn_start_context: context, started_at: now, tool_ids: [], shown: '', judged_len: 0,
  round: 0, agent_message: null, findings: [], original: null, unmet: null, gate_tool_id: null, checks: [],
})

async function readTurn($: EngineInterface, turnId: string): Promise<Turn> {
  const { value } = await $.state.get({ plugin: 'output-gate', key: 'turn', id: turnId })
  if (value) return value
  // turn.start を聞いていない (mod が途中で読み込まれた、resume の後など): 記録から作る。
  const said = spoken(await sessionMessages($))
  const latest = said.filter(m => m.role === 'user').at(-1)?.text ?? ''
  return newTurn(latest, [], Date.now())
}

// --- 証拠 ---

const encoder = new TextEncoder()
const decoder = new TextDecoder()
const bytes = (text: string) => encoder.encode(text).length

// 中ほどを省いて先頭と末尾を残す。省いた箇所には、省いたバイト数とモデルはその範囲を見ていることを書く。
function capOutput(text: string, cap: number): string {
  const data = encoder.encode(text)
  if (data.length <= cap) return text
  const keep = Math.floor(cap / 2)
  const cut = data.length - 2 * keep
  const trim = (s: string) => s.replace(/^\uFFFD+|\uFFFD+$/g, '')
  return trim(decoder.decode(data.slice(0, keep))) +
    `\n[output-gate: omitted ${cut} bytes here to fit the stored evidence; the model saw this range]\n` +
    trim(decoder.decode(data.slice(data.length - keep)))
}

const withoutReminders = (text: string) => text.replace(/<system-reminder>[\s\S]*?<\/system-reminder>/g, '').trim()

// 引数の文字列にも出力と同じ上限を掛ける (ターンのファイルが $.fs.read の上限を超えないように)。
function capStrings(value: unknown, cap: number): unknown {
  if (typeof value === 'string') return capOutput(value, cap)
  if (Array.isArray(value)) return value.map(item => capStrings(item, cap))
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, capStrings(item, cap)]))
  }
  return value
}

function describeCall(e: ToolCallInput): { command: string | null; input: Record<string, unknown> } {
  const { tool: _tool, tool_use_id: _id, agentId: _agent, requestMeta: _meta, ...rest } = e as Record<string, unknown>
  const input = capStrings(rest, OUTPUT_CAP) as Record<string, unknown>
  const command = typeof input['command'] === 'string' ? (input['command'] as string) : null
  return { command, input }
}

function recordOf(e: ToolCallInput, result: ToolCallResult | undefined, error: unknown): Evidence {
  const { command, input } = describeCall(e)
  let output: string
  let failed = false
  let note: string | null = null
  if (result === undefined) {
    failed = true
    output = error instanceof Error ? error.message : String(error)
    note = '呼び出しが例外で終わった (拒否・中断を含む)'
  } else if (result.deny !== undefined) {
    failed = true
    output = result.deny
    note = '呼び出しが拒否された'
  } else {
    failed = result.isError === true
    output = typeof result.text === 'string' ? result.text : JSON.stringify(result.result ?? null)
  }
  output = withoutReminders(output)
  const exit = failed ? /^Error: Exit code (\d+)/.exec(output) : null
  return { tool: String(e.tool), command, input, output: capOutput(output, OUTPUT_CAP), failed,
    exit_code: exit ? Number(exit[1]) : null, note }
}

function evidenceItem(id: string, record: Evidence): Item {
  const item: Item = { id, tool: record.tool, input: record.input, output: record.output, failed: record.failed }
  if (record.command !== null) item.command = record.command
  if (record.exit_code !== null) item.exit_code = record.exit_code
  if (record.note !== null) item.note = record.note
  return item
}

async function currentEvidence($: EngineInterface, turn: Turn): Promise<Item[]> {
  const items: Item[] = []
  for (const id of turn.tool_ids) {
    const { value } = await $.state.get({ plugin: 'output-gate', key: 'evidence', id: id })
    items.push(value ? evidenceItem(id, value) : {
      id: `missing-${id}`, unavailable: true,
      note: 'この呼び出しの結果を出力ゲートが記録できなかった (mod の読み直しの前の呼び出しなど)',
    })
  }
  return items
}

async function turnsDir($: EngineInterface): Promise<string | undefined> {
  const dir = await stateDir($)
  return dir === undefined ? undefined : `${dir}/claude-turns/${await $.session.id()}`
}

const TURN_FILE = /^(\d{13})-(.+)\.json$/

async function turnFiles($: EngineInterface, dir: string) {
  let entries
  try {
    entries = await $.fs.list(dir)
  } catch {
    return []
  }
  return entries.flatMap(entry => {
    const match = TURN_FILE.exec(entry.name)
    return match ? [{ path: `${dir}/${entry.name}`, time: Number(match[1]), turnId: match[2]! }] : []
  }).sort((a, b) => b.time - a.time)
}

const kept = <T extends { time: number }>(files: T[], now: number): T[] => files.filter(f => now - f.time <= KEEP_MS).slice(0, KEEP_TURNS)

async function previousEvidence($: EngineInterface, turnId: string, turn: Turn): Promise<PreviousTurn[]> {
  const dir = await turnsDir($)
  const now = Date.now()
  const previous: PreviousTurn[] = []
  const recorded = new Set<string>(turn.tool_ids)
  if (dir !== undefined) {
    for (const file of kept((await turnFiles($, dir)).filter(f => f.turnId !== turnId), now)) {
      const time = new Date(file.time).toISOString()
      try {
        const data = JSON.parse(await $.fs.read(file.path)) as { turn_id: string; items: Item[] }
        if (!Array.isArray(data.items)) throw new Error('items')
        data.items.forEach(item => recorded.add(item.id))
        previous.push({ turn_id: data.turn_id, time, items: data.items })
      } catch {
        previous.push({ turn_id: file.turnId, time, items: [{ id: `unreadable-${file.turnId}`, unavailable: true,
          note: '前のターンの証拠を取得できなかった (ターンのファイルを読めない・解析できない)' }] })
      }
    }
  }
  // 記録に見える前のターンの呼び出しで、ファイルに記録の無いもの (mod が動く前など)。保持する範囲 (直近の
  // 10 ターン) に合わせ、利用者の入力で区切った直近の区間だけを見る。
  const messages = await sessionMessages($)
  const prompts = messages.flatMap((m, i) => (m.role === 'user' && m.text.trim() !== '' ? [i] : []))
  const from = prompts.at(-(KEEP_TURNS + 1)) ?? 0
  const missing = messages.slice(from).flatMap(m => m.toolUses)
    .filter(use => use.tool !== GATE_TOOL && !recorded.has(use.tool_use_id))
  if (missing.length > 0) {
    const tools = [...new Set(missing.map(use => use.tool))].join(', ')
    previous.push({ turn_id: 'unrecorded', time: null, items: [{ id: 'unrecorded-previous-calls', unavailable: true,
      note: `前のターンの ${missing.length} 件の呼び出し (${tools}) は、出力ゲートの記録が無いか保持の範囲外のため、証拠を取得できない` }] })
  }
  return previous
}

// ターンの証拠をターンごとのファイルに書き (一時ファイルから置き換える)、保持の範囲より古いものを消す。
async function saveTurnFile($: EngineInterface, turnId: string, turn: Turn, items: Item[]) {
  const dir = await turnsDir($)
  if (dir === undefined) return
  const now = Date.now()
  let cap = OUTPUT_CAP
  let text = ''
  for (;;) {
    const capped = items.map(item => capStrings(item, cap))
    text = JSON.stringify({ turn_id: turnId, time: new Date(turn.started_at).toISOString(), items: capped,
      checks: turn.checks })
    if (bytes(text) <= FILE_LIMIT || cap < 1024) break
    cap = Math.floor(cap / 2)
  }
  const name = `${String(turn.started_at).padStart(13, '0')}-${turnId}.json`
  await $.fs.write(`${dir}/${name}.tmp`, text)
  const files = (await turnFiles($, dir)).filter(f => f.turnId !== turnId)
  const keep = new Set(kept([{ time: turn.started_at, path: '' }, ...files].sort((a, b) => b.time - a.time), now))
  const remove = files.filter(f => !keep.has(f)).map(f => f.path)
  const rmdir: string[] = []
  await staleSessions($, dir, now, remove, rmdir)
  await fileOps($, [[`${dir}/${name}.tmp`, `${dir}/${name}`]], remove, rmdir)
}

// ほかのセッションのターンのファイルで保持の範囲 (24 時間) を過ぎたものを消す。中身が全て消えたセッションの
// ディレクトリも消す。
async function staleSessions($: EngineInterface, current: string, now: number, remove: string[], rmdir: string[]) {
  const root = current.slice(0, current.lastIndexOf('/'))
  let sessions
  try {
    sessions = await $.fs.list(root)
  } catch {
    return
  }
  for (const session of sessions) {
    const dir = `${root}/${session.name}`
    if (session.kind !== 'dir' || dir === current) continue
    let entries
    try {
      entries = await $.fs.list(dir)
    } catch {
      continue
    }
    const stale = entries.filter(entry => {
      const time = TURN_FILE.exec(entry.name)?.[1]
      return now - (time === undefined ? entry.mtimeMs : Number(time)) > KEEP_MS
    })
    remove.push(...stale.map(entry => `${dir}/${entry.name}`))
    if (stale.length === entries.length) rmdir.push(dir)
  }
}

async function fileOps($: EngineInterface, replace: [string, string][], remove: string[], rmdir: string[]) {
  const result = await $.process.run([await findPython($), '-I', '-c', FILE_OPS, JSON.stringify({ replace, remove, rmdir })],
    { timeoutMs: 10_000 })
  if (result.exitCode !== 0) throw new Error('ターンのファイルを置き換えられない')
}

// --- 検査処理と検査役 ---

async function checkerArgv($: EngineInterface, mode?: '--prepare' | '--receive') {
  const home = await homeDir($)
  if (!home) throw new Error('ホームディレクトリが分からない')
  return [await findPython($), '-I', `${home}/.agent-shared/bin/output-gate-check.py`, ...(mode ? [mode] : [])]
}

// budgetMs: 検査処理に渡す締切 (OUTPUT_GATE_TIMEOUT)。
async function runChecker($: EngineInterface, input: unknown, budgetMs: number, mode?: '--prepare' | '--receive'):
    Promise<Record<string, unknown>> {
  const argv = await checkerArgv($, mode)
  let result
  try {
    result = await $.process.run(argv, { stdin: JSON.stringify(input), timeoutMs: Math.ceil(budgetMs) + CLEANUP_MS,
      env: { OUTPUT_GATE_TIMEOUT: (budgetMs / 1000).toFixed(3) } })
  } catch {
    throw new Error('検査処理を実行できなかった')
  }
  if (result.exitCode !== 0) throw new Error(`検査処理が失敗した (終了コード ${result.exitCode})`)
  return JSON.parse(result.stdout) as Record<string, unknown>
}

function asResult(out: Record<string, unknown>): CheckResult {
  const hasReason = typeof out['reason'] === 'string' && (out['reason'] as string).trim() !== ''
  const status = out['status']
  const textOk = typeof out['text'] === 'string' || (out['text'] === null && typeof out['agent_message'] === 'string')
  if (!textOk || !(status === 'checked' || (status === 'unchecked' && hasReason))) {
    throw new Error('検査処理の答えの形が違う')
  }
  const failures = Array.isArray(out['engine_failures']) ? out['engine_failures'] as Failure[] : []
  return { ...(out as unknown as CheckResult), findings: Array.isArray(out['findings']) ? out['findings'] : [],
    engine_failures: failures, dropped: Array.isArray(out['dropped']) ? out['dropped'] : [],
    unmet_text: typeof out['unmet_text'] === 'string' ? out['unmet_text'] : null,
    display_text: typeof out['display_text'] === 'string' ? out['display_text'] : null }
}

// 検査役の系統の失敗 (検査役が答えなかった) か。検査役が答えて検査できなかった場合は別の系統へ移らない。
const engineFailed = (r: CheckResult) => r.status === 'unchecked' && r.engine == null && r.engine_failures.length > 0

// 利用者の設定 (先に試す系統、Claude の系統のモデルと推論量)。検査処理と同じく、無ければ既定値、読めない・
// 形が違えば検査できなかった扱い (理由付き) にする。
async function settings($: EngineInterface): Promise<Settings> {
  const dir = await stateDir($)
  const path = (await $.env.get('OUTPUT_GATE_SETTINGS')) || (dir === undefined ? undefined : `${dir}/checker.json`)
  if (path === undefined || !(await $.fs.exists(path))) return { first: 'opposite', claude: { model: 'sonnet', effort: 'medium' } }
  let raw: unknown
  try {
    raw = JSON.parse(await $.fs.read(path))
  } catch (error) {
    throw new Error(`検査役の設定 (${path}) を読めない: ${error instanceof Error ? error.name : 'Error'}`)
  }
  const shaped = (value: unknown) => value === undefined || value === null ||
    (typeof value === 'object' && !Array.isArray(value) &&
      ['model', 'effort'].every(key => ['undefined', 'string'].includes(typeof (value as Record<string, unknown>)[key])))
  const data = raw as { first?: unknown; codex?: unknown; claude?: { model?: string; effort?: string } | null }
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw) || !['opposite', 'same', undefined].includes(data.first as string) ||
      !shaped(data.codex) || !shaped(data.claude)) {
    throw new Error(`検査役の設定 (${path}) の形が違う`)
  }
  // 推論量が $.model.complete の受け付けない値なら、呼び出しが拒まれて Claude の系統の失敗になる。
  return { first: data.first === 'same' ? 'same' : 'opposite',
    claude: { model: data.claude?.model || 'sonnet', effort: (data.claude?.effort || 'medium') as Effort } }
}

// Claude の検査役: 検査処理の入力を組む口で入力を作り (秘密情報は伏せてある)、セッションの認証で呼び、
// 返答を受ける口へ渡す。この系統で検査できなければ、その理由 (Failure) を返す。
async function claudeCheck($: EngineInterface, payload: Payload, config: Settings['claude'], failures: Failure[],
    deadline: number): Promise<CheckResult | Failure> {
  const fail = (reason: string): Failure => ({ family: 'claude', reason: `claude の検査役で検査できなかった (${reason})` })
  let prepared
  try {
    prepared = await runChecker($, payload, deadline - Date.now(), '--prepare')
  } catch (error) {
    return fail(error instanceof Error ? error.message : '入力を組めない')
  }
  if (prepared['status'] !== 'ready') return fail(String(prepared['reason'] ?? '入力を組めない'))
  const left = Math.floor(deadline - Date.now())
  if (left <= 0) return fail('時間が残っていない')
  let reply
  try {
    reply = await $.model.complete({ model: config.model, effort: config.effort, system: String(prepared['system']),
      prompt: String(prepared['prompt']), maxTokens: CLAUDE_MAX_TOKENS, timeoutMs: left })
  } catch (error) {
    return fail(`呼び出しを拒まれた: ${error instanceof Error ? error.message : String(error)}`)
  }
  if (!reply.isAnswered) {
    const detail = reply.reason === 'api-error' ? ` ${reply.error}${reply.status === null ? '' : ` (HTTP ${reply.status})`}` : ''
    return fail(`答えが無い: ${reply.reason}${detail}`)
  }
  try {
    return asResult(await runChecker($, {
      payload, reply: reply.text, engine: { family: 'claude', ...config }, engine_failures: failures,
    }, Math.max(1_000, deadline - Date.now()), '--receive'))
  } catch (error) {
    return fail(error instanceof Error ? error.message : '返答を受けられない')
  }
}

// 先の系統には残りの半分、次の系統には残り全てを渡す。系統で検査できなければ次の系統へ移り、全て失敗すれば
// 全ての理由を付けて例外にする (呼び出し側が原文に理由を添える)。
async function check($: EngineInterface, payload: Payload): Promise<CheckResult> {
  const config = await settings($)
  const total = Number(await $.env.get('OUTPUT_GATE_TIMEOUT')) || DEFAULT_TIMEOUT_S
  const deadline = Date.now() + total * 1000
  const failures: Failure[] = []
  const order: ('codex' | 'claude')[] = config.first === 'same' ? ['claude', 'codex'] : ['codex', 'claude']
  for (const [position, family] of order.entries()) {
    const left = deadline - Date.now()
    const share = position < order.length - 1 ? left / 2 : left
    if (share <= 0) {
      failures.push({ family, reason: `${family} の検査役を試す時間が残っていない` })
      continue
    }
    if (family === 'codex') {
      let result
      try {
        result = asResult(await runChecker($, payload, share))
      } catch (error) {
        failures.push({ family, reason: error instanceof Error ? error.message : '検査処理を実行できなかった' })
        continue
      }
      if (!engineFailed(result)) return { ...result, engine_failures: [...failures, ...result.engine_failures] }
      failures.push(...result.engine_failures)
    } else {
      const result = await claudeCheck($, payload, config.claude, failures, Date.now() + share)
      if (!('status' in result)) {
        failures.push(result)
      } else if (!engineFailed(result)) {
        return result
      } else {
        failures.splice(0, failures.length, ...result.engine_failures)
      }
    }
  }
  throw new Error(failures.map(f => f.reason).join(' / ') || '検査役の系統が無い')
}

// --- 断片の扱い ---

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
    let run = result.at(-1)
    if (run === undefined || previous?.kind !== 'text' || previous.index !== chunk.index) {
      run = { index: chunk.index, text: '' }
      result.push(run)
    }
    run.text += chunk.text
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
      const text = checked[run]
      // checked は区間ごとに一つずつ作るため、ここには来ない。来たら hook の失敗として .catch の処理に任せる。
      if (text === undefined) throw new Error('区間の訂正版が無い')
      yield { kind: 'text', index: chunk.index, text }
    }
  }
}

// 検査の結果を区間ごとの表示する文字列にする。区間の数と合わなければ全体を最初の区間に入れる。
function perRun(bodies: string[], count: number): string[] {
  if (bodies.length === count) return bodies
  return [bodies.join('\n\n'), ...Array.from({ length: Math.max(0, count - 1) }, () => '')]
}

// 本文より前にそのまま流した断片の数。hook が失敗したとき、.catch の処理が同じ断片を重複して流さないために
// 使う。正常に終わったときと、.catch の処理が読んだときに消す。
const yielded = new Map<string, number>()
const stepKey = (e: TurnStepInput) => `${e.agentId ?? ''}:${e.turnId}:${e.index}`

// その検査でどの系統が判定し、ほかの系統がなぜ失敗し、どの指摘を捨てたかをターンの記録に残す。
const checkRecord = (index: number, final: boolean, result: CheckResult) => ({
  index, final, status: result.status, engine: result.engine ?? null, engine_failures: result.engine_failures,
  dropped: result.dropped, reason: result.reason,
})

async function payloadFor($: EngineInterface, turnId: string, turn: Turn, bodies: string[], final: boolean,
    continuation: 'withhold' | 'none'): Promise<Payload> {
  const said = spoken(await sessionMessages($))
  return {
    origin: 'claude', bodies, latest_user: turn.latest_user, recent_messages: said.slice(-RECENT_MESSAGES),
    turn_start_context: turn.turn_start_context, shown_text: turn.shown,
    evidence: final ? await currentEvidence($, turn) : [],
    previous_evidence: final ? await previousEvidence($, turnId, turn) : [],
    previous_findings: turn.round === 1 ? turn.findings : null, round: turn.round, final, continuation,
    engines: ['codex'], cyber_program: null,
  }
}

// 本文を捨て、gate_findings の呼び出しに差し替える前に、直させた回数と指摘を書く (ターン → 呼び出しの順)。
// 書けなければ例外。呼び出し側は差し替えず、ターンの記録を書く前の値 (直させていない) で書き直す。
async function recordSwap($: EngineInterface, turnId: string, turn: Turn, toolId: string, original: string,
    result: CheckResult) {
  // ターンが次の最終回答を経ずに終わったときに表示する文は、検査処理の display_text (置き換え済みの本文、
  // 未達の段落、証拠の欠けの注記) をそのまま使う。
  const display = result.display_text ?? original
  const next: Turn = { ...turn, round: 1, agent_message: result.agent_message, findings: result.findings, original,
    unmet: ENDED_UNFIXED + display, gate_tool_id: toolId }
  await $.state.set({ plugin: 'output-gate', key: 'turn', id: turnId }, next)
  await $.state.set({ plugin: 'output-gate', key: 'issued', id: toolId }, { turn_id: turnId, agent_message: result.agent_message! })
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    try {
      if (!(await skip($, undefined))) {
        await $.tool.register({
          name: GATE_TOOL_NAME, isDeferred: false, inputSchema: { type: 'object', properties: {} },
          description: '出力ゲートが回答の検査結果を返すために使う。出力ゲート自身が呼び出すもので、自分では呼ばない。',
        })
      }
    } catch {
      // 登録できなくても検査は続ける。差し替えた呼び出しは失敗し、次の最終回答で未達の項目付きで表示する。
    }
    return next(e)
  })

  on('turn.start', async ($, e, next) => {
    if (await skip($, e.agentId)) return next(e)
    try {
      const messages = await sessionMessages($)
      const context = [...lastExchange(messages, e.text), ...(e.text ? [{ role: 'user', text: e.text }] : [])]
      const latest = e.text || (spoken(messages).filter(m => m.role === 'user').at(-1)?.text ?? '')
      await $.state.set({ plugin: 'output-gate', key: 'turn', id: e.turnId }, newTurn(latest, context, Date.now()))
    } catch {
      // 記録できなければ、turn.step が会話の記録から作る。
    }
    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    if (e.tool === GATE_TOOL) {
      const { value } = await $.state.get({ plugin: 'output-gate', key: 'issued', id: e.tool_use_id })
      return { result: value ? value.agent_message : NOT_ISSUED }
    }
    if (await skip($, e.agentId)) return next(e)
    let result: ToolCallResult | undefined
    let error: unknown
    try {
      result = await next(e)
      return result
    } catch (thrown) {
      error = thrown
      throw thrown
    } finally {
      try {
        await $.state.set({ plugin: 'output-gate', key: 'evidence', id: e.tool_use_id }, recordOf(e, result, error))
      } catch {
        // 記録できなければ、検査ではこの呼び出しを取得できなかった範囲として扱う。
      }
    }
  })

  on('turn.step', async function* ($, e, next) {
    if (await skip($, e.agentId)) return yield* next(e)
    await markSession($, e)
    const key = stepKey(e)
    yielded.set(key, 0)
    const stream = next(e)
    const held: TurnStepChunk[] = []
    const toolIds: string[] = []
    let maxIndex = -1
    let isHolding = false
    let completed = false
    try {
      while (true) {
        const step = await stream.next()
        if (step.done) {
          const turn = await readTurn($, e.turnId)
          const stop = step.value.stopReason
          turn.tool_ids = [...turn.tool_ids, ...toolIds.filter(id => !turn.tool_ids.includes(id))]
          const split = runs(held)
          const final = stop !== null && FINAL_STOPS.has(stop)
          if (!isHolding || split.runs.every(run => run.text.trim() === '')) {
            // 本文の無い段は検査しない。表示済みの文章のうち検査していない分は turn.complete で判定する。
            await $.state.set({ plugin: 'output-gate', key: 'turn', id: e.turnId }, turn)
            if (isHolding) yield* held
            completed = true
            return step.value
          }
          const original = split.runs.map(run => run.text)
          if (!final) {
            // 途中の段は検査せずに流す (待たせないため)。表示した文章は最終回答の検査に「表示済み」として渡す。
            const text = original.join('\n\n')
            await $.state.set({ plugin: 'output-gate', key: 'turn', id: e.turnId },
              { ...turn, shown: turn.shown ? `${turn.shown}\n\n${text}` : text })
            yield* held
            completed = true
            return step.value
          }
          let result: CheckResult
          try {
            result = await check($, await payloadFor($, e.turnId, turn, original, final, 'withhold'))
          } catch (error) {
            const reason = UNCHECKED(error instanceof Error ? error.message : '検査できなかった')
            result = { status: 'unchecked', text: reason + original.join('\n\n'), bodies: [reason + original[0], ...original.slice(1)],
              findings: [], agent_message: null, fallback_text: null, fallback_bodies: null, reason, engine: null,
              engine_failures: [], dropped: [], unmet_text: null, display_text: null }
          }
          turn.checks = [...turn.checks, checkRecord(e.index, final, result)]
          // 検査の間に利用者の入力が届いて印が消えることがあるため、流す直前にも書き直す。
          await markSession($, e)
          if (final && turn.round === 0 && result.text === null && result.agent_message !== null) {
            const toolId = `toolu_outputgate_${crypto.randomUUID().replaceAll('-', '')}`
            let isSaved = true
            try {
              await recordSwap($, e.turnId, turn, toolId, original.join('\n\n'), result)
            } catch {
              isSaved = false
            }
            if (isSaved) {
              const index = maxIndex + 1
              yield { kind: 'tool', index, id: toolId, name: GATE_TOOL }
              yield { kind: 'input', index, json: '{}' }
              yield { kind: 'stop', stopReason: 'tool_use', usage: step.value.usage }
              completed = true
              return { ...step.value, answer: '', toolUses: [{ name: GATE_TOOL, input: {} }], stopReason: 'tool_use' }
            }
            result = { ...result, bodies: result.fallback_bodies ?? [result.fallback_text ?? original.join('\n\n')] }
          }
          const shown = perRun(result.bodies ?? [result.text ?? original.join('\n\n')], split.runs.length)
          const shownText = turn.shown ? `${turn.shown}\n\n${shown.join('\n\n')}` : shown.join('\n\n')
          // 最終回答として検査して表示した範囲 (judged_len) は、turn.complete で判定し直さない。
          const after: Turn = final ? { ...turn, shown: shownText, judged_len: shownText.length, original: null, unmet: null }
            : { ...turn, shown: shownText }
          try {
            await $.state.set({ plugin: 'output-gate', key: 'turn', id: e.turnId }, after)
          } catch {
            // 記録できなくても表示は続ける。
          }
          yield* rebuilt(held, split.owner, shown)
          completed = true
          return { ...step.value, answer: correctedAnswer(step.value.answer, split.runs, shown) }
        }
        const chunk = step.value
        if ('index' in chunk && typeof chunk.index === 'number') maxIndex = Math.max(maxIndex, chunk.index)
        if (chunk.kind === 'tool' && chunk.name !== GATE_TOOL) toolIds.push(chunk.id)
        // 最初の本文の断片から応答の終わりまでを止める。それより前の推論やツール呼び出しはすぐ流す。
        if (!isHolding && chunk.kind === 'text') {
          isHolding = true
          await setHolding($, 1)
        }
        if (isHolding) {
          held.push(chunk)
        } else {
          yielded.set(key, (yielded.get(key) ?? 0) + 1)
          yield chunk
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

  on('turn.complete', async ($, e, next) => {
    if (e.agentId !== undefined) return next(e)
    // 止めている間に中断や読み直しが起きて減らせなかった値を、メインのターンの終わりで 0 に戻す。
    try {
      await update($, holding, () => 0)
    } catch {
      // 表示のための値なので、書けなくても続ける。
    }
    const result = await next(e)
    if (await skip($, undefined)) return result
    let extra = ''
    let turn: Turn | null = null
    try {
      turn = (await $.state.get({ plugin: 'output-gate', key: 'turn', id: e.turnId })).value ?? null
      if (turn?.original != null) {
        // 差し替えた後、次の最終回答を経ずに終わった: 捨てた原文と未達の項目は会話記録にも無いため、ここで出す。
        extra = turn.unmet ?? turn.original
      } else if (turn && JUDGED_ENDS.has(e.reason) && turn.shown.slice(turn.judged_len).trim() !== '') {
        // 最終回答として検査していない文章が残ったまま終わった: 表示済みの文章を草稿にして 1〜3 を判定し、
        // 未達の項目を下に足す。
        const draft = turn.shown
        try {
          const checked = await check($, await payloadFor($, e.turnId, { ...turn, shown: '' }, [draft], true, 'none'))
          turn.checks = [...turn.checks, checkRecord(-1, true, checked)]
          if (checked.status === 'unchecked') extra = UNCHECKED(checked.reason ?? '検査できなかった').trim()
          else if (checked.unmet_text) extra = checked.unmet_text
        } catch (error) {
          extra = UNCHECKED(error instanceof Error ? error.message : '検査できなかった').trim()
        }
      }
    } catch {
      // 状態を読めなければ足すものは無い。
    }
    if (turn) {
      try {
        await saveTurnFile($, e.turnId, turn, await currentEvidence($, turn))
      } catch {
        // 次のターンでは、このターンの証拠を取得できなかった範囲として扱う。
      }
      try {
        for (const id of turn.tool_ids) await $.state.set({ plugin: 'output-gate', key: 'evidence', id: id }, null)
        if (turn.gate_tool_id !== null) {
          await $.state.set({ plugin: 'output-gate', key: 'issued', id: turn.gate_tool_id }, null)
        }
        await $.state.set({ plugin: 'output-gate', key: 'turn', id: e.turnId }, null)
      } catch {
        // 消せなくても、次のターンは別の turnId で記録する。
      }
    }
    // 主ループの回答と違う text は回答の下に表示される (会話記録は書き換わらない)。
    return extra === '' ? result : { ...result, text: extra }
  })

  on('ui.render', { component: 'Spinner' }, async ($, e, next) => {
    if ((await read($, holding)) > 0) {
      return next({ ...e, props: { ...e.props, suffix: `${e.props.suffix} 出力ゲートで回答を確認中` } })
    }
    return next(e)
  })
}
