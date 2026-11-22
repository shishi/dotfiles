import { createInterface } from 'node:readline';
import { Readable } from 'node:stream';

export function serveCodexRelay(socket, args, createSession, env = process.env) {
  const backend = Bun.spawn(['codex', 'app-server', '--stdio', ...args], {
    stdin: 'pipe',
    stdout: 'pipe',
    stderr: 'inherit',
    env,
  });
  const output = createInterface({ input: Readable.fromWeb(backend.stdout) });
  let closed = false;
  let claimed = false;
  let session;

  function stop() {
    if (closed) return;
    closed = true;
    session?.close?.();
    server.stop(true);
    output.close();
    backend.kill();
  }

  const server = startSocket();
  function startSocket() {
    try {
      return Bun.serve({
        unix: socket,
        fetch(request, server) {
          if (!claimed && server.upgrade(request)) {
            claimed = true;
            return;
          }
          return new Response('This terminal has its own Codex session.', { status: 503 });
        },
        websocket: {
          idleTimeout: 0,
          open(client) {
            const sendToTerminal = (message) => client.send(JSON.stringify(message));
            const sendToServer = (message) => {
              backend.stdin.write(JSON.stringify(message) + '\n');
              return backend.stdin.flush();
            };
            try {
              session = createSession({ sendToTerminal, sendToServer });
              client.data = session;
              output.on('line', (line) => dispatch(client.data.fromServer, line));
            } catch {
              fail();
            }
          },
          message(client, line) {
            dispatch(client.data.fromTerminal, line);
          },
          close() {
            stop();
          },
          error: fail,
        },
      });
    } catch (error) {
      output.close();
      backend.kill();
      throw error;
    }
  }

  function fail() {
    if (closed) return;
    console.error('The Codex connection failed. The terminal session stopped.');
    stop();
  }

  function dispatch(receiver, line) {
    try {
      Promise.resolve(receiver(JSON.parse(line))).catch(fail);
    } catch {
      fail();
    }
  }

  const done = backend.exited.finally(stop);
  return { done, stop };
}
