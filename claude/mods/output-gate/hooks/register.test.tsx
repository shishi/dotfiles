import { expect, mock, test } from 'claude-code/testing'
import type { On, TurnStepChunk } from 'claude-code'

const STEP = { turnId: 't1', index: 0, model: 'm', messageCount: 2 } as const
const PREFIX = '[出力ゲート: 検査できませんでした'
const UNAVAILABLE = '回答の確認を完了できませんでした。\n\n'
const GATE_TOOL = 'mcp__output-gate__gate_findings'
const NOT_ISSUED = '出力ゲートが出した呼び出しではなく、検査は行われていない'
const UNMET_TEXT = '出力ゲート: 次の点は確かめられていません\n- 確認していない主張: 「全部通った」'
const UNMET = '\n\n---\n' + UNMET_TEXT

type Payload = {
  origin: string; latest_user: string; recent_messages: { role: string; text: string }[]; bodies: string[]
  turn_start_context: { role: string; text: string }[]; shown_text: string; final: boolean; round: number
  continuation?: string; engines?: string[]; previous_findings?: unknown
  evidence: { id: string; tool?: string; command?: string; output?: string; failed?: boolean; unavailable?: boolean; note?: string }[]
  previous_evidence: { turn_id: string; time: string; items: { id: string; unavailable?: boolean; output?: string }[] }[]
}
type Result = Record<string, unknown>
type Message = { role: 'user' | 'assistant'; text: string; toolUses: { tool_use_id: string; tool: string; input: Record<string, unknown> }[] }

const done = { stderr: '', isStdoutTruncated: false, isStderrTruncated: false }
const ok = (value: unknown) => ({ value: { ...done, exitCode: 0, stdout: JSON.stringify(value) } })

// 検査処理の結果: 検査済みで本文をそのまま (または変えて) 表示する。
const checked = (p: Payload, change = (s: string) => s): Result => {
  const bodies = p.bodies.map(change)
  return { status: 'checked', text: bodies.join('\n\n'), bodies, findings: [], agent_message: null,
    fallback_text: null, fallback_bodies: null, reason: null, engine: { family: 'codex' }, engine_failures: [] }
}
const replaceKiku = (p: Payload) => checked(p, s => s.replaceAll('効く', '速い'))
const FINDING = { kind: 'unverified_claim', excerpt: { source: 'draft', text: '全部通った' }, evidence: [] }
// 未達あり: 続けさせられるなら何回目 (round) でもエージェントへの指摘、続けさせられない場合は未達の項目付きの本文。
const unmet = (p: Payload): Result => {
  const marked = [...p.bodies.slice(0, -1), p.bodies.at(-1) + UNMET]
  const base = { ...checked(p), findings: [FINDING], unmet_text: UNMET_TEXT, display_text: marked.join('\n\n'),
    corrected_bodies: p.bodies,
    progress_state: { round: p.round, stalled: 0, bodies: p.bodies, findings: [FINDING], evidence: p.evidence } }
  if (p.continuation === 'none') return { ...base, text: marked.join('\n\n'), bodies: marked }
  const fallback = ['[出力ゲート: 指摘を保存できなかったため、直させずに表示します]\n\n' + marked[0], ...marked.slice(1)]
  return { ...base, text: null, bodies: null, agent_message: '指摘: 全部通った の証拠が無い',
    fallback_text: fallback.join('\n\n'), fallback_bodies: fallback }
}
const codexFailed = (p: Payload): Result => ({ status: 'unchecked', text: `[出力ゲート: 検査できませんでした — codex 不調]\n\n${p.bodies.join('\n\n')}`,
  bodies: p.bodies, findings: [], agent_message: null, reason: 'codex 不調', engine: null,
  engine_failures: [{ family: 'codex', reason: 'codex 不調' }] })

type Fs = Map<string, string>
const norm = (path: string) => String(path).replaceAll('\\', '/').replace(/^[A-Za-z]:/, '')

// このマシンで出力ゲートを有効にした状態 (状態ディレクトリの claude-enabled を読める) と、記憶だけのファイル。
function world(on: On, options: { env?: Record<string, string>; enabled?: boolean; messages?: Message[] } = {}) {
  const fs: Fs = new Map()
  if (options.enabled ?? true) fs.set('/state/output-gate/claude-enabled', '')
  mock.env(on, { HOME: '/home/u', XDG_STATE_HOME: '/state', ...options.env })
  on('session.id', () => ({ value: 'sess-1' }))
  on('session.messages', () => ({ value: options.messages ?? [{ role: 'user' as const, text: '設定を教えて', toolUses: [] }] }))
  on('fs.read', (_$, e) => {
    const text = fs.get(norm(e.path))
    if (text === undefined) throw new Error('no such file')
    if (text.length > 4 * 1024 * 1024) throw new Error('over 4 MiB')
    return { value: text }
  })
  on('fs.exists', (_$, e) => ({ value: fs.has(norm(e.path)) || [...fs.keys()].some(p => p.startsWith(norm(e.path) + '/')) }))
  on('fs.write', (_$, e) => {
    fs.set(norm(e.path), e.text)
    return { value: undefined }
  })
  on('fs.list', (_$, e) => {
    const dir = norm(e.path ?? '') + '/'
    const below = [...fs.keys()].filter(p => p.startsWith(dir)).map(p => p.slice(dir.length))
    const files = below.filter(p => !p.includes('/'))
    const dirs = [...new Set(below.filter(p => p.includes('/')).map(p => p.split('/')[0]!))]
    return { value: [
      ...files.map(name => ({ name, kind: 'file' as const, size: fs.get(dir + name)!.length, mtimeMs: 0, isLink: false })),
      ...dirs.map(name => ({ name, kind: 'dir' as const, size: 0, mtimeMs: 0, isLink: false })),
    ] }
  })
  return fs
}

const runs: { argv: string[]; env: Record<string, string> }[] = []
type Checker = { prepare?: () => ReturnType<typeof ok>; bulk?: (p: Payload) => Result;
  finish?: (r: { initial: Result; rechecked: Result }) => Result;
  receive?: (r: { payload: Payload; reply: string; engine: unknown; engine_failures?: unknown[] }) => Result }
// 検査処理の代わり: Python の確認・ファイルの置き換えと削除は記憶のファイルで行い、検査は与えた関数で答える。
function checker(on: On, fs: Fs, answer: Checker | ((p: Payload) => Result), calls: Payload[] = []) {
  runs.length = 0
  const given = typeof answer === 'function' ? { bulk: answer } : answer
  on('process.run', (_$, e) => {
    const argv = e.argv.map(String)
    const code = argv.indexOf('-c')
    if (code >= 0 && argv.length > code + 2) {
      const ops = JSON.parse(argv[code + 2]!) as { replace: [string, string][]; remove: string[] }
      for (const [from, to] of ops.replace) {
        fs.set(norm(to), fs.get(norm(from))!)
        fs.delete(norm(from))
      }
      for (const path of ops.remove) fs.delete(norm(path))
      return { value: { ...done, exitCode: 0, stdout: '' } }
    }
    if (e.init?.stdin === undefined) return { value: { ...done, exitCode: 0, stdout: '' } }
    runs.push({ argv, env: e.init?.env ?? {} })
    if (argv.includes('--prepare') && given.prepare) return given.prepare()
    if (argv.includes('--prepare')) return ok({ status: 'ready', system: 'SYSTEM', prompt: 'PROMPT', schema: {} })
    if (argv.includes('--receive')) {
      const request = JSON.parse(e.init.stdin)
      calls.push(request.payload)
      return ok(given.receive!(request))
    }
    if (argv.includes('--finish-recheck')) return ok(given.finish!(JSON.parse(e.init.stdin)))
    const payload = JSON.parse(e.init.stdin) as Payload
    calls.push(payload)
    return ok(given.bulk!(payload))
  })
  return calls
}

