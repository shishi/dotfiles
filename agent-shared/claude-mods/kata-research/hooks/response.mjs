export async function* responseBlocked(event, error, usage = null) {
  const text = error?.name === 'ResearchRefused'
    ? '明示的な拒否を受けたため、依頼を停止しました。'
    : '調査結果または省略許可がそろっていないため、回答を保留しました。';
  yield { kind: 'text', index: 0, text };
  yield { kind: 'stop', stopReason: 'end_turn', usage };
  return { turnId: event.turnId, index: event.index, answer: text, toolUses: [], stopReason: 'end_turn', usage };
}

export async function* guardedResponse(event, next, check, recover) {
  let result;
  let keepText = true;
  const chunks = [];
  const stream = next(event);
  for (;;) {
    const item = await stream.next();
    if (item.done) {
      result = item.value;
      break;
    }
    chunks.push(item.value);
  }
  try {
    keepText = await check(result) !== 'tools';
  } catch (error) {
    if (next.signal?.aborted) return;
    const usage = result?.usage ?? null;
    const retry = recover?.(error);
    if (!retry) return yield* responseBlocked(event, error, usage);
    yield { kind: 'tool', index: 0, id: retry.id, name: retry.name };
    yield { kind: 'input', index: 0, json: JSON.stringify(retry.input) };
    yield { kind: 'stop', stopReason: 'tool_use', usage };
    return { turnId: event.turnId, index: event.index, answer: '', toolUses: [retry], stopReason: 'tool_use', usage };
  }

  for (const chunk of chunks) {
    if (next.signal?.aborted) return;
    if (keepText || !['text', 'thinking'].includes(chunk.kind)) yield chunk;
  }
  return keepText ? result : { ...result, answer: '' };
}
