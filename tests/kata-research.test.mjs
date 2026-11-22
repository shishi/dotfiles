import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { createCodexResearchSession } from '../agent-shared/bin/kata-codex-session.mjs';
import { guardedResponse } from '../agent-shared/claude-mods/kata-research/hooks/response.mjs';

import {
  ObsoleteRequest,
  ResearchControl,
  ResearchRefused,
  ResearchRequired,
  ResearchUnavailable,
} from '../agent-shared/claude-mods/kata-research/hooks/control.mjs';

async function setupCodex(t, judge, readThread, workspaceReads = false) {
  const params = { threadId: 'fixture-thread', turnId: 'fixture-turn' };
  const sent = [];
  const visible = [];
  let reads = 0;
  let state = 'old';
  const session = createCodexResearchSession({
    sendToServer: (message) => {
      sent.push(message);
      if (readThread && message.method === 'thread/read') {
        queueMicrotask(() => session.fromServer({ id: message.id, result: { thread: readThread(message.params.threadId) } }));
      }
      if (workspaceReads && message.method === 'command/exec') {
        const [command, ...args] = message.params.command;
        execFile(command, args, { encoding: 'utf8' }, (error, stdout) => {
          session.fromServer({ id: message.id, result: { stdout, exitCode: error ? 1 : 0 } });
        });
      }
    },
    sendToTerminal: (message) => visible.push(message),
  }, {
    kataPath: '/tmp/example/SKILL.md',
    judge,
    readEvidence: workspaceReads ? undefined : async (_, path) => {
      const reread = async () => {
        if (path === 'reference') return 'manual';
        reads++;
        return state;
      };
      return { key: path, value: await reread(), reread };
    },
  });
  t.after(() => session.close());
  const invoke = (id, tool, input) => session.fromServer({
    id, method: 'item/tool/call', params: { ...params, namespace: 'kata_research', tool, arguments: input },
  });

  await session.fromTerminal({ id: 1, method: 'thread/start', params: { cwd: '/tmp' } });
  await session.fromServer({ id: 1, result: {
    thread: { id: params.threadId, cwd: '/tmp' },
    activePermissionProfile: { id: ':workspace' },
  } });
  await session.fromTerminal({ id: 2, method: 'turn/start', params: {
    threadId: params.threadId, input: [{ type: 'text', text: 'Check a local setting' }],
  } });
  await session.fromServer({ method: 'turn/started', params: { ...params, turn: { id: params.turnId } } });
  async function completeResearch(continueWork = false) {
    await invoke(3, 'research_gate', { action: 'research' });
    await invoke(4, 'read_research_file', { path: 'reference' });
    await invoke(5, 'read_research_file', { path: 'state' });
    await invoke(6, 'research_gate', {
      action: 'complete', sources: ['reference'], observations: ['state'],
      comparison: 'Compared manual and setting', continueWork,
    });
    assert.equal(sent.findLast(({ id }) => id === 6)?.result.success, true);
  }

  return {
    session, params, invoke, sent, visible, completeResearch,
    reads: () => reads,
    changePremise: () => { state = 'new'; },
  };
}

test('Codex acknowledges revalidated evidence once and still checks it at publication', async (t) => {
  const { session, params, visible, completeResearch, reads, changePremise } = await setupCodex(t);
  await completeResearch();
  assert.equal(reads(), 2);
  const item = { id: 'answer', type: 'agentMessage', text: 'The old setting' };
  await session.fromServer({ method: 'item/started', params: { ...params, item } });
  changePremise();
  await session.fromServer({ method: 'item/completed', params: { ...params, item } });
  assert.equal(reads(), 3);
  assert.equal(visible.some(({ params }) => params?.item?.id === item.id), false);
});

test('Codex withholds plan text before research', async (t) => {
  const { session, params, visible } = await setupCodex(t);
  const item = { id: 'unverified-plan', type: 'plan', text: 'Unverified plan' };
  await session.fromServer({ method: 'item/started', params: { ...params, item } });
  await session.fromServer({ method: 'item/plan/delta', params: { ...params, itemId: item.id, delta: item.text } });
  await session.fromServer({ method: 'item/completed', params: { ...params, item } });
  await session.fromServer({ method: 'turn/completed', params: {
    threadId: params.threadId, turn: { id: params.turnId, items: [item] },
  } });
  assert.equal(JSON.stringify(visible).includes(item.text), false);
});

