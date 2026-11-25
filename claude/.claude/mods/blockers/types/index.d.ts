export type PlanBrief = { id: string; path: string; url: string; gist: string[]; questions: string[]; approved: boolean; say: string }
export type BlockerRow = {
  plans: PlanBrief[]
  win: string
  i: string
  name: string
  state: string
  track: string
  pct: number | null
  step: string
  eta: string
  waiting: string
  asks: string[]
  need: string[]
  brief_age: string | null
}
export type Blockers = { session: string; scope: string; rows: BlockerRow[]; extra: string[]; ts: string }
export type Where = { session: string; index: string; isLead: boolean }

declare module 'claude-code' {
  interface PluginState {
    blockers: { data: Blockers | null; error: string; where: Where | null }
  }
}
