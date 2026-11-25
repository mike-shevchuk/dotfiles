import { expect, test } from 'claude-code/testing'

const PANE = {
  plugin: 'panes',
  component: 'Pane',
  requestId: 'pane-mine',
  props: { title: 'Mine', isFocused: false, bodyColumns: 80, placement: 'dock', scroll: { offset: 0, bodyRows: 30 }, view: {} },
} as const

// the engine stamps origin + presentation on every command.run — the double carries them too
const run = (command: string, args = '') =>
  ({ command, args, origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 160 } }) as const

const ok = (stdout: string) => ({ value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } })

test('/pane mine runs lead.py mine full and shows its verbatim output; an unknown view lists the views', async ($, on) => {
  const argvs: string[][] = []
  on('command.register', () => ({ value: { command: 'pane' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('env.get', () => ({ value: '/Users/x' }))
  on('process.run', (_, e) => {
    argvs.push([...e.argv])
    return ok('\x1b[1m┌─ [P0 PUN-1938] W42:9 · punchIn\x1b[0m\n│ ПИТАННЯ ДО ТЕБЕ:\n')
  })

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  expect((await $.command.run(run('pane', 'nope'))).text).toMatch(/gates · mine/)
  expect((await $.command.run(run('pane', 'mine'))).text).toMatch(/opened/)
  expect(argvs.at(-1)).toEqual(['python3', '/Users/x/.claude/scripts/lead.py', 'mine', 'full'])

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /W42:9/ }))?.text).toBe('┌─ [P0 PUN-1938] W42:9 · punchIn')
    await ui.unmount()
  }
})

test('/legend opens the emoji legend pane from the one legend file', async ($, on) => {
  const argvs: string[][] = []
  on('command.register', () => ({ value: { command: 'legend' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('env.get', () => ({ value: '/Users/x' }))
  on('process.run', (_, e) => {
    argvs.push([...e.argv])
    return ok('🧾 ЛЕГЕНДА\n   🔄  працює зараз                       🙋  стоїть і чекає ТЕБЕ\n')
  })

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  expect((await $.command.run(run('legend'))).text).toMatch(/Legend — emoji — opened/)
  expect(argvs.at(-1)).toEqual(['cat', '/Users/x/.claude/fleet-board/legend.md'])

  const ui = await $.ui.mount({ ...PANE, requestId: 'pane-legend', surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /працює зараз/ }))?.text).toMatch(/🔄/)
  await ui.unmount()
})