test('a change before Codex switches from research to editing restarts research', async (t) => {
  const { session, params, sent, completeResearch, changePremise } = await setupCodex(t);
  await completeResearch(true);
  changePremise();
  await session.fromServer({ method: 'turn/completed', params: {
    threadId: params.threadId, turn: { id: params.turnId, items: [] },
  } });
  const retry = sent.find((message) => message.method === 'turn/start' && message.params.toolOutput);
  assert.ok(retry);
  assert.deepEqual(JSON.parse(retry.params.toolOutput.output).changed, ['state']);
  assert.equal(retry.params.sandboxPolicy.type, 'readOnly');
});

test('a Codex correction is judged together with the original request and can resume editing', async (t) => {
  const { session, params, invoke, sent } = await setupCodex(t, (request) => {
    assert.match(request, /Check a local setting/);
    assert.match(request, /Use the other name/);
    return { verdict: 'approved', reason: 'The names are supplied' };
  });
  await session.fromTerminal({ id: 10, method: 'turn/steer', params: {
    threadId: params.threadId, expectedTurnId: params.turnId, input: [{ type: 'text', text: 'Use the other name' }],
  } });
  await invoke(11, 'research_gate', { action: 'waiver', reason: 'No additional facts required', continueWork: true });
  assert.equal(sent.findLast(({ id }) => id === 11)?.result.success, true);
  await session.fromServer({ method: 'turn/completed', params: {
    threadId: params.threadId, turn: { id: params.turnId, items: [] },
  } });
  const resumed = sent.find((message) => message.method === 'turn/start' && message.params.toolOutput);
  assert.equal(resumed?.params.permissions, ':workspace');
});

test('a Codex subagent rechecks its parent turn before each operation', async (t) => {
  const childId = 'fixture-child';
  const childTurnId = 'child-turn';
  const rootTurnId = 'parent-editing-turn';
  const { session, params, completeResearch, changePremise, sent } = await setupCodex(t, undefined, (id) => ({
    id,
    parentThreadId: 'fixture-thread',
    turns: [{ id: childTurnId, rootTurnId }],
  }));
  await completeResearch(true);
  await session.fromServer({ method: 'turn/completed', params: {
    threadId: params.threadId, turn: { id: params.turnId, items: [] },
  } });
  await session.fromServer({ method: 'turn/started', params: { threadId: params.threadId, turn: { id: rootTurnId } } });

  assert.equal(await session.mayRunTool(params.threadId, childTurnId, 'Bash', childId), true);
  changePremise();
  assert.equal(await session.mayRunTool(params.threadId, childTurnId, 'Bash', childId), false);
  assert.equal(sent.filter((message) => message.method === 'thread/read').length, 1);
});

test('cancelling a Codex connector approval withholds the pending answer', async (t) => {
  const { session, params, completeResearch, visible, sent } = await setupCodex(t);
  await completeResearch();
  const item = { id: 'pending-answer', type: 'agentMessage', text: 'A result the user cancelled' };
  await session.fromServer({ method: 'item/started', params: { ...params, item } });
  await session.fromServer({ id: 12, method: 'mcpServer/elicitation/request', params: {
    ...params, mode: 'form', serverName: 'fixture',
  } });
  await session.fromTerminal({ id: 12, result: { action: 'cancel', content: null, _meta: null } });
  await session.fromServer({ method: 'item/completed', params: { ...params, item } });

  assert.equal(visible.some(({ params }) => params?.item?.id === item.id), false);
  assert.ok(sent.some(({ method }) => method === 'turn/interrupt'));
});

test('Codex forwards a verification service failure without treating it as user refusal', async (t) => {
  const { session, params, completeResearch, sent } = await setupCodex(t);
  await completeResearch();
  await session.fromServer({ id: 12, method: 'mcpServer/elicitation/request', params: {
    ...params, mode: 'url', serverName: 'fixture',
  } });
  const result = { action: 'cancel', content: null, _meta: { 'openai/userVerificationReason': 'serviceError' } };
  await session.fromTerminal({ id: 12, result });

  assert.deepEqual(sent.findLast(({ id }) => id === 12), { id: 12, result });
  assert.equal(sent.some(({ method }) => method === 'turn/interrupt'), false);
});

test('Codex can observe a byte range in a large single-line file', async (t) => {
  const root = mkdtempSync(join(tmpdir(), 'kata-byte-range-'));
  t.after(() => rmSync(root, { recursive: true }));
  const path = join(root, 'manifest.json');
  writeFileSync(path, 'x'.repeat(70_000) + 'chunk');
  const { invoke, sent } = await setupCodex(t, undefined, undefined, true);
  await invoke(3, 'research_gate', { action: 'research' });
  await invoke(4, 'read_research_file', { path, byteOffset: 70_000, byteLength: 5 });
  const response = sent.findLast(({ id }) => id === 4)?.result;
  assert.equal(response.success, true, response.contentItems[0].text);
  assert.equal(JSON.parse(response.contentItems[0].text).content, 'chunk');
});

