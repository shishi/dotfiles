export function serveCodexToolGuard(socket, session) {
  return Bun.serve({
    unix: socket,
    async fetch(request) {
      if (request.method !== 'POST' || request.headers.has('origin')) {
        return new Response(null, { status: 403 });
      }
      try {
        const { session_id: threadId, turn_id: turnId, tool_name: tool, agent_id: agentId } = await request.json();
        if (await session()?.mayRunTool(threadId, turnId, tool, agentId)) {
          return new Response(null, { status: 204 });
        }
      } catch {
        return new Response(null, { status: 409 });
      }
      return new Response(null, { status: 409 });
    },
  });
}