const STOP = (stopReason: 'end_turn' | 'tool_use' | 'max_tokens' = 'end_turn'): TurnStepChunk => ({ kind: 'stop', stopReason, usage: null })
// 一番下のモデルの代わり: 段 (index) ごとに与えた断片を流し、応答を返す。script.steps は後から差し替えられる。
function model(on: On, steps: TurnStepChunk[][]) {
  const script = { steps }
  on('turn.step', async function* (_$, e) {
    const chunks = script.steps[e.index] ?? script.steps.at(-1)!
    for (const chunk of chunks) yield chunk
    const answer = chunks.map(c => (c.kind === 'text' ? c.text : '')).join('')
    const stop = chunks.find(c => c.kind === 'stop')
    const stopReason = stop?.kind === 'stop' ? stop.stopReason : 'end_turn'
    return { turnId: e.turnId, index: e.index, answer, toolUses: [], stopReason, usage: null }
  })
  return script
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function run($: any, input: object = STEP) {
  const stream = $.turn.step({ ...STEP, ...input })
  const chunks: TurnStepChunk[] = []
  let result
  while (true) {
    const step = await stream.next()
    if (step.done) {
      result = step.value
      break
    }
    chunks.push(step.value)
  }
  return { chunks, result, text: chunks.map(c => (c.kind === 'text' ? c.text : '')).join('') }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const start = ($: any, text = '設定を教えて', turnId = 't1') => $.turn.start({ text, turnId })
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const complete = ($: any, reason = 'answer', turnId = 't1') =>
  $.turn.complete({ turnId, reason, answer: '', durationMs: 1, isAborted: reason === 'aborted' })
function tools(on: On, answer: (e: { tool: string; tool_use_id: string; command?: unknown }) => object = () => ({ result: 'ok', text: 'ok' })) {
  on('turn.complete', (_$, e) => ({ text: e.answer }))
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('tool.call', (_$, e) => answer(e as never) as never)
}
const TEXT = (index: number, text: string): TurnStepChunk => ({ kind: 'text', index, text })
const TOOL = (index: number, id: string, name = 'Bash'): TurnStepChunk => ({ kind: 'tool', index, id, name })

test('the answer is shown only after the check, corrected', async ($, on) => {
  const fs = world(on)
  const calls = checker(on, fs, replaceKiku)
  model(on, [[TEXT(0, 'これは'), TEXT(0, '効く。'), STOP()]])
  const { text } = await run($)
  expect(text).toBe('これは速い。')
  expect(calls.length).toBe(1)
  expect(calls[0]?.bodies).toEqual(['これは効く。'])
  expect(calls[0]?.origin).toBe('claude')
  expect(calls[0]?.engines).toEqual(['codex'])
  expect(calls[0]?.final).toBe(true)
  expect(calls[0]?.latest_user).toBe('設定を教えて')
})

test('input sent while the turn runs joins its request', async ($, on) => {
  const fs = world(on)
  const calls = checker(on, fs, replaceKiku)
  tools(on)
  on('prompt.submit', (_$, e) => ({ text: e.text }))
  model(on, [[TEXT(0, 'これは効く。'), STOP()]])
  await start($)
  await $.prompt.submit({ text: 'テストも回して' })
  await run($)
  expect(calls.at(-1)?.latest_user).toBe('設定を教えて\n\nテストも回して')
})

test('a failed check shows the original with the reason', async ($, on) => {
  const fs = world(on)
  on('process.run', (_$, e) => ({ value: { ...done, exitCode: e.init?.stdin === undefined ? 0 : 1, stdout: '' } }))
  void fs
  model(on, [[TEXT(0, 'これは効く。'), STOP()]])
  const { text } = await run($)
  expect(text).toBe(UNAVAILABLE + 'これは効く。')
})

test('an unchecked result without a reason gets one', async ($, on) => {
  const fs = world(on)
  checker(on, fs, p => ({ status: 'unchecked', text: p.bodies.join(''), bodies: p.bodies }))
  model(on, [[TEXT(0, 'これは効く。'), STOP()]])
  const { text } = await run($)
  expect(text).toBe(UNAVAILABLE + 'これは効く。')
})

test('text resent after a retry marker is checked with the rest in one call', async ($, on) => {
  // 本文が流れ始めた後の再試行では、同じ index の本文がもう一度届く。続いて届いた区間ごとに元の位置に出す。
  const fs = world(on)
  const calls = checker(on, fs, replaceKiku)
  const retry: TurnStepChunk = { kind: 'thinking', index: 1, text: '再試行' }
  model(on, [[TEXT(0, 'これは'), TEXT(0, '効く。'), retry, TEXT(0, 'これは効く。'), STOP()]])
  const { chunks } = await run($)
  expect(chunks).toEqual([TEXT(0, 'これは速い。'), retry, TEXT(0, 'これは速い。'), STOP()])
  expect(calls.length).toBe(1)
})

test('the answer handed to hooks above follows the attempt the engine kept', async ($, on) => {
  const fs = world(on)
  checker(on, fs, replaceKiku)
  on('turn.step', async function* (_$, e) {
    yield TEXT(0, '捨てる本文は効く。')
    yield TEXT(2, '捨てる二つ目。')
    yield { kind: 'thinking', index: 1, text: '再試行' }
    yield TEXT(0, 'これは効く。')
    yield STOP()
    return { turnId: e.turnId, index: e.index, answer: 'これは効く。', toolUses: [], stopReason: 'end_turn' as const, usage: null }
  })
  const { result } = await run($)
  expect(result.answer).toBe('これは速い。')
})

test('a correction of abandoned text is not applied inside the kept text', async ($, on) => {
  const fs = world(on)
  checker(on, fs, p => checked(p, s => (s === 'foo' ? 'bar' : s)))
  const kept = '```' + String.fromCharCode(10) + 'foo' + String.fromCharCode(10) + '```'
  on('turn.step', async function* (_$, e) {
    yield TEXT(0, 'foo')
    yield { kind: 'thinking', index: 1, text: '再試行' }
    yield TEXT(0, kept)
    yield STOP()
    return { turnId: e.turnId, index: e.index, answer: kept, toolUses: [], stopReason: 'end_turn' as const, usage: null }
  })
  const { result } = await run($)
  expect(result.answer).toBe(kept)
})

test('a failed continuation write preserves the kept retry answer and its findings for upper hooks', async ($, on) => {
  const fs = world(on)
  checker(on, fs, unmet)
  on('state.set', (_$, e, next) => e.key === 'issued' && e.value !== null ? { deny: 'read only' } as never : next(e))
  on('turn.step', async function* (_$, e) {
    yield TEXT(0, '破棄する試行。')
    yield { kind: 'thinking', index: 1, text: '再試行' }
    yield TEXT(0, '全部通った。')
    yield STOP()
    return { turnId: e.turnId, index: e.index, answer: '全部通った。', toolUses: [], stopReason: 'end_turn' as const, usage: null }
  })
  const { result } = await run($)
  expect(result.answer).toContain('全部通った。')
  expect(result.answer).toContain(UNMET_TEXT)
  expect(result.answer).toContain('自動差戻し停止・未解決')
})

test('a machine where the gate is not enabled is not checked and has no tool', async ($, on) => {
  const fs = world(on, { enabled: false })
  const calls = checker(on, fs, replaceKiku)
  const registered: string[] = []
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('tool.register', (_$, e) => {
    registered.push(e.name)
    return { value: { tool: GATE_TOOL } }
  })
  model(on, [[TEXT(0, 'これは効く。'), STOP()]])
  await $.session.start({ cwd: '/w', surface: null, isInteractive: false })
  const { text } = await run($)
  expect(text).toBe('これは効く。')
  expect(calls.length).toBe(0)
  expect(registered).toEqual([])
})

test('the tool is registered at the start of an enabled session', async ($, on) => {
  world(on)
  const registered: string[] = []
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('tool.register', (_$, e) => {
    registered.push(e.name)
    return { value: { tool: GATE_TOOL } }
  })
  await $.session.start({ cwd: '/w', surface: null, isInteractive: false })
  expect(registered).toEqual(['gate_findings'])
})

test('steps of a subagent are not checked', async ($, on) => {
  const fs = world(on)
  const calls = checker(on, fs, replaceKiku)
  model(on, [[TEXT(0, 'これは効く。'), STOP()]])
  const { text } = await run($, { agentId: 'a1' })
  expect(text).toBe('これは効く。')
  expect(calls.length).toBe(0)
})

test('a delegated session is not checked and has no tool', async ($, on) => {
  const fs = world(on, { env: { AGENT_DELEGATED_SESSION: '1' } })
  const calls = checker(on, fs, replaceKiku)
  const registered: string[] = []
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('tool.register', (_$, e) => {
    registered.push(e.name)
    return { value: { tool: GATE_TOOL } }
  })
  model(on, [[TEXT(0, 'これは効く。'), STOP()]])
  await $.session.start({ cwd: '/w', surface: null, isInteractive: false })
  const { text } = await run($)
  expect(text).toBe('これは効く。')
  expect(calls.length).toBe(0)
  expect(registered).toEqual([])
})

test('chunks keep their order and tool calls are not rewritten', async ($, on) => {
  const fs = world(on)
  checker(on, fs, replaceKiku)
  const tool = TOOL(1, 'toolu_1')
  const input: TurnStepChunk = { kind: 'input', index: 1, json: '{"command":"echo 効く"}' }
  model(on, [[{ kind: 'thinking', index: 0, text: '考える' }, TEXT(0, 'これは効く。'), tool, input, STOP('tool_use')]])
  const { chunks } = await run($)
  expect(chunks.map(c => c.kind)).toEqual(['thinking', 'text', 'tool', 'input', 'stop'])
  expect(chunks[2]).toEqual(tool)
  expect(chunks[3]).toEqual(input)
})

test('two text blocks of a final answer are checked in one call', async ($, on) => {
  const fs = world(on)
  const calls = checker(on, fs, replaceKiku)
  model(on, [[TEXT(0, '前は効く。'), TEXT(2, '後も効く。'), STOP()]])
  const { chunks } = await run($)
  expect(chunks.filter(c => c.kind === 'text')).toEqual([TEXT(0, '前は速い。'), TEXT(2, '後も速い。')])
  expect(calls.length).toBe(1)
  expect(calls[0]?.bodies).toEqual(['前は効く。', '後も効く。'])
})

test('the spinner does not show inspection details while the answer is held', async ($, on) => {
  const fs = world(on)
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    const props = e.props as { word: string; suffix: string }
    return <Text>{`${props.word}${props.suffix}`}</Text>
  })
  let seen = ''
  on('process.run', async (_$, e) => {
    if (e.init?.stdin === undefined) return { value: { ...done, exitCode: 0, stdout: '' } }
    const ui = await $.ui.mount({
      plugin: 'output-gate', surface: 'terminal', component: 'Spinner', requestId: 'main',
      props: { word: 'Working', message: null, suffix: '…', mode: 'responding' },
    })
    seen = (await ui.find({ type: 'Text' }))?.text ?? ''
    await ui.unmount()
    return ok(replaceKiku(JSON.parse(e.init.stdin) as Payload))
  })
  void fs
  model(on, [[TEXT(0, 'これは効く。'), STOP()]])
  await run($)
  expect(seen).toBe('Working…')
  const ui = await $.ui.mount({
    plugin: 'output-gate', surface: 'terminal', component: 'Spinner', requestId: 'main',
    props: { word: 'Working', message: null, suffix: '…', mode: 'responding' },
  })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('Working…')
  await ui.unmount()
})