test('Claude reports the original model transport failure before displaying the draft', async () => {
  const upstreamFailure = new Error('Model connection reset');
  async function* model() {
    yield { kind: 'text', index: 0, text: 'Unverified draft' };
    throw upstreamFailure;
  }
  const answer = guardedResponse({ turnId: 'fixture-turn', index: 0 }, model, () => assert.fail('No completed model response'));
  await assert.rejects(answer.next(), upstreamFailure);
});

function setup(t) {
  const root = mkdtempSync(join(tmpdir(), 'kata-research-'));
  t.after(() => rmSync(root, { recursive: true }));
  const rule = join(root, 'reference.txt');
  const state = join(root, 'tracking.txt');
  const setTracking = (tracking) => writeFileSync(state, tracking);
  setTracking('UNTRACKED');
  writeFileSync(rule, 'Files already tracked by Git are not affected');
  const observe = (id) => readFileSync(id === 'tracking' ? state : rule, 'utf8');
  const control = new ResearchControl(observe);
  const turn = control.begin('Is generated.txt tracked?');
  const sample = () => ['rule', 'tracking'].map((id) => ({ id, value: observe(id) }));
  const messages = [];
  return { control, turn, sample, setTracking, observe, messages, display: (answer) => messages.push(answer) };
}

test('no answer before research and same answer is displayed after evidence', async (t) => {
  const { control, turn, sample, messages, display } = setup(t);
  control.requestResearch(turn);
  await assert.rejects(
    control.publish(turn, () => assert.fail('Started an answer before research'), display),
    ResearchRequired,
  );
  control.recordResearch(turn, sample());
  await control.publish(turn, () => 'UNTRACKED', display);
  assert.deepEqual(messages, ['UNTRACKED']);
});

test('only an independent permission to omit research releases a waiver', async (t) => {
  const { control, turn, sample, messages, display } = setup(t);
  let calls = 0;
  await control.requestWaiver(turn, 'The prompt supplies the answer', (request, reason) => {
    calls++;
    assert.equal(request, 'Is generated.txt tracked?');
    assert.equal(reason, 'The prompt supplies the answer');
    return { verdict: 'research', reason: 'The prompt does not say what Git tracks' };
  });
  await assert.rejects(control.publish(turn, () => assert.fail('Started an answer'), display), ResearchRequired);
  control.recordResearch(turn, sample());
  await control.publish(turn, () => 'UNTRACKED', display);
  assert.equal(calls, 1);
  assert.deepEqual(messages, ['UNTRACKED']);
});

test('a refused action cannot be retried or treated as a research task', async (t) => {
  const { control, turn, display } = setup(t);
  await assert.rejects(control.requestWaiver(turn, 'The prompt suffices', () => ({
    verdict: 'refused', reason: 'The user declined',
  })), { name: 'ResearchRefused', message: 'The user declined' });
  assert.throws(() => control.requestResearch(turn), ResearchRefused);
  await assert.rejects(
    control.requestWaiver(turn, 'Try again', () => assert.fail('Asked again after refusal')),
    ResearchRefused,
  );
  await assert.rejects(control.publish(turn, () => assert.fail('Started a refused task'), display), ResearchRefused);
});

test('a failed judge leaves the answer pending and can be retried', async (t) => {
  const { control, turn, messages, display } = setup(t);
  await assert.rejects(control.requestWaiver(turn, 'The prompt suffices', () => {
    throw new Error('fixture transport timeout');
  }), ResearchUnavailable);
  await assert.rejects(control.publish(turn, () => assert.fail('Accepted the timeout'), display), ResearchRequired);
  await control.requestWaiver(turn, 'The prompt suffices', () => ({ verdict: 'approved', reason: 'Self-contained' }));
  await control.publish(turn, () => 'done', display);
  assert.deepEqual(messages, ['done']);
});

test('a verdict for the previous input cannot be used for the corrected task', async (t) => {
  const { control, turn, display } = setup(t);
  let newTurn;
  await assert.rejects(control.requestWaiver(turn, 'Self-contained', () => {
    newTurn = control.begin('Use a different file');
    return { verdict: 'approved', reason: 'Self-contained' };
  }), ObsoleteRequest);
  await assert.rejects(control.publish(newTurn, () => assert.fail('Accepted the old verdict'), display), ResearchRequired);
});

