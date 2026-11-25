export type PaneView = { text: string; at: string; error: string }

declare module 'claude-code' {
  interface PluginState {
    panes: { views: Record<string, PaneView>; open: string[] }
  }
}