test('only the inspection tool cards are hidden', async ($, on) => {
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    const props = e.props as { tool?: string; output?: string }
    return <Text>{`${props.tool}:${props.output ?? ''}`}</Text>
  })
  for (const component of ['ToolUse', 'ToolResult'] as const) {
    for (const tool of [GATE_TOOL, 'mcp__other__tool']) {
      const ui = await $.ui.mount({
        plugin: 'output-gate', surface: 'terminal', component, requestId: 'toolu_test',
        props: { tool, output: 'DETAIL', tool_use_id: 'toolu_test' },
      })
      const text = (await ui.find({ type: 'Text' }))?.text ?? ''
      expect(text).toBe(tool === GATE_TOOL ? '' : `${tool}:DETAIL`)
      await ui.unmount()
    }
  }
})

test('the session is marked so that the display hook leaves it to the mod', async ($, on) => {
  const fs = world(on)
  checker(on, fs, replaceKiku)
  model(on, [[TEXT(0, 'これは効く。'), STOP()]])
  await run($)
  expect(fs.get('/state/output-gate/claude-mod/sess-1')).toBe('t1')   // 印には今のターンの識別子を書く
})

test('a checker call that is cut off shows the original with the reason', async ($, on) => {
  world(on)
  on('process.run', (_$, e) => {
    if (e.init?.stdin === undefined) return { value: { ...done, exitCode: 0, stdout: '' } }
    throw new Error('timed out')
  })
  model(on, [[TEXT(0, 'これは効く。'), STOP()]])
  const { text } = await run($)
  expect(text).toBe(UNAVAILABLE + 'これは効く。')
})

test('a failure of the hook itself shows the original with the reason', async ($, on) => {
  on('env.get', () => {
    throw new Error('env is broken')
  })
  on('process.run', () => ({ value: { ...done, exitCode: 0, stdout: '' } }))
  model(on, [[TEXT(0, 'これは効く。'), STOP()]])
  const { text } = await run($)
  expect(text).toBe(UNAVAILABLE + 'これは効く。')
})

// --- 検査役の系統 ---

type Completion = { model: string; effort?: string; maxTokens?: number; system?: string; prompt: string }
function claudeModel(on: On, answer: (e: Completion) => object, calls: Completion[] = []) {
  on('model.complete', (_$, e) => {
    calls.push(e as Completion)
    return { value: answer(e as Completion) } as never
  })
  return calls
}
const usage = (output: number) => ({ input_tokens: 1, output_tokens: output, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 })