test('a changed premise withholds an answer and requires fresh evidence with the prior source', async (t) => {
  const { control, turn, sample, setTracking, observe, messages, display } = setup(t);
  control.requestResearch(turn);
  control.recordResearch(turn, sample());
  await assert.rejects(control.publish(turn, () => {
    setTracking('TRACKED');
    return 'UNTRACKED';
  }, display), ResearchRequired);
  assert.deepEqual(messages, []);
  assert.throws(() => control.recordResearch(turn, [{ id: 'tracking', value: observe('tracking') }]), ResearchRequired);
  control.recordResearch(turn, sample());
  await control.publish(turn, () => 'TRACKED', display);
  assert.deepEqual(messages, ['TRACKED']);
});

test('previous evidence does not become valid again when an observed change reverts', async (t) => {
  const { control, turn, sample, setTracking, display } = setup(t);
  control.requestResearch(turn);
  control.recordResearch(turn, sample());
  setTracking('TRACKED');
  await assert.rejects(control.publish(turn, () => assert.fail('Started with changed evidence'), display), ResearchRequired);
  setTracking('UNTRACKED');
  await assert.rejects(control.publish(turn, () => assert.fail('Restored old clearance'), display), ResearchRequired);
});

test('an in-flight answer cannot use evidence collected after generation started', async (t) => {
  const { control, turn, sample, setTracking, messages, display } = setup(t);
  control.requestResearch(turn);
  control.recordResearch(turn, sample());
  await assert.rejects(control.publish(turn, async () => {
    setTracking('TRACKED');
    await assert.rejects(control.check(turn), ResearchRequired);
    control.recordResearch(turn, sample());
    return 'UNTRACKED';
  }, display), ResearchRequired);
  assert.deepEqual(messages, []);
  await control.publish(turn, () => 'TRACKED', display);
  assert.deepEqual(messages, ['TRACKED']);
});

test('cancelling a turn withholds its pending answer', async (t) => {
  const { control, turn, sample, messages, display } = setup(t);
  control.requestResearch(turn);
  control.recordResearch(turn, sample());
  assert.equal(typeof control.cancel, 'function', 'A native interrupt cannot cancel the research permit');
  await assert.rejects(control.publish(turn, () => {
    control.cancel(turn);
    return 'UNTRACKED';
  }, display), ObsoleteRequest);
  assert.deepEqual(messages, []);
});

test('the model supplies observation references but only the adapter can supply evidence', async (t) => {
  const { ResearchSession } = await import('../agent-shared/claude-mods/kata-research/hooks/session.mjs');
  const { observe, setTracking } = setup(t);
  const session = new ResearchSession();
  const turn = session.begin('Is generated.txt tracked?');
  await session.submit(turn, { action: 'research' });
  await assert.rejects(session.submit(turn, {
    action: 'complete', sources: ['rule'], observations: ['tracking'], comparison: 'I investigated',
  }), ResearchRequired);
  session.capture(turn, 'rule', observe('rule'), () => observe('rule'));
  session.capture(turn, 'tracking', observe('tracking'), () => observe('tracking'));
  await session.submit(turn, {
    action: 'complete', sources: ['rule'], observations: ['tracking'], comparison: 'The rule applies to tracking status.',
  });
  await session.check(turn);
  setTracking('TRACKED');
  await assert.rejects(session.check(turn), ResearchRequired);
  await assert.rejects(session.submit(turn, {
    action: 'complete', sources: ['rule'], observations: ['tracking'], comparison: 'Reused old tracking result.',
  }), ResearchRequired);
  session.capture(turn, 'tracking', observe('tracking'), () => observe('tracking'));
  await session.submit(turn, {
    action: 'complete', sources: ['rule'], observations: ['tracking'], comparison: 'Now tracked. The Git rule stayed the same.',
  });
  await session.check(turn);
});

test('a failed independent check is visible and the same request may choose research', async () => {
  const { ResearchSession } = await import('../agent-shared/claude-mods/kata-research/hooks/session.mjs');
  const session = new ResearchSession();
  const turn = session.begin('Extract the names from this sentence');
  await assert.rejects(session.submit(turn, { action: 'waiver', reason: 'Self-contained' }, () => {
    throw new Error('fixture provider failed');
  }), ResearchUnavailable);
  await assert.rejects(session.check(turn), ResearchRequired);
  await session.submit(turn, { action: 'research' }, () => assert.fail('Research must not call a judge'));
});

