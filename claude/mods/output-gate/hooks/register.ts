import { atom, update } from 'claude-code'
import type { EngineInterface, Register, ToolCallInput, ToolCallResult, TurnStepChunk, TurnStepInput } from 'claude-code'
import type { HoldingEvidence, HoldingMessage, HoldingTurn } from '../types/index.d.ts'

// 出力ゲートの Claude Code 側: モデルの応答の文字列を止め、共通の検査処理
// (~/.agent-shared/bin/output-gate-check.py) で検査し、訂正した文字列だけを流す。
// 流した文字列が画面と会話記録になる。検査できなければ原因をエージェントへ戻し、継続できない場合は未完了の案内だけを流す。
// 最終回答 (end_turn・stop_sequence の段) に未達があれば、本文を gate_findings の呼び出しに差し替え、
// 指摘をツールの結果として返して同じターンで直させる。停滞が続く場合は未解決を明示して表示する。
// 証拠は tool.call で記録した呼び出しと結果。

const holding = atom({ plugin: 'output-gate', key: 'holding' } as const, 0)
// 動いているメインのターンの ID。作業中に送られた入力を、そのターンの依頼に足すために使う。
const active = atom({ plugin: 'output-gate', key: 'active' } as const, null as string | null)

const UNAVAILABLE = '出力検査が完了していないため、回答は確定していません。\n\n'
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
const ENDED_UNFIXED = '回答は完了前に中断されました。\n\n'
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
  session_id?: string
  request_id?: string
  source_collector?: string
  source_mode?: string
  turn_id?: string
  context_dir?: string
  bodies: string[]
  latest_user: string
  recent_messages: HoldingMessage[]
  turn_start_context: HoldingMessage[]
  shown_text: string
  evidence: Item[]
  previous_evidence: PreviousTurn[]
  previous_findings: unknown[] | null
  round: number
  final: boolean
  continuation: 'withhold' | 'none'
  engines: ['codex']
  cyber_program: null
  progress_state?: Record<string, unknown> | null
}
type Failure = { family: string | null; reason: string }
type CheckResult = {
  context_metrics?: Record<string, unknown> | null
  status: 'checked' | 'unchecked'
  display_receipt?: string
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
  corrected_bodies?: string[]
  progress_state?: Record<string, unknown> | null
  recheck_required?: boolean
  stopped?: boolean
}
type Effort = 'low' | 'medium' | 'high' | 'xhigh' | 'max'
type Settings = { first: 'codex' | 'claude'; claude: { model: string; effort: Effort } }

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

type Said = { role: string; text: string; uuid?: string; id?: string; toolUses: { tool_use_id: string; tool: string }[] }

async function sessionMessages($: EngineInterface): Promise<Said[]> {
  const messages = await $.session.messages()
  return 'deny' in messages ? [] : messages
}

const spoken = (messages: Said[]) => messages.filter(m => m.text.trim() !== '').map(m => ({ role: m.role, text: m.text, ...((m.uuid || m.id) ? { native_id: m.uuid || m.id } : {}) }))

function precedingConversation(messages: Said[], prompt: string): HoldingMessage[] {
  const said = spoken(messages)
  if (said.at(-1)?.role === 'user' && said.at(-1)?.text === prompt) said.pop()
  return said
}

const newTurn = (latestUser: string, context: HoldingMessage[], now: number, requestId?: string): Turn => ({
  latest_user: latestUser, current_request_id: requestId, turn_start_context: context, started_at: now, tool_ids: [], shown: '', judged_len: 0,
  round: 0, agent_message: null, findings: [], original: null, unmet: null, gate_tool_id: null, checks: [],
})

