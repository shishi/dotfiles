import { randomBytes } from 'node:crypto';

const serverName = 'kata_research_resume';
const prefix = `mcp_servers.${serverName}`;

export function createResumeTools() {
  const sessions = new Map();
  let server;

  function attach(tools, call) {
    server ??= Bun.serve({
      hostname: '127.0.0.1',
      port: 0,
      async fetch(request) {
        if (request.headers.has('origin')) return new Response(null, { status: 403 });
        if (request.method !== 'POST') return new Response(null, { status: 405, headers: { allow: 'POST' } });
        const session = sessions.get(request.headers.get('authorization'));
        if (!session || new URL(request.url).pathname !== '/mcp') return new Response(null, { status: 404 });

        let message;
        try {
          message = await request.json();
        } catch {
          return new Response(null, { status: 400 });
        }
        if (!message || message.jsonrpc !== '2.0' || typeof message.method !== 'string') {
          return new Response(null, { status: 400 });
        }
        const { id, method, params } = message;
        if (id === undefined) return new Response(null, { status: 202 });
        let result;
        switch (method) {
          case 'initialize':
            result = {
              protocolVersion: '2025-11-25',
              capabilities: { tools: {} },
              serverInfo: { name: serverName, version: '1' },
            };
            break;
          case 'ping':
            result = {};
            break;
          case 'tools/list':
            result = { tools: session.tools };
            break;
          case 'tools/call':
            result = await session.call(params?.name, params?.arguments);
            break;
          default:
            return Response.json({ jsonrpc: '2.0', id, error: { code: -32601, message: 'Unknown method.' } });
        }
        return Response.json({ jsonrpc: '2.0', id, result });
      },
    });
    const authorization = `Bearer ${randomBytes(32).toString('hex')}`;
    sessions.set(authorization, { tools, call });
    return {
      config: {
        [`${prefix}.url`]: `http://127.0.0.1:${server.port}/mcp`,
        [`${prefix}.http_headers`]: { Authorization: authorization },
        [`${prefix}.required`]: true,
        [`${prefix}.default_tools_approval_mode`]: 'approve',
        [`${prefix}.supports_parallel_tool_calls`]: true,
      },
      close: () => sessions.delete(authorization),
    };
  }

  return { attach, stop: () => server?.stop(true) };
}