test('with Codex first, when the Codex checker fails, Claude checks through the session at opus / low', async ($, on) => {
  const fs = world(on)
  fs.set('/state/output-gate/checker.json', JSON.stringify({ first: 'codex' }))
  const received: { engine: unknown; engine_failures?: unknown[] }[] = []
  checker(on, fs, { bulk: codexFailed, receive: r => (received.push(r), replaceKiku(r.payload)) })
  const completions = claudeModel(on, () => ({ isAnswered: true, text: '{"replacements":[],"findings":[]}', usage: usage(10) }))
  model(on, [[TEXT(0, 'これは効く。'), STOP()]])
  const { text } = await run($)
  expect(text).toBe('これは速い。')
  expect(completions.length).toBe(1)
  expect(completions[0]?.model).toBe('opus')
  expect(completions[0]?.effort).toBe('low')
  expect(typeof completions[0]?.maxTokens).toBe('number')
  expect(completions[0]?.system).toBe('SYSTEM')
  expect(completions[0]?.prompt).toBe('PROMPT')
  expect(received[0]?.engine).toEqual({ family: 'claude', model: 'opus', effort: 'low' })
  expect(received[0]?.engine_failures).toEqual([{ family: 'codex', reason: 'codex 不調' }])
})

test('the settings choose sonnet, and Claude first', async ($, on) => {
  const fs = world(on)
  fs.set('/state/output-gate/checker.json', JSON.stringify({ first: 'same', claude: { model: 'sonnet' } }))
  const bulk: Payload[] = []
  checker(on, fs, { bulk: p => (bulk.push(p), replaceKiku(p)), receive: r => replaceKiku(r.payload) })
  const completions = claudeModel(on, () => ({ isAnswered: true, text: '{}', usage: usage(10) }))
  model(on, [[TEXT(0, 'これは効く。'), STOP()]])
  const { text } = await run($)
  expect(text).toBe('これは速い。')
  expect(completions.map(c => c.model)).toEqual(['sonnet'])
  expect(bulk.length).toBe(0)
})

test('when both checkers fail, the original is shown with both reasons', async ($, on) => {
  const fs = world(on)
  checker(on, fs, { bulk: codexFailed, receive: r => replaceKiku(r.payload) })
  claudeModel(on, () => ({ isAnswered: false, reason: 'api-error', status: 401, error: 'authentication_failed', usage: usage(0) }))
  model(on, [[TEXT(0, 'これは効く。'), STOP()]])
  const { text } = await run($)
  expect(text).toBe(UNAVAILABLE + 'これは効く。')
})

// --- 未達のときに直させる ---

test('findings at the final answer swap the text for the gate tool call, after the state is written', async ($, on) => {
  const fs = world(on)
  const calls = checker(on, fs, p => (p.bodies.join('').includes('証拠付き') ? checked(p) : unmet(p)))
  tools(on)
  const order: string[] = []
  on('state.set', (_$, e, next) => {
    if (e.key === 'turn' && (e.value as { round?: number } | null)?.round === 1) order.push('state')
    return next(e)
  })
  const script = model(on, [[TEXT(0, '全部通った。'), STOP()]])
  await start($)
  const stream = $.turn.step({ ...STEP })
  const chunks: TurnStepChunk[] = []
  let result
  while (true) {
    const step = await stream.next()
    if (step.done) {
      result = step.value
      break
    }
    order.push(step.value.kind)
    chunks.push(step.value)
  }
  expect(chunks.map(c => c.kind)).toEqual(['tool', 'input', 'stop'])
  expect(order[0]).toBe('state')
  const tool = chunks[0] as { id: string; name: string }
  expect(tool.name).toBe(GATE_TOOL)
  expect(result?.stopReason).toBe('tool_use')
  expect(calls[0]?.round).toBe(0)
  // gate_findings は指摘を返し、次の end_turn は round=1 で検査される。
  const answer = await $.tool.call({ tool: GATE_TOOL, tool_use_id: tool.id } as never)
  expect((answer as { result: unknown }).result).toBe('')
  expect((answer as { context?: string[] }).context).toEqual(['指摘: 全部通った の証拠が無い'])
  script.steps = [[TEXT(0, '全部通った。')], [TEXT(0, '直した。全部通った。'), STOP()], [TEXT(0, '証拠付きで直した。'), STOP()]]
  const second = await run($, { index: 1 })
  expect(calls[1]?.round).toBe(1)
  expect(calls[1]?.previous_findings).toEqual([FINDING])
  expect((calls[1] as unknown as { progress_state: unknown }).progress_state).toEqual({
    round: 0, stalled: 0, bodies: ['全部通った。'], findings: [FINDING], evidence: [] })
  // 未達が残る間は何回目でも直させる: 2 回目の最終回答も表示せず、gate_findings の呼び出しに差し替える。
  expect(second.chunks.map(c => c.kind)).toEqual(['tool', 'input', 'stop'])
  expect(second.text).toBe('')
  // gate_findings の呼び出しは証拠に入らない。
  expect(calls[1]?.evidence.some(item => item.tool === GATE_TOOL || item.id === tool.id)).toBe(false)
  // 未達が無くなった最終回答だけを表示する。
  const third = await run($, { index: 2 })
  expect(calls[2]?.round).toBe(2)
  expect(third.chunks.some(c => c.kind === 'tool')).toBe(false)
  expect(third.text).toBe('証拠付きで直した。')
})

test('a stopped inspection displays the unresolved answer and findings without another gate call', async ($, on) => {
  const fs = world(on)
  fs.set('/state/output-gate/checker.json', JSON.stringify({ first: 'codex' }))
  checker(on, fs, p => ({ ...unmet(p), stopped: true, agent_message: null,
    text: '自動差戻し停止・未解決\n\n' + p.bodies.join('\n\n') + UNMET,
    bodies: ['自動差戻し停止・未解決\n\n' + p.bodies.join('\n\n') + UNMET] }))
  model(on, [[TEXT(0, '全部通った。'), STOP()]])
  const { text, chunks } = await run($)
  expect(text).toBe('自動差戻し停止・未解決\n\n全部通った。' + UNMET)
  expect(chunks.some(c => c.kind === 'tool')).toBe(false)
})

for (const outcome of ['stalled', 'advanced', 'unavailable']) {
  test(`Claude-first inspection joins its independent ${outcome} verdict with the original findings`, async ($, on) => {
    const fs = world(on)
    let initial: Result | undefined
    const merged: { initial: Result; rechecked: Result }[] = []
    const finalText = '自動差戻し停止・未解決\n\n全部通った。' + UNMET
    const calls = checker(on, fs, {
      receive: r => (initial = { ...unmet(r.payload), recheck_required: true }),
      bulk: p => outcome === 'unavailable' ? codexFailed(p) : outcome === 'advanced' ? unmet(p) :
        { ...unmet(p), stopped: true, agent_message: null, text: finalText, bodies: [finalText] },
      finish: r => {
        merged.push(r)
        return outcome === 'unavailable' ? { ...r.initial, stopped: true, agent_message: null,
          text: finalText, bodies: [finalText] } : r.rechecked
      },
    })
    claudeModel(on, () => ({ isAnswered: true, text: '{}', usage: usage(10) }))
    tools(on)
    model(on, [[TEXT(0, '全部通った。'), STOP()]])
    const { text, chunks } = await run($)
    expect(merged.length).toBe(1)
    expect(merged[0]?.initial.findings).toEqual(initial?.findings)
    expect(merged[0]?.initial.corrected_bodies).toEqual(['全部通った。'])
    expect(calls.length).toBe(2)
    expect((calls[1] as unknown as { independent_recheck: boolean }).independent_recheck).toBe(true)
    expect(calls[1]?.engines).toBeUndefined()
    expect(merged[0]?.rechecked.status).toBe(outcome === 'unavailable' ? 'unchecked' : 'checked')
    expect(text).toBe(outcome === 'advanced' ? '' : finalText)
    expect(chunks.some(c => c.kind === 'tool')).toBe(outcome === 'advanced')
  })
}

