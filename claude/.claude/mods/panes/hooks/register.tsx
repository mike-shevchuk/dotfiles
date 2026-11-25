import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { PaneView } from '../types'

// Mike 21.10: the slash commands that only ran a script and printed it verbatim cost a model turn each — a pane costs nothing.
const VIEWS: Record<string, { title: string; argv: string[]; everyMs: number }> = {
  gates: { title: '🧭 PR gates (/pr-state all)', argv: ['~/.claude/pipeline-stamp.sh', 'gates'], everyMs: 300000 },
  mine: { title: '🙋 Mine (full)', argv: ['python3', '~/.claude/scripts/lead.py', 'mine', 'full'], everyMs: 120000 },
  fleet: { title: '🛰 Fleet', argv: ['python3', '~/.claude/scripts/lead.py', 'fleet'], everyMs: 120000 },
  stuck: { title: '⛔ Stuck', argv: ['python3', '~/.claude/scripts/lead.py', 'stuck'], everyMs: 120000 },
  idle: { title: '💤 Idle', argv: ['python3', '~/.claude/scripts/lead.py', 'idle'], everyMs: 120000 },
  devnow: { title: '🚂 Dev now', argv: ['python3', '~/.claude/scripts/lead.py', 'devnow'], everyMs: 120000 },
  tokens: { title: '🪙 Tokens', argv: ['python3', '~/.claude/scripts/lead.py', 'tokens'], everyMs: 300000 },
  trylog: { title: '🧪 Last try', argv: ['python3', '~/.claude/scripts/lead.py', 'trylog'], everyMs: 120000 },
  board: { title: '📋 Board', argv: ['python3', '~/.claude/scripts/lead.py', 'board'], everyMs: 300000 },
  footer: { title: '👥 Lead footer', argv: ['python3', '~/.claude/scripts/lead.py', 'footer'], everyMs: 60000 },
  'sprint-pr': { title: '🏁 Sprint PRs', argv: ['~/.claude/pipeline-stamp.sh', 'fleet'], everyMs: 300000 },
  // Mike 22.10: every emoji of the tmux windows, footer, /pr-state and the status page — one file, kept by the lead
  legend: { title: '🧾 Legend — emoji', argv: ['cat', '~/.claude/fleet-board/legend.md'], everyMs: 600000 },
}
const SLOW = new Set(['gates', 'sprint-pr', 'tokens', 'board'])
const views = atom({ plugin: 'panes', key: 'views' } as const, {})
const open = atom({ plugin: 'panes', key: 'open' } as const, [])

// eslint-disable-next-line no-control-regex
const ANSI = /\x1b\[[0-9;?]*[A-Za-z]/g

async function refresh($: EngineInterface, name: string) {
  const v = VIEWS[name]
  if (!v) return
  const home = (await $.env.get('HOME')) ?? ''
  const argv = v.argv.map(a => a.replace(/^~/, home))
  const now = new Date().toTimeString().slice(0, 5)
  try {
    const run = await $.process.run(argv, { timeoutMs: 300000, env: { NO_COLOR: '1' } })
    const text = (run.stdout || run.stderr).replace(ANSI, '').trimEnd()
    const error = run.exitCode === 0 ? '' : `exit ${run.exitCode}`
    await update($, views, all => ({ ...all, [name]: { text, at: now, error } as PaneView }))
  } catch (err) {
    await update($, views, all => ({ ...all, [name]: { text: '', at: now, error: String(err) } as PaneView }))
  }
}

async function openView($: EngineInterface, name: string) {
  await update($, open, list => (list.includes(name) ? list : [...list, name]))
  if (SLOW.has(name)) void refresh($, name) // GitHub-bound views: open at once, fill in when the script ends
  else await refresh($, name)
  const { isPlaced } = await $.ui.open({ id: `pane-${name}`, title: VIEWS[name]?.title ?? name })
  return { text: isPlaced ? `${VIEWS[name]?.title} — opened, refreshes itself.` : 'Pane queued (the terminal is too narrow to seat it now).' }
}

async function tick($: EngineInterface, name: string) {
  if ((await read($, open)).includes(name)) await refresh($, name)
}

// Mike 21.10: «/status-html» — regenerate the one-page sprint status from Claude, no model turn; it takes minutes (GitHub), so it runs in the background and toasts the link
async function statusPage($: EngineInterface, week: string) {
  const home = (await $.env.get('HOME')) ?? ''
  const run = await $.process.run(['python3', `${home}/.claude/fleet-board/bin/status-html.py`, ...(week ? [week] : [])], { timeoutMs: 600000 })
  const file = run.stdout.trim().split('\n').pop() ?? ''
  const name = file.split('/').pop() ?? ''
  if (run.exitCode !== 0 || !name) {
    $.ui.toast(`status-html failed (exit ${run.exitCode}): ${run.stderr.slice(0, 160)}`)
    return
  }
  $.ui.toast(`✅ status page updated: http://192.168.50.85:8890/rescue-serverless/fleet/${name}#mine`)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'pane',
      description: 'Side pane with a fleet view, no model tokens: gates · mine · fleet · stuck · idle · devnow · tokens · trylog · board · footer · sprint-pr · legend',
      argumentHint: '<view>',
      immediate: true,
    })
    await $.command.register({
      name: 'legend',
      description: 'Side pane: what every emoji means — tmux window marks (🔄🙋🧭🚂⏳💤), footer, /pr-state gates, status page',
      immediate: true,
    })
    await $.command.register({
      name: 'status-html',
      description: 'Regenerate the sprint status page (gates, per-feature cards, plans, kanban) in the background — toasts the link',
      argumentHint: '[week]',
      immediate: true,
    })
    for (const [name, v] of Object.entries(VIEWS)) $.clock.every(v.everyMs, () => tick($, name))
    return next(e)
  })

  on('command.run', { command: 'pane' }, async ($, e) => {
    const name = (e.args ?? '').trim()
    if (!VIEWS[name]) return { text: `Usage: /pane <view> — ${Object.keys(VIEWS).join(' · ')}` }
    return openView($, name)
  })

  on('command.run', { command: 'legend' }, async $ => openView($, 'legend'))

  on('command.run', { command: 'status-html' }, async ($, e) => {
    void statusPage($, (e.args ?? '').trim())
    return { text: '⏳ status page is regenerating in the background (1–5 min) — a toast brings the link: http://192.168.50.85:8890/rescue-serverless/fleet/' }
  })

  on('ui.render', { component: 'Pane' }, async ($, e, next) => {
    const name = e.requestId?.startsWith('pane-') ? e.requestId.slice(5) : ''
    if (!VIEWS[name]) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const v = (await read($, views))[name]
    if (!v) return <Text dimColor>Loading {name}…</Text>
    return (
      <Box flexDirection="column">
        <Text dimColor>
          {VIEWS[name]?.title} · {v.at}
          {v.error ? ` · ⚠ ${v.error}` : ''} · /pane {name} to refresh
        </Text>
        {v.text.split('\n').map((line, k) => (
          <Text key={String(k)} mono wrap="truncate-end">
            {line || ' '}
          </Text>
        ))}
      </Box>
    )
  })
}
