/** How many answers this session is holding or checking right now. */
export type Holding = number

declare module 'claude-code' {
  interface PluginState {
    'output-gate': { holding: Holding }
  }
}