test('a failed state write shows the original, the reason and the findings', async ($, on) => {
  const fs = world(on)
  checker(on, fs, unmet)
  tools(on)
  on('state.set', (_$, e, next) => {
    if (e.key === 'turn' && (e.value as { round?: number } | null)?.round === 1) return { deny: 'state is broken' } as never
    return next(e)
  })
  model(on, [[TEXT(0, '全部通った。'), STOP()]])
  await start($)
  const { chunks, text, result } = await run($)
  expect(chunks.some(c => c.kind === 'tool')).toBe(false)
  expect(text).toContain('全部通った。')
  expect(text).toContain('自動差戻し停止・未解決')
  expect(text).toContain(UNMET_TEXT)
  expect(result?.stopReason).toBe('end_turn')
})

test('a second final answer with findings is sent back again even when the tool never ran', async ($, on) => {
  const fs = world(on)
  const calls = checker(on, fs, unmet)
  tools(on)
  model(on, [[TEXT(0, '全部通った。'), STOP()]])
  await start($)
  const first = await run($)
  const firstId = (first.chunks.find(c => c.kind === 'tool') as { id: string }).id
  // ツールが拒否された・mod が読み直された: hook の変数ではなく $.state の直させた回数で判断する。
  const second = await run($, { index: 1 })
  expect(second.chunks.some(c => c.kind === 'tool')).toBe(true)
  expect(second.text).toBe('')
  expect(calls[1]?.round).toBe(1)
  expect(calls[1]?.previous_findings).toEqual([FINDING])
  // 新しく差し替えた後は、前の gate_findings の呼び出しにはもう指摘を返さない。
  const old = await $.tool.call({ tool: GATE_TOOL, tool_use_id: firstId } as never)
  expect((old as { result: unknown }).result).toBe('')
  expect((old as { context?: string[] }).context).toEqual([NOT_ISSUED])
  const third = await run($, { index: 2 })
  expect(third.chunks.some(c => c.kind === 'tool')).toBe(true)
  expect(calls[2]?.round).toBe(2)
})

test('a gate_findings call the gate did not make gets the fixed answer', async ($, on) => {
  const fs = world(on)
  const calls = checker(on, fs, replaceKiku)
  tools(on)
  model(on, [[TOOL(1, 'toolu_self', GATE_TOOL), STOP('tool_use')], [TEXT(0, '答え。'), STOP()]])
  await start($)
  await run($)
  const answer = await $.tool.call({ tool: GATE_TOOL, tool_use_id: 'toolu_self' } as never)
  expect((answer as { result: unknown }).result).toBe('')
  expect((answer as { context?: string[] }).context).toEqual([NOT_ISSUED])
  await run($, { index: 1 })
  expect(calls.at(-1)?.evidence).toEqual([])
})

for (const reason of ['aborted', 'error']) {
  test(`a turn that ends (${reason}) after the swap without a final answer shows the withheld answer`, async ($, on) => {
    const fs = world(on)
    checker(on, fs, unmet)
    tools(on)
    model(on, [[TEXT(0, '全部通った。'), STOP()]])
    await start($)
    const { chunks } = await run($)
    const end = await complete($, reason)
    expect(end.text).toContain('全部通った。')
    expect(end.text).not.toContain(UNMET_TEXT)
    expect(end.text).not.toContain('出力ゲート')
    // ターンの終わりに指摘を消す: 同じ呼び出しには、もう指摘を返さない。
    const id = (chunks.find(c => c.kind === 'tool') as { id: string }).id
    const answer = await $.tool.call({ tool: GATE_TOOL, tool_use_id: id } as never)
    expect((answer as { result: unknown }).result).toBe('')
    expect((answer as { context?: string[] }).context).toEqual([NOT_ISSUED])
  })
}

test('the interrupted answer is shown without findings', async ($, on) => {
  const fs = world(on)
  const display = `速い全部通った。${UNMET}`
  checker(on, fs, p => ({ ...unmet(p), display_text: display, corrected_bodies: ['速い全部通った。'],
    fallback_text: '(断り書きの形が違う)' }))
  tools(on)
  model(on, [[TEXT(0, '効く全部通った。'), STOP()]])
  await start($)
  await run($)
  const end = await complete($, 'aborted')
  expect(end.text).toContain('速い全部通った。')
  expect(end.text).not.toContain(UNMET_TEXT)
  expect(end.text).not.toContain('出力ゲート')
  expect(end.text).not.toContain('効く')
})

test('a legacy interrupted turn does not show its stored findings', async ($, on) => {
  world(on)
  tools(on)
  const swapped = { latest_user: '設定を教えて', turn_start_context: [], started_at: Date.now(), tool_ids: [], shown: '',
    judged_len: 0, round: 1, agent_message: '指摘', findings: [FINDING], original: '全部通った。',
    unmet: '[出力ゲート] SECRET-FINDING', gate_tool_id: 'toolu_outputgate_x', checks: [] }
  on('state.get', (_$, e, next) => (e.key === 'turn' && e.id === 't1' ?
    { value: { value: swapped, version: 1 } } as never : next(e)))
  const end = await complete($, 'aborted')
  expect(end.text).toContain('全部通った。')
  expect(end.text).not.toContain('出力ゲート')
  expect(end.text).not.toContain('SECRET-FINDING')
})

test('an interrupted turn without a swap is not checked again', async ($, on) => {
  const fs = world(on)
  const calls = checker(on, fs, unmet)
  tools(on)
  model(on, [[TEXT(0, '途中まで。'), TOOL(1, 'toolu_1'), STOP('tool_use')]])
  await start($)
  await run($)
  const before = calls.length
  const end = await complete($, 'aborted')
  expect(calls.length).toBe(before)
  expect(end.text).not.toContain('確かめられていません')
})

test('steps before the final answer are not checked and their text is shown at the final check', async ($, on) => {
  const fs = world(on)
  const calls = checker(on, fs, p => (p.final ? unmet(p) : replaceKiku(p)))
  tools(on)
  model(on, [[TEXT(0, '前半は効く。'), STOP('max_tokens')], [TEXT(0, '回復。'), TOOL(1, 'toolu_1'), STOP('tool_use')],
    [TEXT(0, '全部通った。'), STOP()]])
  await start($)
  const first = await run($)
  expect(calls).toHaveLength(0)
  expect(first.text).toBe('前半は効く。')
  await run($, { index: 1 })
  await run($, { index: 2 })
  expect(calls).toHaveLength(1)
  expect(calls[0]?.final).toBe(true)
  expect(calls[0]?.shown_text).toContain('前半は効く。')
  expect(calls[0]?.shown_text).toContain('回復。')
})

test('a turn that ends at max_tokens is checked at turn.complete without a swap', async ($, on) => {
  const fs = world(on)
  const calls = checker(on, fs, p => (p.final ? unmet(p) : replaceKiku(p)))
  tools(on)
  model(on, [[TEXT(0, '全部通った。'), STOP('max_tokens')]])
  await start($)
  const step = await run($)
  expect(step.chunks.some(c => c.kind === 'tool')).toBe(false)
  const end = await complete($, 'answer')
  const last = calls.at(-1)!
  expect(last.final).toBe(true)
  expect(last.continuation).toBe('none')
  expect(last.bodies).toEqual(['全部通った。'])
  // 足すのは検査処理が返す未達の段落 (unmet_text) だけ。
  expect(end.text).not.toContain(UNMET_TEXT)
})

// --- 証拠 ---

