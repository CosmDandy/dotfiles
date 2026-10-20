import type { Color, Register } from 'claude-code'

// Splits a reply's markdown into plain runs and report blocks.
// A block opens on a line that starts with one of the five report glyphs (bold
// markers around it allowed) and runs to the first blank line outside fenced
// code: the card holds the claim and the list glued to it, while an explanation
// set off by a blank line stays plain text under it. Fenced code is never a
// block opener.

export type Kind = 'done' | 'failed' | 'found' | 'decide' | 'act'

export type Part =
  | { kind: 'text'; text: string }
  | { kind: Kind; glyph: string; text: string }

const GLYPHS: Record<string, Kind> = {
  '✔': 'done',
  '✘': 'failed',
  '!': 'found',
  '?': 'decide',
  '»': 'act',
}

const OPENER = /^ {0,3}(\*\*|__)?(✔|✘|!|\?|»)(?=\s|\*\*|__)\s*/
const FENCE = /^ {0,3}(```|~~~)/

export function split(text: string): Part[] {
  const lines = text.split('\n')
  const parts: Part[] = []
  let plain: string[] = []
  let block: { kind: Kind; glyph: string; lines: string[] } | null = null
  let inFence = false

  const flushPlain = () => {
    const t = plain.join('\n').replace(/\s+$/, '')
    if (t.trim() !== '') parts.push({ kind: 'text', text: t })
    plain = []
  }
  const flushBlock = () => {
    if (block) {
      parts.push({ kind: block.kind, glyph: block.glyph, text: block.lines.join('\n').replace(/\s+$/, '') })
      block = null
    }
  }

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    if (FENCE.test(line)) inFence = !inFence
    const m = inFence ? null : OPENER.exec(line)
    if (m && !FENCE.test(line)) {
      flushBlock()
      flushPlain()
      // the glyph moves to the card's edge; a bold marker opened before it stays
      // with the rest of the line so the markdown still closes it
      block = { kind: GLYPHS[m[2]], glyph: m[2], lines: [(m[1] ?? '') + line.slice(m[0].length)] }
      continue
    }
    if (block) {
      if (!inFence && line.trim() === '') {
        flushBlock()
        continue
      }
      block.lines.push(line)
      continue
    }
    plain.push(line)
  }
  flushBlock()
  flushPlain()
  return parts
}



// Splits a block's text into its label and the rest: the label is a leading
// bold run (`**Сделано:**`) or, without one, the words up to the first colon;
// a line with neither has no label.
export function label(text: string): { label: string; rest: string } {
  const bold = /^(\*\*|__)(.+?)\1[ \t]*/.exec(text)
  if (bold) return { label: bold[2], rest: text.slice(bold[0].length) }
  const colon = /^([^:\n`]{1,40}:)[ \t]*/.exec(text)
  if (colon) return { label: colon[1], rest: text.slice(colon[0].length) }
  return { label: '', rest: text }
}

// Theme keys, so the cards follow the person's theme (Solarized light and dark).
const COLOR: Record<Kind, Color> = {
  done: 'success',
  failed: 'error',
  found: 'claude',
  decide: 'warning',
  act: 'suggestion',
}

// A card only for what needs the person's attention; the rest is a coloured
// label alone, since a terminal selection across a frame takes its `│` along
// with the text, and done, found and act blocks are the ones read and copied.
const FRAME: Record<Kind, { borderStyle?: string; paddingX?: number }> = {
  done: {},
  failed: { borderStyle: 'round', paddingX: 1 },
  decide: { borderStyle: 'round', paddingX: 1 },
  found: {},
  act: {},
}

export const register: Register = on => {
  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    if (e.props.isSummary) return next(e)
    const parts = split(e.props.text)
    if (!parts.some(p => p.kind !== 'text')) return next(e)

    const { Box, Text, Markdown } = $.ui.resolve(e)
    // NOTE: the first part goes through the engine, which is what keeps the bullet
    // that opens a reply and its indent; a report leads with its point anyway, so
    // that part is plain text in practice.
    const [first, ...rest] = parts
    const head = await next({ ...e, props: { ...e.props, text: first.text } })

    return (
      // each part after the first sits one blank line below the one before, as
      // the paragraphs of a reply do
      <Box flexDirection="column">
        {head}
        {rest.map((p, i) => {
          if (p.kind === 'text') {
            return (
              <Box key={`t${i}`} marginLeft={2} marginTop={1}>
                <Markdown text={p.text} />
              </Box>
            )
          }
          // Markdown takes no colour, so only the glyph and the label are drawn
          // as coloured Text; what follows stays markdown in the default colour.
          const { label: name, rest: after } = label(p.text)
          const head = `${p.glyph}${name ? ` ${name}` : ''}`
          const onLine = !after.startsWith('\n')
          const rest = after.replace(/^\n/, '')
          return (
            <Box
              key={`b${i}`}
              marginLeft={2}
              marginTop={1}
              flexDirection={onLine ? 'row' : 'column'}
              {...FRAME[p.kind]}
              borderColor={FRAME[p.kind].borderStyle ? COLOR[p.kind] : undefined}
            >
              <Text color={COLOR[p.kind]} bold>
                {onLine && rest ? `${head} ` : head}
              </Text>
              {rest !== '' && (
                <Box flexGrow={1} flexShrink={1} marginLeft={onLine ? 0 : 2}>
                  <Markdown text={rest} />
                </Box>
              )}
            </Box>
          )
        })}
      </Box>
    )
  })
}
