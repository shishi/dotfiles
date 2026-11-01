import { expect, mock, test } from 'claude-code/testing'
import type { On, TurnStepChunk } from 'claude-code'

const STEP = { turnId: 't1', index: 0, model: 'm', messageCount: 2 } as const
const PREFIX = '[出力ゲート: 検査できませんでした'

type Payload = { cli: string; latest_user: string; conversation: unknown[]; draft: string }

// 一番下のモデルの代わり: 与えた断片を流し、応答を返す。
function model(on: On, chunks: TurnStepChunk[]) {
  on('turn.step', async function* (_$, e) {
    for (const chunk of chunks) yield chunk
    const answer = chunks.map(c => (c.kind === 'text' ? c.text : '')).join('')
    return { turnId: e.turnId, index: e.index, answer, toolUses: [], stopReason: 'end_turn' as const, usage: null }
  })
}

// 検査処理の代わり: Python の確認には成功で答え、検査には answer の結果を返す。
function checker(on: On, answer: (p: Payload) => { exitCode: number; stdout: string }, calls: Payload[] = []) {
  on('process.run', (_$, e) => {
    const done = { stderr: '', isStdoutTruncated: false, isStderrTruncated: false }
    if (e.init?.stdin === undefined) return { value: { ...done, exitCode: 0, stdout: '' } }
    const payload = JSON.parse(e.init.stdin) as Payload
    calls.push(payload)
    return { value: { ...done, ...answer(payload) } }
  })
  return calls
}

const replaceKiku = (p: Payload) => ({
  exitCode: 0,
  stdout: JSON.stringify({ status: 'checked', text: p.draft.replaceAll('効く', '速い'), reason: null, applied: 1 }),
})