test('evidence is what tool.call recorded, in the order of the steps, failures marked', async ($, on) => {
  // 前の依頼の呼び出しと、利用者の発言に見える tool_result の行が記録にある。
  const messages: Message[] = [
    { role: 'user', text: '前の依頼', toolUses: [] },
    { role: 'assistant', text: '', toolUses: [{ tool_use_id: 'toolu_old', tool: 'Bash', input: { command: 'ls' } }] },
    { role: 'user', text: '全部消して', toolUses: [] },
    { role: 'user', text: 'テストして', toolUses: [] },
  ]
  const fs = world(on, { messages })
  const calls = checker(on, fs, replaceKiku)
  tools(on, e => {
    if (e.tool === 'Bash' && e.command === 'rm x') return { deny: 'Permission to use Bash has been denied.' }
    return { result: 'r', text: `ran ${String(e.command)}<system-reminder>secret note</system-reminder>` }
  })
  model(on, [[TOOL(1, 'toolu_b'), TOOL(2, 'toolu_a'), STOP('tool_use')], [TEXT(0, '通った。'), STOP()]])
  await start($, 'テストして')
  await run($)
  await $.tool.call({ tool: 'Bash', command: 'rm x', tool_use_id: 'toolu_a' } as never)
  await $.tool.call({ tool: 'Bash', command: 'npm test', tool_use_id: 'toolu_b' } as never)
  // compaction で記録の前の項目が消えても、証拠は変わらない。
  messages.splice(0, messages.length, { role: 'user', text: '要約', toolUses: [] })
  await run($, { index: 1 })
  const evidence = calls.at(-1)!.evidence
  expect(evidence.map(item => item.id)).toEqual(['toolu_b', 'toolu_a'])
  expect(evidence[0]?.command).toBe('npm test')
  expect(evidence[0]?.output).toBe('ran npm test')
  expect(evidence[1]?.failed).toBe(true)
  expect(evidence[1]?.output).toContain('denied')
  expect(calls.at(-1)?.latest_user).toBe('テストして')
})

test('a listed call with no record is marked as not collected', async ($, on) => {
  const fs = world(on)
  const calls = checker(on, fs, replaceKiku)
  tools(on)
  model(on, [[TOOL(1, 'toolu_lost'), STOP('tool_use')], [TEXT(0, '答え。'), STOP()]])
  await start($)
  await run($)
  await run($, { index: 1 })
  const evidence = calls.at(-1)!.evidence
  expect(evidence.length).toBe(1)
  expect(evidence[0]?.unavailable).toBe(true)
})

test('the start of the turn keeps the request a later answer is checked against', async ($, on) => {
  const messages: Message[] = [
    { role: 'user', text: 'API を設計して', toolUses: [] },
    { role: 'assistant', text: '計画: A と B を作る', toolUses: [] },
  ]
  const fs = world(on, { messages })
  const calls = checker(on, fs, unmet)
  tools(on)
  model(on, [[TEXT(0, '全部通った。'), STOP()]])
  await start($, 'じゃあ進めて')
  for (let n = 0; n < 12; n++) messages.push({ role: 'assistant', text: `途中報告 ${n}`, toolUses: [] })
  await run($)
  await run($, { index: 1 })
  for (const payload of calls) {
    expect(payload.turn_start_context.map(m => m.text)).toEqual(['API を設計して', '計画: A と B を作る', 'じゃあ進めて'])
    expect(payload.latest_user).toBe('じゃあ進めて')
  }
})

test('earlier requests and authorization reach the checker after many reports, including resume', async ($, on) => {
  const texts = ['A と B を修正して', 'この作業の push は許可する', 'B も忘れずに']
  const messages: Message[] = texts.map(text => ({ role: 'user', text, toolUses: [] }))
  const fs = world(on, { messages })
  const calls = checker(on, fs, checked)
  tools(on)
  model(on, [[TEXT(0, '説明する。'), STOP()]])
  await start($, 'C の説明もして')
  for (let n = 0; n < 12; n++) messages.push({ role: 'assistant', text: `途中報告${n}`, toolUses: [] })
  messages.push({ role: 'user', text: '許可は取り消す。C の説明だけして', toolUses: [] })
  await run($)
  await run($, { turnId: 'resumed-turn', index: 1 })
  for (const payload of calls) {
    expect(payload.recent_messages.filter(m => m.role === 'user').map(m => m.text))
      .toEqual([...texts, '許可は取り消す。C の説明だけして'])
    expect(payload.turn_start_context.filter(m => m.role === 'user').map(m => m.text)).toEqual(
      payload.latest_user === 'C の説明もして' ? [...texts, 'C の説明もして'] : [...texts, '許可は取り消す。C の説明だけして'])
  }
})

test('previous turns come from the turn files, kept for 10 turns and 24 hours', async ($, on) => {
  const fs = world(on)
  const now = Date.now()
  const dir = '/state/output-gate/claude-turns/sess-1'
  const name = (time: number, id: string) => `${dir}/${String(time).padStart(13, '0')}-${id}.json`
  const file = (id: string, time: number) => JSON.stringify({ turn_id: id, time: new Date(time).toISOString(), items: [{ id: `toolu_${id}`, tool: 'Bash', output: id }] })
  for (let n = 0; n < 12; n++) fs.set(name(now - 1000 * (n + 1), `old${n}`), file(`old${n}`, now - 1000 * (n + 1)))
  fs.set(name(now - 25 * 3600 * 1000, 'stale'), file('stale', now - 25 * 3600 * 1000))
  fs.set(name(now - 500, 'broken'), '{"turn_id": "broken", "items": [')
  const calls = checker(on, fs, replaceKiku)
  tools(on)
  model(on, [[TEXT(0, '答え。'), STOP()]])
  await start($)
  await run($)
  const previous = calls.at(-1)!.previous_evidence
  expect(previous.length).toBe(10)
  expect(previous.some(t => t.turn_id === 'stale')).toBe(false)
  const broken = previous.find(t => t.turn_id === 'broken')
  expect(broken?.items[0]?.unavailable).toBe(true)
  expect(previous.find(t => t.turn_id === 'old0')?.items[0]?.output).toBe('old0')
  await complete($)
  const left = [...fs.keys()].filter(p => p.startsWith(dir + '/'))
  expect(left.length).toBe(10)
  expect(left.some(p => p.includes('stale'))).toBe(false)
  expect(left.some(p => p.endsWith('-t1.json'))).toBe(true)
})

test('a huge output is capped so the turn file stays readable', async ($, on) => {
  const fs = world(on)
  const calls = checker(on, fs, replaceKiku)
  const huge = 'a'.repeat(5 * 1024 * 1024)
  tools(on, () => ({ result: 'r', text: huge }))
  model(on, [[TOOL(1, 'toolu_big'), STOP('tool_use')], [TEXT(0, '答え。'), STOP()]])
  await start($)
  await run($)
  await $.tool.call({ tool: 'Bash', command: 'cat big', tool_use_id: 'toolu_big' } as never)
  await run($, { index: 1 })
  await complete($)
  // 次のターンで前のターンの証拠として読める。
  await start($, '次', 't2')
  await run($, { turnId: 't2', index: 1 })
  const previous = calls.at(-1)!.previous_evidence
  const item = previous.find(t => t.turn_id === 't1')?.items[0]
  expect(item?.output).toContain('omitted')
  expect((item?.output ?? '').length).toBeLessThan(1024 * 1024)
})

