import { appendFileSync, closeSync, constants, mkdirSync, openSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

export function createResearchHistory(directory) {
  function historyPath(threadId) {
    if (!/^[a-zA-Z0-9][a-zA-Z0-9_-]*$/.test(threadId)) throw new Error('Invalid Codex thread ID.');
    return join(directory, threadId + '.jsonl');
  }

  function read(threadId) {
    const released = new Map();
    let fd;
    try {
      fd = openSync(historyPath(threadId), constants.O_RDONLY | constants.O_NOFOLLOW);
    } catch (error) {
      if (error.code === 'ENOENT') return released;
      throw error;
    }
    try {
      for (const line of readFileSync(fd, 'utf8').split('\n')) {
        if (!line) continue;
        const [turnId, itemId] = JSON.parse(line);
        if (typeof turnId !== 'string' || (itemId !== null && typeof itemId !== 'string')) {
          throw new Error('Invalid Codex research history record.');
        }
        if (!released.has(turnId)) released.set(turnId, new Set());
        if (itemId !== null) released.get(turnId).add(itemId);
      }
      return released;
    } finally {
      closeSync(fd);
    }
  }

  function append(threadId, records) {
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    const fd = openSync(historyPath(threadId),
      constants.O_WRONLY | constants.O_APPEND | constants.O_CREAT | constants.O_NOFOLLOW, 0o600);
    try {
      appendFileSync(fd, records.map((record) => JSON.stringify(record) + '\n').join(''));
    } finally {
      closeSync(fd);
    }
  }

  function record(threadId, turnId, itemId = null) {
    append(threadId, [[turnId, itemId]]);
  }

  function inherit(threadId, turns) {
    const records = [];
    for (const [turnId, items] of turns) {
      records.push([turnId, null]);
      for (const itemId of items) records.push([turnId, itemId]);
    }
    if (records.length) append(threadId, records);
  }

  return { read, record, inherit };
}