// このマシンで出力ゲートを有効にした状態 (状態ディレクトリの claude-enabled を読める)。
function world(on: On, env: Record<string, string> = {}, enabled = true) {
  mock.env(on, { HOME: '/home/u', ...env })
  on('session.messages', () => ({ value: [{ role: 'user' as const, text: '設定を教えて', toolUses: [] }] }))
  on('fs.read', (_$, e) => {
    if (enabled && String(e.path).replaceAll('\\', '/').endsWith('/output-gate/claude-enabled')) return { value: '' }
    throw new Error('no such file')
  })
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

const TEXT = (index: number, text: string): TurnStepChunk => ({ kind: 'text', index, text })
const STOP: TurnStepChunk = { kind: 'stop', stopReason: 'end_turn', usage: null }

test('the answer is shown only after the check, corrected', async ($, on) => {
  world(on)
  const calls = checker(on, replaceKiku)
  model(on, [TEXT(0, 'これは'), TEXT(0, '効く。'), STOP])
  const { text } = await run($)
  expect(text).toBe('これは速い。')
  expect(calls.length).toBe(1)
  expect(calls[0].draft).toBe('これは効く。')
  expect(calls[0].cli).toBe('claude')
  expect(calls[0].latest_user).toBe('設定を教えて')
})

test('a failed check shows the original with the reason', async ($, on) => {
  world(on)
  checker(on, () => ({ exitCode: 1, stdout: '' }))
  model(on, [TEXT(0, 'これは効く。'), STOP])
  const { text } = await run($)
  expect(text.startsWith(PREFIX)).toBe(true)
  expect(text.endsWith('これは効く。')).toBe(true)
})

test('an unchecked result without a reason gets one', async ($, on) => {
  world(on)
  checker(on, p => ({ exitCode: 0, stdout: JSON.stringify({ status: 'unchecked', text: p.draft }) }))
  model(on, [TEXT(0, 'これは効く。'), STOP])
  const { text } = await run($)
  expect(text.startsWith(PREFIX)).toBe(true)
  expect(text.endsWith('これは効く。')).toBe(true)
})

test('text resent after a retry marker is checked as its own run', async ($, on) => {
  // 本文が流れ始めた後の再試行では、同じ index の本文がもう一度届く。続いて届いた区間ごとに検査して元の位置に出す。
  // 再試行の印 (engine の断片) はエンジンだけが作れるため、本文以外の断片として推論の断片で代わりに挟む。
  world(on)
  const calls = checker(on, replaceKiku)
  const retry: TurnStepChunk = { kind: 'thinking', index: 1, text: '再試行' }
  model(on, [TEXT(0, 'これは'), TEXT(0, '効く。'), retry, TEXT(0, 'これは効く。'), STOP])
  const { chunks } = await run($)
  expect(chunks).toEqual([TEXT(0, 'これは速い。'), retry, TEXT(0, 'これは速い。'), STOP])
  expect(calls.length).toBe(2)
})

test('the answer handed to hooks above follows the attempt the engine kept', async ($, on) => {
  // 再試行の前に届いた本文はエンジンの answer に含まれない。末尾から何個かの区間をつないだものが answer と
  // 完全に一致したとき、answer はその区間の訂正版になる。
  world(on)
  checker(on, replaceKiku)
  on('turn.step', async function* (_$, e) {
    yield TEXT(0, '捨てる本文は効く。')
    yield TEXT(2, '捨てる二つ目。')
    yield { kind: 'thinking', index: 1, text: '再試行' }
    yield TEXT(0, 'これは効く。')
    yield STOP
    return { turnId: e.turnId, index: e.index, answer: 'これは効く。', toolUses: [], stopReason: 'end_turn' as const, usage: null }
  })
  const { result } = await run($)
  expect(result.answer).toBe('これは速い。')
})

test('the answer is corrected when the retried text starts like the abandoned text', async ($, on) => {
  world(on)
  checker(on, replaceKiku)
  on('turn.step', async function* (_$, e) {
    yield TEXT(0, 'これは')
    yield { kind: 'thinking', index: 1, text: '再試行' }
    yield TEXT(0, 'これは効く。')
    yield STOP
    return { turnId: e.turnId, index: e.index, answer: 'これは効く。', toolUses: [], stopReason: 'end_turn' as const, usage: null }
  })
  const { result } = await run($)
  expect(result.answer).toBe('これは速い。')
})

test('a correction of abandoned text is not applied inside the kept text', async ($, on) => {
  // 捨てた区間の文字列が、採用した本文の中 (コードブロックなど) に現れても置き換えない。
  world(on)
  // 検査処理はコードの中を変えないので、地の文の foo だけを bar にする。
  checker(on, p => ({ exitCode: 0, stdout: JSON.stringify({ status: 'checked', text: p.draft === 'foo' ? 'bar' : p.draft, reason: null, applied: 1 }) }))
  const kept = '```' + String.fromCharCode(10) + 'foo' + String.fromCharCode(10) + '```'
  on('turn.step', async function* (_$, e) {
    yield TEXT(0, 'foo')
    yield { kind: 'thinking', index: 1, text: '再試行' }
    yield TEXT(0, kept)
    yield STOP
    return { turnId: e.turnId, index: e.index, answer: kept, toolUses: [], stopReason: 'end_turn' as const, usage: null }
  })
  const { result } = await run($)
  expect(result.answer).toBe(kept)
})

test('the answer is empty when the kept attempt has no text', async ($, on) => {
  world(on)
  checker(on, replaceKiku)
  on('turn.step', async function* (_$, e) {
    yield TEXT(0, '捨てる本文は効く。')
    yield { kind: 'thinking', index: 1, text: '再試行' }
    yield STOP
    return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn' as const, usage: null }
  })
  const { result } = await run($)
  expect(result.answer).toBe('')
})

test('a machine where the gate is not enabled is not checked', async ($, on) => {
  world(on, {}, false)
  const calls = checker(on, replaceKiku)
  model(on, [TEXT(0, 'これは効く。'), STOP])
  const { text } = await run($)
  expect(text).toBe('これは効く。')
  expect(calls.length).toBe(0)
})

test('steps of a subagent are not checked', async ($, on) => {
  world(on)
  const calls = checker(on, replaceKiku)
  model(on, [TEXT(0, 'これは効く。'), STOP])
  const { text } = await run($, { agentId: 'a1' })
  expect(text).toBe('これは効く。')
  expect(calls.length).toBe(0)
})

test('a delegated session is not checked', async ($, on) => {
  world(on, { AGENT_DELEGATED_SESSION: '1' })
  const calls = checker(on, replaceKiku)
  model(on, [TEXT(0, 'これは効く。'), STOP])
  const { text } = await run($)
  expect(text).toBe('これは効く。')
  expect(calls.length).toBe(0)
})

test('chunks keep their order and tool calls are not rewritten', async ($, on) => {
  world(on)
  checker(on, replaceKiku)
  const tool: TurnStepChunk = { kind: 'tool', index: 1, id: 'toolu_1', name: 'Bash' }
  const input: TurnStepChunk = { kind: 'input', index: 1, json: '{"command":"echo 効く"}' }
  model(on, [{ kind: 'thinking', index: 0, text: '考える' }, TEXT(0, 'これは効く。'), tool, input, STOP])
  const { chunks } = await run($)
  expect(chunks.map(c => c.kind)).toEqual(['thinking', 'text', 'tool', 'input', 'stop'])
  expect(chunks[2]).toEqual(tool)
  expect(chunks[3]).toEqual(input)
})

test('each text block is checked on its own', async ($, on) => {
  world(on)
  const calls = checker(on, replaceKiku)
  model(on, [TEXT(0, '前は効く。'), TEXT(2, '後も効く。'), STOP])
  const { chunks } = await run($)
  expect(chunks.filter(c => c.kind === 'text')).toEqual([TEXT(0, '前は速い。'), TEXT(2, '後も速い。')])
  expect(calls.map(c => c.draft).sort()).toEqual(['前は効く。', '後も効く。'].sort())
})

test('the spinner says the answer is being checked while it is held', async ($, on) => {
  world(on)
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    const props = e.props as { word: string; suffix: string }
    return <Text>{`${props.word}${props.suffix}`}</Text>
  })
  let seen = ''
  on('process.run', async (_$, e) => {
    const done = { stderr: '', isStdoutTruncated: false, isStderrTruncated: false }
    if (e.init?.stdin === undefined) return { value: { ...done, exitCode: 0, stdout: '' } }
    const ui = await $.ui.mount({
      plugin: 'output-gate', surface: 'terminal', component: 'Spinner', requestId: 'main',
      props: { word: 'Working', message: null, suffix: '…', mode: 'responding' },
    })
    seen = (await ui.find({ type: 'Text' }))?.text ?? ''
    await ui.unmount()
    return { value: { ...done, ...replaceKiku(JSON.parse(e.init.stdin) as Payload) } }
  })
  model(on, [TEXT(0, 'これは効く。'), STOP])
  await run($)
  expect(seen).toContain('出力ゲート')
  const ui = await $.ui.mount({
    plugin: 'output-gate', surface: 'terminal', component: 'Spinner', requestId: 'main',
    props: { word: 'Working', message: null, suffix: '…', mode: 'responding' },
  })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('Working…')
  await ui.unmount()
})

