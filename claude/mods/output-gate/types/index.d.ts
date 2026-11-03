/** How many answers this session is holding or checking right now. */
export type Holding = number

/** A message of the conversation as the checker reads it. */
export type HoldingMessage = { role: string; text: string }

/**
 * What the gate keeps for one turn of the main loop, by its turnId; null once the turn ended.
 *
 * `round` is how many times the gate swapped a final answer for its `gate_findings` call (`gate_tool_id`);
 * `original` and `unmet` are the answer it withheld and what to show if the turn ends before the next
 * final answer. `judged_len` is how much of `shown` was already judged as a final answer.
 */
export type HoldingTurn = {
  latest_user: string
  turn_start_context: HoldingMessage[]
  started_at: number
  tool_ids: string[]
  shown: string
  judged_len: number
  round: number
  agent_message: string | null
  findings: unknown[]
  original: string | null
  unmet: string | null
  gate_tool_id: string | null
  checks: HoldingCheck[]
} | null

/** One check of the turn: which checker judged it, why the others failed, and which findings were dropped. */
export type HoldingCheck = {
  index: number
  final: boolean
  status: string
  engine: unknown
  engine_failures: unknown[]
  dropped: unknown[]
  reason: string | null
}

/** One tool call of the main loop as `tool.call` saw it, by its tool_use_id; null once the turn ended. */
export type HoldingEvidence = {
  tool: string
  command: string | null
  input: Record<string, unknown>
  output: string
  failed: boolean
  exit_code: number | null
  note: string | null
} | null

/** The `gate_findings` call the gate made up, by its tool_use_id: what the call answers. */
export type HoldingIssued = { turn_id: string; agent_message: string } | null

declare module 'claude-code' {
  interface PluginState {
    'output-gate': {
      holding: Holding
      /** The turnId of the running main turn, so input sent while it runs joins its request; null between turns. */
      active: string | null
      turn: StateFamily<HoldingTurn>
      evidence: StateFamily<HoldingEvidence>
      issued: StateFamily<HoldingIssued>
    }
  }
}
