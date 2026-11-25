import { expect, test } from 'claude-code/testing'

const ROWS = {
  session: 'W42',
  scope: '9',
  ts: '14:00',
  extra: [],
  rows: [
    {
      win: 'W42:9', i: '9', name: '🔵 PUN-1938 · punchIn↔alert', state: 'waiting', track: 'PUN-1938', pct: 80,
      step: '#2381 → dev', eta: '~15:00', waiting: 'Чекаю на: dev', asks: ['**PUN-1938 → «PR так»**'], need: [], brief_age: '5хв',
      plans: [{ id: 'PUN-1938', path: '~/p.md', url: 'http://x#f-PUN-1938', gist: ['one record'], questions: ['Q1 ok?'], approved: false, say: 'план так PUN-1938' }],
    },
  ],
}

const PANE = {
  plugin: 'blockers',
  component: 'Pane',
  requestId: 'blockers',
  props: { title: '🙋 Blockers', isFocused: false, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 30 }, view: {} },
} as const

test('a teammate window shows only itself, with its window number and the ask for Mike', async ($, on) => {
  const argvs: string[][] = []
  on('command.register', () => ({ value: { command: 'blockers' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('env.get', (_, e) => ({ value: e.name === 'TMUX_PANE' ? '%9' : '/Users/x' }))
  on('process.run', (_, e) => {
    argvs.push([...e.argv])
    if (e.argv[0] === 'tmux') return { value: { exitCode: 0, stdout: 'W42\t9\n', stderr: '' } }
    return { value: { exitCode: 0, stdout: JSON.stringify(ROWS), stderr: '' } }
  })

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const { text } = await $.command.run({ command: 'blockers' })
  expect(text).toMatch(/1 window/)
  // teammate → lead.py is asked for that window only
  expect(argvs.find(a => a[0] === 'python3')).toContain('9')

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /W42:9/ }))?.text).toMatch(/W42:9/)
    expect((await ui.find({ type: 'Text', text: /PR так/ }))?.text).toMatch(/🙋/)
    expect((await ui.find({ type: 'Text', text: /напиши ліду/ }))?.text).toMatch(/план так PUN-1938/)
    expect((await ui.find({ type: 'Text', text: /файл:/ }))?.text).toMatch(/p\.md/)
    await ui.unmount()
  }
})