test('the session is marked so that the display hook leaves it to the mod', async ($, on) => {
  world(on, { XDG_STATE_HOME: '/state' })
  checker(on, replaceKiku)
  on('session.id', () => ({ value: 'sess-1' }))
  const writes: string[] = []
  const texts: string[] = []
  on('fs.write', (_$, e) => {
    writes.push(e.path)
    texts.push(e.text)
    return { value: undefined }
  })
  model(on, [TEXT(0, 'これは効く。'), STOP])
  await run($)
  // 区切り文字とドライブ名は OS ごとに付け直されるので、末尾の並びで確かめる。
  // 印はステップの開始時と、検査した回答を流す直前に書き直す。
  expect(writes.length).toBe(2)
  expect(texts).toEqual(['t1', 't1'])   // 印には今のターンの識別子を書く
  expect(writes.every(w => w.replaceAll('\\', '/').endsWith('/state/output-gate/claude-mod/sess-1'))).toBe(true)
})

test('a checker call that is cut off shows the original with the reason', async ($, on) => {
  // $.process.run が時間切れなどで reject しても、ステップを失敗させずに原文と理由を流す。
  // 実際に 10 秒を超えて待つ場合は、テストの道具の hook にも時間制限があるため、実機の受入で確かめる。
  world(on)
  on('process.run', (_$, e) => {
    const done = { stderr: '', isStdoutTruncated: false, isStderrTruncated: false }
    if (e.init?.stdin === undefined) return { value: { ...done, exitCode: 0, stdout: '' } }
    throw new Error('timed out')
  })
  model(on, [TEXT(0, 'これは効く。'), STOP])
  const { text } = await run($)
  expect(text.startsWith(PREFIX)).toBe(true)
  expect(text.endsWith('これは効く。')).toBe(true)
})

test('a failure of the hook itself shows the original with the reason', async ($, on) => {
  on('env.get', () => {
    throw new Error('env is broken')
  })
  checker(on, replaceKiku)
  model(on, [TEXT(0, 'これは効く。'), STOP])
  const { text } = await run($)
  expect(text.startsWith(PREFIX)).toBe(true)
  expect(text.endsWith('これは効く。')).toBe(true)
})