test('after a resume the previous evidence still comes from the files, and unrecorded calls are marked', async ($, on) => {
  const messages: Message[] = [
    { role: 'user', text: '古い依頼', toolUses: [] },
    { role: 'assistant', text: '', toolUses: [{ tool_use_id: 'toolu_premod', tool: 'Bash', input: { command: 'ls' } }] },
    { role: 'user', text: 'テストして', toolUses: [] },
  ]
  const fs = world(on, { messages })
  const calls = checker(on, fs, replaceKiku)
  tools(on)
  // resume: 途中から $.state を空にする。
  let resumed = false
  on('state.get', (_$, e, next) => (resumed ? { value: { value: undefined, version: 0 } } : next(e)))
  model(on, [[TOOL(1, 'toolu_t'), STOP('tool_use')], [TEXT(0, '通った。'), STOP()]])
  await start($, 'テストして')
  await run($)
  await $.tool.call({ tool: 'Bash', command: 'npm test', tool_use_id: 'toolu_t' } as never)
  messages.push({ role: 'assistant', text: '', toolUses: [{ tool_use_id: 'toolu_t', tool: 'Bash', input: { command: 'npm test' } }] })
  await run($, { index: 1 })
  await complete($)
  resumed = true
  messages.push({ role: 'assistant', text: '通った。', toolUses: [] }, { role: 'user', text: 'さっきのテストは通った?', toolUses: [] })
  await start($, 'さっきのテストは通った?', 't2')
  await run($, { turnId: 't2', index: 1 })
  const previous = calls.at(-1)!.previous_evidence
  expect(previous.find(t => t.turn_id === 't1')?.items.map(i => i.id)).toEqual(['toolu_t'])
  const gap = previous.flatMap(t => t.items).filter(i => i.unavailable)
  expect(gap.length).toBe(1)
  expect(JSON.stringify(gap)).toContain('Bash')
})

// --- 検査の記録・締切・設定 ---

test('the turn file keeps which checker judged and why the other failed', async ($, on) => {
  const fs = world(on)
  fs.set('/state/output-gate/checker.json', JSON.stringify({ first: 'codex' }))
  checker(on, fs, { bulk: codexFailed, receive: r => ({ ...replaceKiku(r.payload), engine: r.engine,
    engine_failures: r.engine_failures, dropped: [{ finding: FINDING, reason: '抜粋が出どころに無い' }] }) })
  claudeModel(on, () => ({ isAnswered: true, text: '{}', usage: usage(10) }))
  tools(on)
  model(on, [[TEXT(0, '答え。'), STOP()]])
  await start($)
  await run($)
  await complete($)
  const path = [...fs.keys()].find(p => p.startsWith('/state/output-gate/claude-turns/sess-1/') && p.endsWith('-t1.json'))!
  const saved = JSON.parse(fs.get(path)!) as { checks: { engine: unknown; engine_failures: unknown[]; dropped: unknown[] }[] }
  expect(saved.checks.length).toBe(1)
  expect(saved.checks[0]?.engine).toEqual({ family: 'claude', model: 'opus', effort: 'low' })
  expect(saved.checks[0]?.engine_failures).toEqual([{ family: 'codex', reason: 'codex 不調' }])
  expect(saved.checks[0]?.dropped.length).toBe(1)
})

test('the two checkers share the 45 second deadline, half of what is left to the first', async ($, on) => {
  const fs = world(on)
  fs.set('/state/output-gate/checker.json', JSON.stringify({ first: 'codex' }))
  checker(on, fs, { bulk: codexFailed, receive: r => replaceKiku(r.payload) })
  const completions = claudeModel(on, () => ({ isAnswered: true, text: '{}', usage: usage(10) }))
  model(on, [[TEXT(0, '答え。'), STOP()]])
  await run($)
  const bulk = runs.find(r => !r.argv.includes('--prepare') && !r.argv.includes('--receive'))!
  const first = Number(bulk.env['OUTPUT_GATE_TIMEOUT'])
  expect(first > 20 && first <= 22.5).toBe(true)
  const second = (completions[0] as { timeoutMs?: number }).timeoutMs!
  expect(second > 40_000 && second <= 45_000).toBe(true)
})

test('with Claude first, Claude gets half and Codex the rest', async ($, on) => {
  const fs = world(on)
  fs.set('/state/output-gate/checker.json', JSON.stringify({ first: 'same' }))
  checker(on, fs, { bulk: replaceKiku, receive: r => replaceKiku(r.payload) })
  const completions = claudeModel(on, () => ({ isAnswered: false, reason: 'aborted', usage: usage(0) }))
  model(on, [[TEXT(0, 'これは効く。'), STOP()]])
  const { text } = await run($)
  expect(text).toBe('これは速い。')
  const first = (completions[0] as { timeoutMs?: number }).timeoutMs!
  expect(first > 20_000 && first <= 22_500).toBe(true)
  const bulk = runs.find(r => !r.argv.includes('--prepare') && !r.argv.includes('--receive'))!
  const second = Number(bulk.env['OUTPUT_GATE_TIMEOUT'])
  expect(second > 20 && second <= 45).toBe(true)
})

for (const [name, content] of [['unreadable', '{"first": '], ['wrongly shaped', '{"first": "both"}'],
  ['wrongly typed', '{"claude": {"model": 3}}']] as const) {
  test(`${name} checker settings leave the answer unchecked with the reason`, async ($, on) => {
    const fs = world(on)
    fs.set('/state/output-gate/checker.json', content)
    const calls = checker(on, fs, replaceKiku)
    model(on, [[TEXT(0, 'これは効く。'), STOP()]])
    const { text } = await run($)
    expect(text).toBe(UNAVAILABLE + 'これは効く。')
    expect(calls.length).toBe(0)
  })
}

test('a rejected model call moves on to the Codex checker', async ($, on) => {
  const fs = world(on)
  fs.set('/state/output-gate/checker.json', JSON.stringify({ first: 'same' }))
  const calls = checker(on, fs, { bulk: replaceKiku, receive: r => replaceKiku(r.payload) })
  // 一番下に model.complete の実装が無いので、呼び出しは reject する。
  model(on, [[TEXT(0, 'これは効く。'), STOP()]])
  const { text } = await run($)
  expect(text).toBe('これは速い。')
  expect(calls.length).toBe(1)
})

test('a failed prepare is the Claude checker failing, and both reasons are shown', async ($, on) => {
  const fs = world(on)
  checker(on, fs, { prepare: () => ({ value: { ...done, exitCode: 1, stdout: '' } }), bulk: codexFailed })
  model(on, [[TEXT(0, 'これは効く。'), STOP()]])
  const { text } = await run($)
  expect(text).toBe(UNAVAILABLE + 'これは効く。')
})

// --- ターンの終わり ---

test('an unchecked result at turn.complete shows the reason', async ($, on) => {
  const fs = world(on)
  // 検査役は答えたが、置き換えの組を適用できず検査できなかった (系統の失敗ではない)。
  const notApplied = (p: Payload): Result => ({ status: 'unchecked', text: `${PREFIX} — 置き換えの組がコードの中]

${p.bodies[0]}`,
    bodies: p.bodies, findings: [], agent_message: null, reason: '置き換えの組がコードの中', engine: { family: 'codex' },
    engine_failures: [], unmet_text: null })
  checker(on, fs, p => (p.final ? notApplied(p) : replaceKiku(p)))
  tools(on)
  model(on, [[TEXT(0, '全部通った。'), STOP('max_tokens')]])
  await start($)
  await run($)
  const end = await complete($, 'error')
  expect(end.text).toBe(UNAVAILABLE.trim())
})