test('duplicate approval replies cannot overtake revalidation', async (t) => {
  const { observe, setTracking } = setup(t);
  const { createCodexResearchSession } = await import('../agent-shared/bin/kata-codex-session.mjs');
  const sent = [];
  let resumeRead;
  let race = false;
  const relay = createCodexResearchSession({
    sendToServer: (message) => sent.push(message),
    sendToTerminal: () => {},
  }, {
    kataPath: '/tmp/kata/SKILL.md',
    async readEvidence(cwd, id) {
      return {
        key: id, value: observe(id),
        reread: () => race && id === 'tracking'
          ? new Promise((done) => { resumeRead = () => done(observe(id)); })
          : observe(id),
      };
    },
  });
  const threadId = 'fixture-thread';
  const turnId = 'fixture-turn';
  relay.fromTerminal({ id: 1, method: 'thread/start', params: { cwd: '/tmp' } });
  relay.fromServer({ id: 1, result: { thread: { id: threadId, cwd: '/tmp' } } });
  relay.fromTerminal({ id: 2, method: 'turn/start', params: { threadId, input: [{ type: 'text', text: 'Compare the rule and tracked state.' }] } });
  relay.fromServer({ method: 'turn/started', params: { threadId, turn: { id: turnId } } });
  const call = (id, tool, args) => relay.fromServer({
    id, method: 'item/tool/call',
    params: { threadId, turnId, namespace: 'kata_research', tool, arguments: args },
  });
  await call(3, 'research_gate', { action: 'research' });
  await call(4, 'read_research_file', { path: 'rule' });
  await call(5, 'read_research_file', { path: 'tracking' });
  await call(6, 'research_gate', {
    action: 'complete', sources: ['rule'], observations: ['tracking'], comparison: 'The tracking state matches the rule.',
  });
  relay.fromServer({ id: 7, method: 'item/commandExecution/requestApproval', params: { threadId, turnId } });
  race = true;
  const response = { id: 7, result: { decision: 'accept' } };
  const first = relay.fromTerminal(response);
  relay.fromTerminal(response);
  setTracking('TRACKED');
  resumeRead();
  await first;
  assert.deepEqual(sent.filter(({ id }) => id === 7), [{ id: 7, result: { decision: 'cancel' } }]);
});

test('public source checks use the validator and notice an updated document', async () => {
  const { observePublicSource } = await import('../agent-shared/claude-mods/kata-research/hooks/public-http.mjs');
  const responses = [
    { status: 200, headers: { etag: '"v1"' }, text: 'Old instructions' },
    { status: 304, headers: {}, text: '' },
    { status: 200, headers: { etag: '"v2"' }, text: 'New instructions' },
  ];
  const requests = [];
  const source = await observePublicSource('https://example.com/reference#section', (url, headers) => {
    requests.push([url, headers]);
    return responses.shift();
  });
  assert.equal(source.key, 'https://example.com/reference');
  assert.equal(source.value, 'Old instructions');
  assert.equal(await source.reread(), 'Old instructions');
  assert.equal(await source.reread(), 'New instructions');
  assert.deepEqual(requests, [
    ['https://example.com/reference', {}],
    ['https://example.com/reference', { 'If-None-Match': '"v1"' }],
    ['https://example.com/reference', { 'If-None-Match': '"v1"' }],
  ]);
});

test('an endpoint outside public HTTPS is rejected before fetching', async () => {
  const { observePublicSource } = await import('../agent-shared/claude-mods/kata-research/hooks/public-http.mjs');
  await assert.rejects(observePublicSource('http://127.0.0.1/reference', () => assert.fail('Made a network call')), {
    message: 'Use a public HTTPS URL without credentials.',
  });
});

test('a source cannot occupy both sides of the comparison', async (t) => {
  const { observe } = setup(t);
  const { ResearchSession } = await import('../agent-shared/claude-mods/kata-research/hooks/session.mjs');
  const session = new ResearchSession();
  const turn = session.begin('Compare the rule and tracked state.');
  await session.submit(turn, { action: 'research' });
  session.capture(turn, 'rule', observe('rule'), () => observe('rule'));
  await assert.rejects(session.submit(turn, {
    action: 'complete', sources: ['rule'], observations: ['rule'], comparison: 'Compared.',
  }), ResearchRequired);
});

test('an unavailable observation reports which evidence needs to be re-read', async (t) => {
  const { sample, observe } = setup(t);
  const control = new ResearchControl((id) => {
    if (id === 'tracking') throw new Error('The target disappeared.');
    return observe(id);
  });
  const turn = control.begin('Is the path tracked?');
  control.requestResearch(turn);
  control.recordResearch(turn, sample());
  await assert.rejects(control.check(turn), (error) => {
    assert.ok(error instanceof ResearchUnavailable);
    assert.deepEqual(error.observationIds, ['tracking']);
    return true;
  });
});
