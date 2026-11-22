import { access, mkdir, mkdtemp, rm } from 'node:fs/promises';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createResearchHistory } from './kata-codex-history.mjs';
import { serveCodexRelay } from './kata-codex-relay.mjs';
import { createCodexResearchSession } from './kata-codex-session.mjs';
import { serveCodexToolGuard } from './kata-codex-tool-guard.mjs';

const scriptDirectory = fileURLToPath(new URL('./', import.meta.url));
const args = process.argv.slice(2);
const codexHome = process.env.CODEX_HOME || join(homedir(), '.codex');
const kataPath = join(codexHome, 'skills', 'kata', 'SKILL.md');
const publicReader = {
  path: join(scriptDirectory, 'kata-public-https.py'),
  permissionProfile: 'kata-public-https',
};
const stateHome = process.env.XDG_STATE_HOME || join(homedir(), '.local', 'state');
const history = createResearchHistory(join(stateHome, 'kata-research', 'codex'));
const state = await mkdtemp(join(tmpdir(), 'kata-codex-'));
const socket = join(state, 'terminal.sock');
const guardSocket = join(state, 'tool.sock');
let relay;
let guard;
let activeSession;
let terminal;
let model;

function stop() {
  terminal?.kill();
  relay?.stop();
  guard?.stop(true);
}

try {
  await access(kataPath);
  const judgeDirectory = join(state, 'judge');
  await mkdir(judgeDirectory);
  const judgeModel = async () => {
    model ??= (async () => {
      const lookup = Bun.spawn([join(scriptDirectory, 'codex-model'), 'luna'], {
        cwd: judgeDirectory, stdout: 'pipe', stderr: 'inherit',
      });
      const name = (await new Response(lookup.stdout).text()).trim();
      if (await lookup.exited !== 0 || !name) throw new Error('No supported Codex judge model was resolved.');
      return name;
    })();
    try {
      return await model;
    } catch (error) {
      model = undefined;
      throw error;
    }
  };
  guard = serveCodexToolGuard(guardSocket, () => activeSession);
  relay = serveCodexRelay(socket, [
    '-c', 'permissions.kata-public-https.extends=":read-only"',
    '-c', 'permissions.kata-public-https.network.enabled=true',
  ], (transport) => {
    activeSession = createCodexResearchSession(transport, {
      kataPath, judgeModel, judgeDirectory, history, requireToolGuard: true, publicReader,
    });
    return activeSession;
  }, { ...process.env, KATA_RESEARCH_CHECK_SOCKET: guardSocket });
  terminal = Bun.spawn(['codex', '--remote', `unix://${socket}`, ...args], {
    stdin: 'inherit', stdout: 'inherit', stderr: 'inherit',
  });
  process.once('SIGTERM', stop);
  process.once('SIGHUP', stop);
  process.exitCode = await terminal.exited;
} catch {
  console.error('Codex の調査制御を開始できませんでした。起動設定と kata の配置を確認してください。');
  process.exitCode = 1;
} finally {
  stop();
  if (relay) await relay.done;
  await rm(state, { recursive: true });
}