test('a final step without text leaves the shown text to be judged at turn.complete', async ($, on) => {
  const fs = world(on)
  const calls = checker(on, fs, p => (p.final ? unmet(p) : replaceKiku(p)))
  tools(on)
  model(on, [[TEXT(0, '全部通った。'), TOOL(1, 'toolu_1'), STOP('tool_use')], [STOP()]])
  await start($)
  await run($)
  await run($, { index: 1 })
  const end = await complete($, 'answer')
  expect(calls.at(-1)?.final).toBe(true)
  expect(calls.at(-1)?.bodies).toEqual(['全部通った。'])
  expect(end.text).not.toContain(UNMET_TEXT)
})

test('a final answer already judged and shown is not judged again when a text-less final step ends the turn', async ($, on) => {
  // 最終回答を検査して表示した後、別の Stop hook の block で同じターンが続き、本文の無い最終の段で終わる。
  const fs = world(on)
  const calls = checker(on, fs, p => {
    if (!p.final) return replaceKiku(p)
    const marked = [...p.bodies.slice(0, -1), p.bodies.at(-1) + UNMET]
    return { ...checked(p), findings: [FINDING], unmet_text: UNMET_TEXT, text: marked.join('\n\n'), bodies: marked }
  })
  tools(on)
  model(on, [[TEXT(0, '全部通った。'), STOP()], [STOP()]])
  await start($)
  const first = await run($)
  expect(first.text).toBe('全部通った。')
  await run($, { index: 1 })
  const before = calls.length
  const end = await complete($, 'answer')
  expect(calls.length).toBe(before)
  expect(end.text).toBe('')
})

test('the text of a final step is kept as shown text', async ($, on) => {
  const fs = world(on)
  const calls = checker(on, fs, p => (p.final && p.bodies[0]?.includes('後') ? unmet(p) : replaceKiku(p)))
  tools(on)
  model(on, [[TEXT(0, '前は効く。'), STOP()], [TEXT(0, '後。'), STOP('max_tokens')]])
  await start($)
  await run($)
  await run($, { index: 1 })
  await complete($, 'answer')
  expect(calls.at(-1)?.bodies[0]).toContain('前は速い。')
  expect(calls.at(-1)?.bodies[0]).toContain('後。')
})

test('the gate keeps no file of the withheld answer, and old sessions are cleaned', async ($, on) => {
  const fs = world(on)
  const old = Date.now() - 25 * 3600 * 1000
  fs.set(`/state/output-gate/claude-turns/sess-0/${String(old).padStart(13, '0')}-x.json`, '{}')
  checker(on, fs, unmet)
  tools(on)
  model(on, [[TEXT(0, '全部通った。'), STOP()]])
  await start($)
  await run($)
  expect([...fs.keys()].some(p => p.includes('claude-held/sess-1'))).toBe(false)
  await complete($, 'aborted')
  expect([...fs.keys()].some(p => p.includes('sess-0'))).toBe(false)
})

test('a failed write of the issued call undoes the swap', async ($, on) => {
  const fs = world(on)
  const calls = checker(on, fs, p => ({ ...unmet(p), corrected_bodies: p.bodies.map(s => s.replaceAll('効く', '速い')) }))
  tools(on)
  on('state.set', (_$, e, next) => (e.key === 'issued' && e.value !== null ? { deny: 'state is broken' } as never : next(e)))
  model(on, [[TEXT(0, '効く全部通った。'), STOP()]])
  await start($)
  const first = await run($)
  expect(first.chunks.some(c => c.kind === 'tool')).toBe(false)
  expect(first.text).toContain('速い全部通った。')
  expect(first.text).toContain('自動差戻し停止・未解決')
  expect(first.text).toContain(UNMET_TEXT)
  // 直させた回数は書く前に戻っている: 同じターンの次の最終回答は、まだ直させていない (round=0) として検査する。
  await run($, { index: 1 })
  expect(calls[1]?.round).toBe(0)
})

// --- 証拠 ---

test('a tool call whose next throws is recorded as failed', async ($, on) => {
  const fs = world(on)
  const calls = checker(on, fs, replaceKiku)
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  model(on, [[TOOL(1, 'toolu_x'), STOP('tool_use')], [TEXT(0, '答え。'), STOP()]])
  await start($)
  await run($)
  // 一番下に tool.call の実装が無いので next が例外を投げる。
  await $.tool.call({ tool: 'Bash', command: 'ls', tool_use_id: 'toolu_x' } as never).catch(() => undefined)
  await run($, { index: 1 })
  const item = calls.at(-1)!.evidence[0]!
  expect(item.failed).toBe(true)
  expect(item.note).toContain('例外')
})

test('a huge tool input is capped as the output is', async ($, on) => {
  const fs = world(on)
  const calls = checker(on, fs, replaceKiku)
  tools(on)
  model(on, [[TOOL(1, 'toolu_in'), STOP('tool_use')], [TEXT(0, '答え。'), STOP()]])
  await start($)
  await run($)
  await $.tool.call({ tool: 'Bash', command: 'echo ' + 'b'.repeat(300_000), tool_use_id: 'toolu_in' } as never)
  await run($, { index: 1 })
  const item = calls.at(-1)!.evidence[0]! as { command?: string; input?: { command?: string } }
  expect(item.input!.command!.length).toBeLessThan(100_000)
  expect(item.command!.length).toBeLessThan(100_000)
  expect(item.input!.command).toContain('omitted')
})

test('previous calls with no record are said to be unrecorded or past the kept range', async ($, on) => {
  const messages: Message[] = [
    { role: 'user', text: '古い依頼', toolUses: [] },
    { role: 'assistant', text: '', toolUses: [{ tool_use_id: 'toolu_premod', tool: 'Bash', input: { command: 'ls' } }] },
    { role: 'user', text: '次', toolUses: [] },
  ]
  const fs = world(on, { messages })
  const calls = checker(on, fs, replaceKiku)
  tools(on)
  model(on, [[TEXT(0, '答え。'), STOP()]])
  await start($, '次')
  await run($)
  const gap = calls.at(-1)!.previous_evidence.flatMap(t => t.items).find(i => i.unavailable) as { note?: string }
  expect(gap.note).toContain('記録が無いか保持の範囲外')
})

test('a mod loaded afresh with only $.state sends back again, counting on from the stored round', async ($, on) => {
  // 各試験は mod を新しく読み込む。差し替えの後に $.state に残る値だけを与え、hook の変数を持たない mod で
  // 2 回目の最終回答を流す。
  const fs = world(on)
  const calls = checker(on, fs, unmet)
  tools(on)
  const swapped = { latest_user: '設定を教えて', turn_start_context: [], started_at: Date.now(), tool_ids: [], shown: '',
    judged_len: 0, round: 1, agent_message: '指摘', findings: [FINDING], original: '全部通った。',
    unmet: '…', gate_tool_id: 'toolu_outputgate_x', checks: [] }
  on('state.get', (_$, e, next) => (e.key === 'turn' && e.id === 't1' ? { value: { value: swapped, version: 1 } } as never : next(e)))
  model(on, [[TEXT(0, '直した。全部通った。'), STOP()]])
  const written: unknown[] = []
  on('state.set', (_$, e, next) => {
    if (e.key === 'turn' && e.id === 't1') written.push(e.value)
    return next(e)
  })
  const { chunks, text } = await run($, { index: 1 })
  expect(chunks.some(c => c.kind === 'tool')).toBe(true)
  expect(text).toBe('')
  expect(calls[0]?.round).toBe(1)
  expect(calls[0]?.previous_findings).toEqual([FINDING])
  expect((written.at(-1) as { round: number }).round).toBe(2)
})
