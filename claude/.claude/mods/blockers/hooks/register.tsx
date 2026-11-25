import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Blockers, BlockerRow, Where } from '../types'

// Mike 21.10: like /diff, a side pane — his blockers in detail. Fleet lead → every teammate; a teammate → only itself.
const PANE = 'blockers'
const data = atom({ plugin: 'blockers', key: 'data' } as const, null)
const error = atom({ plugin: 'blockers', key: 'error' } as const, '')
const where = atom({ plugin: 'blockers', key: 'where' } as const, null)

const bar = (pct: number) => '▓'.repeat(Math.round(pct / 10)) + '░'.repeat(10 - Math.round(pct / 10))

// which tmux window this session runs in: W42:1 or a non-W session (the lead's own «w42») = lead, else one teammate
async function locate($: EngineInterface): Promise<Where> {
  const pane = await $.env.get('TMUX_PANE')
  if (!pane) return { session: '', index: '', isLead: true }
  const { stdout } = await $.process.run(['tmux', 'display', '-p', '-t', pane, '#S\t#I'])
  const [session = '', index = ''] = stdout.trim().split('\t')
  return { session, index, isLead: !/^W\d+$/.test(session) || index === '1' }
}

async function refresh($: EngineInterface) {
  const at = (await read($, where)) ?? (await locate($))
  await update($, where, () => at)
  const home = (await $.env.get('HOME')) ?? ''
  const argv = ['python3', `${home}/.claude/scripts/lead.py`, 'blockers', ...(at.isLead ? [] : [at.index]), '--json']
  const env = /^W\d+$/.test(at.session) ? { LEAD_SESSION: at.session } : undefined
  const run = await $.process.run(argv, { env, timeoutMs: 60000 })
  if (run.exitCode !== 0) {
    await update($, error, () => `lead.py blockers: exit ${run.exitCode} ${run.stderr.slice(0, 200)}`)
    return
  }
  await update($, data, () => JSON.parse(run.stdout) as Blockers)
  await update($, error, () => '')
}


export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'blockers', description: 'Pane: my blockers in detail (lead: every teammate · teammate: this window)', immediate: true })
    $.clock.every(60000, () => refresh($))
    return next(e)
  })

  on('command.run', { command: 'blockers' }, async $ => {
    await refresh($)
    const { isPlaced } = await $.ui.open({ id: PANE, title: '🙋 Blockers' })
    const d = await read($, data)
    const n = d ? d.rows.filter(r => r.asks.length || r.need.length).length : 0
    return { text: isPlaced ? `Blockers pane opened — ${n} window(s) wait on you.` : 'Blockers pane is queued (the terminal is too narrow to seat it now).' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const d = await read($, data)
    const err = await read($, error)
    if (err) return <Text color="error">{err}</Text>
    if (!d) return <Text dimColor>Loading… (/blockers to refresh)</Text>
    const waitsOnMike = (r: BlockerRow) => r.asks.length + r.need.length > 0
    const rows = [...d.rows].sort((a, b) => Number(waitsOnMike(b)) - Number(waitsOnMike(a)))
    const total = rows.reduce((s, r) => s + r.asks.length + r.need.length, 0) + d.extra.length

    return (
      <Box flexDirection="column" gap={1}>
        <Text bold>
          {d.scope === 'lead' ? `${d.session} · fleet` : `${d.session}:${d.scope}`} · 🙋 {total} for you · {d.ts}
        </Text>
        {rows.map(r => (
          <Box key={r.win} flexDirection="column" borderStyle="round" borderColor={waitsOnMike(r) ? 'warning' : 'subtle'} paddingX={1}>
            <Text bold wrap="truncate-end">
              {r.win} {r.name}
            </Text>
            <Text dimColor wrap="truncate-end">
              {r.state === 'working' ? '🔄 working' : '⏳ waiting'}
              {r.pct !== null ? `  ${bar(r.pct)} ${r.pct}%  ETA ${r.eta}` : ''}
            </Text>
            {r.step ? <Text wrap="wrap">{r.step}</Text> : null}
            {r.waiting ? <Text color="suggestion" wrap="wrap">{r.waiting}</Text> : null}
            {[...r.asks, ...r.need].map((a, k) => (
              <Text key={String(k)} color="warning" wrap="wrap">
                🙋 {a.replace(/\*\*/g, '')}
              </Text>
            ))}
            {(r.plans ?? []).map(p => (
              <Box key={p.id} flexDirection="column" borderStyle="single" borderColor="suggestion" paddingX={1} marginTop={1}>
                <Text bold color="suggestion">📋 План {p.id} — чекає твій апрув</Text>
                <Text wrap="wrap">файл: {p.path}</Text>
                <Text wrap="wrap" underline>{p.url}</Text>
                {p.gist.map((g, k) => (
                  <Text key={`g${k}`} wrap="wrap">• {g}</Text>
                ))}
                {p.questions.length ? <Text bold>Питання до тебе:</Text> : null}
                {p.questions.map((q, k) => (
                  <Text key={`q${k}`} wrap="wrap" color="warning">{q}</Text>
                ))}
                <Text bold color="success">→ напиши ліду: «{p.say}»</Text>
              </Box>
            ))}
            {r.brief_age ? <Text dimColor>brief {r.brief_age} old</Text> : null}
          </Box>
        ))}
        {d.extra.length ? (
          <Box flexDirection="column" borderStyle="round" borderColor="warning" paddingX={1}>
            <Text bold>Not tied to a window</Text>
            {d.extra.map((x, k) => (
              <Text key={String(k)} color="warning" wrap="wrap">
                🙋 {x}
              </Text>
            ))}
          </Box>
        ) : null}
      </Box>
    )
  })
}