async function readTurn($: EngineInterface, turnId: string): Promise<Turn> {
  const { value } = await $.state.get({ plugin: 'output-gate', key: 'turn', id: turnId })
  if (value) return value
  // turn.start を聞いていない (mod が途中で読み込まれた、resume の後など): 記録から作る。
  const said = spoken(await sessionMessages($))
  const latest = said.filter(m => m.role === 'user').at(-1)?.text ?? ''
  return newTurn(latest, said, Date.now())
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
    const root = await stateDir($)
    const pendingDir = root === undefined ? undefined : `${root}/claude-context/${await $.session.id()}/pending-turns`
    const recentFiles = kept((await turnFiles($, dir)).filter(f => f.turnId !== turnId), now)
    const pendingFiles = pendingDir === undefined ? [] : (await turnFiles($, pendingDir)).filter(f => f.turnId !== turnId)
    const files = new Map([...recentFiles, ...pendingFiles].map(file => [file.turnId, file]))
    for (const file of files.values()) {
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
  const root = await stateDir($)
  const pendingDir = root === undefined ? undefined : `${root}/claude-context/${await $.session.id()}/pending-turns`
  const pendingName = `${String(turn.started_at).padStart(13, '0')}-${turnId}.json`
  if (pendingDir !== undefined) {
    await $.fs.write(`${pendingDir}/${pendingName}.tmp`, JSON.stringify({ turn_id: turnId,
      time: new Date(turn.started_at).toISOString(), items }))
    await fileOps($, [[`${pendingDir}/${pendingName}.tmp`, `${pendingDir}/${pendingName}`]], [], [])
  }
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

async function checkerArgv($: EngineInterface, mode?: '--prepare' | '--receive' | '--finish-recheck' | '--confirm-display' | '--judge' | '--limits') {
  const home = await homeDir($)
  if (!home) throw new Error('ホームディレクトリが分からない')
  return [await findPython($), '-I', `${home}/.agent-shared/bin/output-gate-check.py`, ...(mode ? [mode] : [])]
}

async function checkerLimits($: EngineInterface): Promise<{ timeoutMs: number; cleanupMs: number; hedgeMs: number }> {
  const timeout = await $.env.get('OUTPUT_GATE_TIMEOUT')
  const result = await $.process.run(await checkerArgv($, '--limits'), {
    timeoutMs: 10_000, env: timeout ? { OUTPUT_GATE_TIMEOUT: timeout } : {},
  })
  if (result.exitCode !== 0) throw new Error('検査処理の待機時間を取得できなかった')
  const limits = JSON.parse(result.stdout) as { timeout_seconds: number; cleanup_seconds: number; hedge_seconds: number }
  if (!Number.isFinite(limits.timeout_seconds) || limits.timeout_seconds <= 0 ||
      !Number.isFinite(limits.cleanup_seconds) || limits.cleanup_seconds < 0 ||
      !Number.isFinite(limits.hedge_seconds) || limits.hedge_seconds <= 0) {
    throw new Error('検査処理の待機時間の形が違う')
  }
  return { timeoutMs: limits.timeout_seconds * 1000, cleanupMs: limits.cleanup_seconds * 1000,
    hedgeMs: limits.hedge_seconds * 1000 }
}

// budgetMs: 検査処理に渡す締切 (OUTPUT_GATE_TIMEOUT)。
async function runChecker($: EngineInterface, input: unknown, budgetMs: number, mode?: '--prepare' | '--receive' | '--finish-recheck' | '--confirm-display' | '--judge'):
    Promise<Record<string, unknown>> {
  const argv = await checkerArgv($, mode)
  const { cleanupMs } = await checkerLimits($)
  // process.run は最大 600 秒なので、検査と後始末を合わせた待機には使えない。
  const stream = $.process.spawn({ argv, input: JSON.stringify(input),
    env: { OUTPUT_GATE_TIMEOUT: (budgetMs / 1000).toFixed(3) } })
  const timer = new AbortController()
  const expired = $.clock.sleep(Math.max(1, Math.ceil(budgetMs) + cleanupMs), { signal: timer.signal })
    .then(() => { throw new Error('検査処理の待機時間を超えた') })
  let stdout = ''
  try {
    for (;;) {
      const next = await Promise.race([stream.next(), expired])
      if (next.done) {
        if (next.value.code !== 0) throw new Error(`検査処理が失敗した (終了コード ${next.value.code})`)
        break
      }
      if (next.value.stream === 'stdout') stdout += next.value.text
    }
  } catch {
    throw new Error('検査処理を実行できなかった')
  } finally {
    timer.abort()
    await stream.return()
  }
  return JSON.parse(stdout) as Record<string, unknown>
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

// 利用者の設定 (先に試す系統、Claude の系統のモデルと推論量)。検査処理と同じく、無ければ既定値、読めない・
// 形が違えば検査できなかった扱い (理由付き) にする。
async function settings($: EngineInterface): Promise<Settings> {
  const dir = await stateDir($)
  const path = (await $.env.get('OUTPUT_GATE_SETTINGS')) || (dir === undefined ? undefined : `${dir}/checker.json`)
  if (path === undefined || !(await $.fs.exists(path))) return { first: 'claude', claude: { model: 'opus', effort: 'low' } }
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
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw) || !['claude', 'codex', 'opposite', 'same', undefined].includes(data.first as string) ||
      !shaped(data.codex) || !shaped(data.claude)) {
    throw new Error(`検査役の設定 (${path}) の形が違う`)
  }
  // 推論量が $.model.complete の受け付けない値なら、呼び出しが拒まれて Claude の系統の失敗になる。
  // この mod が検査するのは Claude Code の回答なので、opposite は codex、same は claude と同じ。
  return { first: data.first === 'codex' || data.first === 'opposite' ? 'codex' : 'claude',
    claude: { model: data.claude?.model || 'opus', effort: (data.claude?.effort || 'low') as Effort } }
}

type ModelAttempt = { family: string; outcome: string; elapsed_ms: number; usage: unknown }
type RawAnswer = ({ reply: string; engine: unknown } | { failures: Failure[] }) & { usage?: unknown; model_attempts?: ModelAttempt[] }

async function rawAnswer($: EngineInterface, payload: Payload, prepared: Record<string, unknown>,
    config: Settings, family: 'claude' | 'codex', deadline: number, stop: AbortController): Promise<RawAnswer> {
  let usage: unknown = null
  try {
    const left = Math.floor(deadline - Date.now())
    if (left <= 0) throw new Error('時間が残っていない')
    if (family === 'claude') {
      // $.model.complete には返答の形を強制する手段が無い。CLI の検査役が --json-schema で受ける必須項目を
      // system で示さないと、検査役が項目を省いて同じ検証エラーを繰り返し、検査が完了しない。
      const schema = prepared['schema'] === undefined ? '' :
        `\n\nReply with one JSON object that conforms to this JSON Schema, with every required property:\n${JSON.stringify(prepared['schema'])}`
      const reply = await $.model.complete({ ...config.claude, system: String(prepared['system']) + schema,
        prompt: String(prepared['prompt']), maxTokens: CLAUDE_MAX_TOKENS, timeoutMs: left }, { signal: stop.signal })
      usage = reply.usage ?? null
      if (!reply.isAnswered) throw new Error(`答えが無い: ${reply.reason}`)
      return { reply: reply.text, engine: { family, ...config.claude }, usage }
    }
    const stream = $.process.spawn({ argv: await checkerArgv($, '--judge'),
      input: JSON.stringify({ payload, prompt: prepared['prompt'], transaction: prepared['transaction'] }),
      env: { OUTPUT_GATE_TIMEOUT: (left / 1000).toFixed(3) } })
    const cancel = () => { void stream.return().catch(() => {}) }
    stop.signal.addEventListener('abort', cancel, { once: true })
    let stdout = ''
    try {
      if (stop.signal.aborted) throw new Error('検査を中止した')
      while (true) {
        const next = await stream.next()
        if (next.done) {
          if (next.value.code !== 0) throw new Error('検査処理が失敗した')
          break
        }
        if (next.value.stream === 'stdout') stdout += next.value.text
      }
    } finally {
      stop.signal.removeEventListener('abort', cancel)
      await stream.return()
    }
    const result = JSON.parse(stdout) as Record<string, unknown>
    if (result['status'] === 'answered' && typeof result['reply'] === 'string')
      return { reply: result['reply'], engine: result['engine'], model_attempts: result['model_attempts'] as ModelAttempt[] | undefined }
    return { model_attempts: result['model_attempts'] as ModelAttempt[] | undefined, failures: Array.isArray(result['engine_failures']) && result['engine_failures'].length ?
      result['engine_failures'] as Failure[] : [{ family, reason: String(result['reason'] ?? '答えが無い') }] }
  } catch (error) {
    return { usage, failures: [{ family, reason: error instanceof Error ? error.message : '検査役を呼べない' }] }
  }
}

async function checkOnce($: EngineInterface, payload: Payload, deadline: number, hedgeMs: number): Promise<CheckResult> {
  const config = await settings($)
  let prepared = await runChecker($, payload, deadline - Date.now(), '--prepare')
  const failures: Failure[] = []
  while (prepared['status'] === 'ready') {
    const primary = new AbortController()
    const secondary = new AbortController()
    const timers = new AbortController()
    const first = config.first
    const other = first === 'claude' ? 'codex' : 'claude'
    const left = deadline - Date.now()
    if (left <= 0) throw new Error('検査の時間が残っていない')
    const attempts = new Map<string, ModelAttempt[]>()
    const pending = new Map<string, Promise<{ family: string; result: RawAnswer }>>()
    const start = (family: 'claude' | 'codex', stop: AbortController) => {
      const started = Date.now()
      const attempt: ModelAttempt = { family, outcome: 'running', elapsed_ms: 0, usage: null }
      attempts.set(family, [attempt])
      stop.signal.addEventListener('abort', () => {
        if (attempt.outcome === 'running') {
          attempt.outcome = 'cancelled'
          attempt.elapsed_ms = Date.now() - started
        }
      }, { once: true })
      pending.set(family, rawAnswer($, payload, prepared, config, family, deadline, stop).then(result => {
        if (attempt.outcome === 'running') {
          if (Array.isArray(result.model_attempts) && result.model_attempts.length) attempts.set(family, result.model_attempts)
          else Object.assign(attempt, { outcome: 'reply' in result ? 'answered' : 'failed', elapsed_ms: Date.now() - started, usage: result.usage ?? null })
        }
        return { family, result }
      }))
    }
    const wait = (ms: number, family: string) => $.clock.sleep(ms, { signal: timers.signal })
      .then(() => ({ family, result: { failures: [] } as RawAnswer }))
    const timeout = wait(left, 'timeout')
    const hedge = wait(Math.min(left / 2, hedgeMs), 'hedge')
    start(first, primary)
    let hedged = false
    let accepted: RawAnswer | undefined
    try {
      while (pending.size) {
        const next = await Promise.race([...pending.values(), timeout, ...(!hedged ? [hedge] : [])])
        if (next.family === 'timeout') throw new Error('検査の時間が残っていない')
        if (next.family === 'hedge') {
          hedged = true
          start(other, secondary)
          continue
        }
        pending.delete(next.family)
        if ('reply' in next.result) { accepted = next.result; break }
        failures.push(...next.result.failures)
        if (!hedged) { hedged = true; start(other, secondary) }
      }
    } finally {
      primary.abort()
      secondary.abort()
      timers.abort()
    }
    if (!accepted || !('reply' in accepted)) throw new Error(failures.map(f => f.reason).join(' / ') || '検査役の答えが無い')
    prepared = await runChecker($, { payload, reply: accepted.reply, engine: accepted.engine, transaction: prepared['transaction'], engine_failures: failures,
      model_attempts: [...attempts.values()].flat() },
      Math.max(1, deadline - Date.now()), '--receive')
  }
  return asResult(prepared)
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

function stopResult(result: CheckResult, original: string[], reason: string): CheckResult {
  if (result.status === 'unchecked') {
    const text = `[出力ゲート: ${reason}・未解決]\n\n${result.fallback_text ?? '出力検査が完了していません。'}`
    return { ...result, stopped: true, recheck_required: false, agent_message: null, text, bodies: [text] }
  }
  const bodies = [...(result.corrected_bodies?.length === original.length ? result.corrected_bodies : original)]
  const last = bodies.length - 1
  bodies[last] = `[出力ゲート: ${reason}・未解決]\n\n` + bodies[last] +
    (result.unmet_text ? '\n\n---\n' + result.unmet_text : '')
  return { ...result, stopped: true, recheck_required: false, agent_message: null, text: bodies.join('\n\n'), bodies }
}

async function check($: EngineInterface, payload: Payload): Promise<CheckResult> {
  const limits = await checkerLimits($)
  const deadline = Date.now() + limits.timeoutMs
  const initial = await checkOnce($, payload, deadline, limits.hedgeMs)
  if (!initial.recheck_required) return initial
  const left = deadline - Date.now()
  const { engines: _engines, ...unrestricted } = payload
  let rechecked: Record<string, unknown>
  try {
    if (left <= 0) throw new Error('再判定の時間が残っていません')
    rechecked = await runChecker($, { ...unrestricted, independent_recheck: true }, left)
  } catch (error) {
    rechecked = { status: 'unchecked', reason: error instanceof Error ? error.message : '再判定不能' }
  }
  try {
    return asResult(await runChecker($, { initial, rechecked }, 1000, '--finish-recheck'))
  } catch {
    return stopResult(initial, payload.bodies, '再判定結果を取得できないため自動差戻し停止')
  }
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
  dropped: result.dropped, reason: result.reason, context_metrics: result.context_metrics,
})

async function payloadFor($: EngineInterface, turnId: string, turn: Turn, bodies: string[], final: boolean,
    continuation: 'withhold' | 'none'): Promise<Payload> {
  const said = spoken(await sessionMessages($)).map(m => m.role === 'assistant' && m.text === turn.original ? { ...m, displayed: false } : m)
  const contextRoot = await stateDir($)
  const sessionId = await $.session.id()
  return {
    session_id: sessionId, turn_id: turnId, request_id: turn.current_request_id, source_collector: 'claude-mod', source_mode: 'snapshot',
    context_dir: contextRoot === undefined ? undefined : `${contextRoot}/claude-context/${sessionId}`,
    origin: 'claude', bodies, latest_user: turn.latest_user, recent_messages: said,
    turn_start_context: turn.turn_start_context, shown_text: turn.shown,
    evidence: final ? await currentEvidence($, turn) : [],
    previous_evidence: final ? await previousEvidence($, turnId, turn) : [],
    previous_findings: turn.round >= 1 ? turn.findings : null, round: turn.round, final, continuation,
    progress_state: turn.progress_state,
    engines: ['codex'], cyber_program: null,
  }
}

// 本文を捨て、gate_findings の呼び出しに差し替える前に、直させた回数と指摘を書く (ターン → 呼び出しの順)。
// 書けなければ例外。呼び出し側は差し替えず、ターンの記録を書く前の値 (直させていない) で書き直す。
async function recordSwap($: EngineInterface, turnId: string, turn: Turn, toolId: string, original: string,
    result: CheckResult) {
  const display = result.status === 'unchecked' ? result.fallback_text ?? '出力検査が完了していません。' :
    result.corrected_bodies?.join('\n\n') ?? original
  const next: Turn = { ...turn, round: turn.round + 1, progress_state: result.progress_state, agent_message: result.agent_message, findings: result.findings,
    original, unmet: ENDED_UNFIXED + display, display_clean: true, gate_tool_id: toolId }
  await $.state.set({ plugin: 'output-gate', key: 'turn', id: turnId }, next)
  await $.state.set({ plugin: 'output-gate', key: 'issued', id: toolId }, { turn_id: turnId, agent_message: result.agent_message! })
  // 前に差し替えた呼び出しの指摘は返し終えている。turn.complete が消すのは最後の呼び出しだけなので、ここで消す。
  if (turn.gate_tool_id !== null) {
    try {
      await $.state.set({ plugin: 'output-gate', key: 'issued', id: turn.gate_tool_id }, null)
    } catch {
      // 消せなくても差し替えは続ける。残るのは返し終えた呼び出しの指摘だけ。
    }
  }
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
      // 登録できなくても検査は続ける。差し替えた呼び出しは失敗し、次の最終回答をまた検査する。
    }
    return next(e)
  })

  on('turn.start', async ($, e, next) => {
    if (await skip($, e.agentId)) return next(e)
    try {
      const messages = await sessionMessages($)
      const context = [...precedingConversation(messages, e.text), ...(e.text ? [{ role: 'user', text: e.text }] : [])]
      const latest = e.text || (spoken(messages).filter(m => m.role === 'user').at(-1)?.text ?? '')
      await $.state.set({ plugin: 'output-gate', key: 'turn', id: e.turnId }, newTurn(latest, context, Date.now(), e.text.trim() ? `${e.turnId}:initial-user` : undefined))
      if (e.agentId === undefined) await update($, active, () => e.turnId)
    } catch {
      // 記録できなければ、turn.step が会話の記録から作る。
    }
    return next(e)
  })

  // 作業中に送られた入力も依頼の一部として扱う。利用者は一つの依頼を何通かに分けて送ることがあるため。
  // ターンを始める入力は turn.start が記録するので、ここでは動いているターンがあるときだけ足す。
  on('prompt.submit', async ($, e, next) => {
    const result = await next(e)
    if (e.command !== undefined || e.isMeta || !e.text.trim()) return result
    try {
      if (await skip($, undefined)) return result
      const { value: turnId } = await $.state.get({ plugin: 'output-gate', key: 'active' })
      if (!turnId) return result
      const { value: turn } = await $.state.get({ plugin: 'output-gate', key: 'turn', id: turnId })
      if (!turn) return result
      await $.state.set({ plugin: 'output-gate', key: 'turn', id: turnId },
        { ...turn, current_request_id: `${turnId}:queued:${crypto.randomUUID()}`, latest_user: turn.latest_user ? `${turn.latest_user}\n\n${e.text}` : e.text })
    } catch {
      // 足せなければ、検査役は会話の記録から読む。
    }
    return result
  })

  on('tool.call', async ($, e, next) => {
    if (e.tool === GATE_TOOL) {
      const { value } = await $.state.get({ plugin: 'output-gate', key: 'issued', id: e.tool_use_id })
      return { result: '', context: [value ? value.agent_message : NOT_ISSUED] }
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
          let payload: Payload | undefined
          try {
            payload = await payloadFor($, e.turnId, turn, original, final, 'withhold')
            result = await check($, payload)
          } catch (error) {
            const reason = error instanceof Error ? error.message : '検査できなかった'
            try {
              if (!payload) throw new Error(reason)
              result = asResult(await runChecker($, { payload, unavailable_reason: reason }, 1000, '--receive'))
            } catch {
              const text = `出力検査が完了していないため、回答は確定していません。\n${reason}`
              result = { status: 'unchecked', stopped: true, text, bodies: [text],
                findings: [], agent_message: null, fallback_text: text, fallback_bodies: [text], reason, engine: null,
                engine_failures: [], dropped: [], unmet_text: null, display_text: null }
            }
          }
          turn.checks = [...turn.checks, checkRecord(e.index, final, result)]
          // 検査の間に利用者の入力が届いて印が消えることがあるため、流す直前にも書き直す。
          await markSession($, e)
          if (final && result.text === null && result.agent_message !== null) {
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
            result = stopResult(result, original, '継続状態を保存できないため自動差戻し停止')
          }
          const shown = perRun(result.status === 'unchecked' ? [result.fallback_text ?? UNAVAILABLE.trim()] :
            result.stopped ? result.bodies ?? original :
              result.findings.length ? result.corrected_bodies ?? original :
              result.bodies ?? [result.text ?? original.join('\n\n')], split.runs.length)
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
          if (result.display_receipt) {
            try {
              const root = await stateDir($)
              if (root !== undefined) await runChecker($, { context_dir: `${root}/claude-context/${await $.session.id()}`,
                token: result.display_receipt, text: shown.join('\n\n') }, 5000, '--confirm-display')
            } catch {
              // A failed delivery receipt leaves the proposed focus and completion unconfirmed.
            }
          }
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
    // hook 自体が失敗した場合も、すでに流した断片は繰り返さない。
    let skipped = yielded.get(stepKey(e)) ?? 0
    yielded.delete(stepKey(e))
    let marked = false
    const stream = next(e)
    while (true) {
      const step = await stream.next()
      if (step.done) return { ...step.value, answer: UNAVAILABLE.trim() }
      if (skipped > 0) {
        skipped -= 1
        continue
      }
      if (!marked && step.value.kind === 'text') {
        marked = true
        yield { ...step.value, text: UNAVAILABLE.trim() }
      } else if (step.value.kind !== 'text') {
        yield step.value
      }
    }
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId !== undefined) return next(e)
    // 止めている間に中断や読み直しが起きて減らせなかった値を、メインのターンの終わりで 0 に戻す。
    try {
      await update($, holding, () => 0)
      await update($, active, () => null)
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
        extra = turn.display_clean ? turn.unmet ?? ENDED_UNFIXED.trim() : ENDED_UNFIXED + turn.original
      } else if (turn && JUDGED_ENDS.has(e.reason) && turn.shown.slice(turn.judged_len).trim() !== '') {
        // 最終回答として検査していない文章が残ったまま終わった: 表示済みの文章を草稿にして 1〜3 を判定し、
        // 未達の項目を下に足す。
        const draft = turn.shown
        try {
          const checked = await check($, await payloadFor($, e.turnId, { ...turn, shown: '' }, [draft], true, 'none'))
          turn.checks = [...turn.checks, checkRecord(-1, true, checked)]
          if (checked.status === 'unchecked') extra = UNAVAILABLE.trim()
        } catch {
          extra = UNAVAILABLE.trim()
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

  on('ui.render', async ($, e, next) => {
    if ((e.component === 'ToolUse' || e.component === 'ToolResult') &&
        (e.props as { tool?: string }).tool === GATE_TOOL) {
      const { Text } = $.ui.resolve(e)
      return Text({ children: '' })
    }
    return next(e)
  })
}
