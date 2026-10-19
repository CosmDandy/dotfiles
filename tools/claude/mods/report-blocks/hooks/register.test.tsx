import { expect, test } from 'claude-code/testing'

import { split } from './register'

const REPORT = [
  'Тема Claude теперь следует за системой.',
  '',
  '✔ **Сделано**',
  '- скрипт apply.sh',
  '- hook в tmux',
  '',
  '! **Найдено.** Сабмодуль отстаёт.',
  '',
  '? **Нужно твоё решение.** Мёржить?',
  '',
  '» **За тобой**',
  '1. смёржить',
  '',
  'Хвост без метки.',
].join('\n')

test('splits a report into its blocks and keeps plain runs plain', async () => {
  const parts = split(REPORT)
  expect(parts.map(p => p.kind)).toEqual(['text', 'done', 'found', 'decide', 'act', 'text'])
  expect(parts[1].text).toBe('**Сделано**\n- скрипт apply.sh\n- hook в tmux')
  expect(parts[4].text).toBe('**За тобой**\n1. смёржить')
  expect(parts[5].text).toBe('Хвост без метки.')
})

test('a blank line ends the card; the explanation under it stays plain', async () => {
  const text = '! **Найдено.** Сабмодуль отстаёт.\n- на два коммита\n\nПотому что пуш за владельцем.\n\n  - и отступ тоже'
  const parts = split(text)
  expect(parts.map(p => p.kind)).toEqual(['found', 'text'])
  expect(parts[0].text).toBe('**Найдено.** Сабмодуль отстаёт.\n- на два коммита')
  expect(parts[1].text).toBe('Потому что пуш за владельцем.\n\n  - и отступ тоже')
})

test('a glyph inside code or mid-sentence opens no block', async () => {
  const text = 'Ответ.\n\n```sh\n! not a block\n? neither\n```\nДа! И что?\n!important'
  expect(split(text).every(p => p.kind === 'text')).toBe(true)
})

test('a reply with blocks draws a card per block; one without is left to the engine', async ($, on) => {
  // stands for the engine's own drawing of an assistant block
  on('ui.render', { component: 'AssistantMessage' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text key="engine">{e.props.text}</Text>
  })
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({
      plugin: 'report-blocks',
      surface,
      component: 'AssistantMessage',
      props: { text: REPORT, isFirstOfReply: true },
    })
    const colours = []
    for (const key of ['b0', 'b1', 'b2', 'b3']) {
      colours.push((await ui.find({ key }))?.props.borderColor)
    }
    expect(colours).toEqual(['success', 'claude', 'warning', 'suggestion'])
    expect((await ui.find({ key: 't4' }))?.text).toBe('Хвост без метки.')
    // the engine draws the opening plain run only, so its bullet stays
    expect((await ui.find({ type: 'Text' }))?.text).toBe('Тема Claude теперь следует за системой.')
    await ui.unmount()

    const plain = await $.ui.mount({
      plugin: 'report-blocks',
      surface,
      component: 'AssistantMessage',
      props: { text: 'Просто ответ без меток.', isFirstOfReply: true },
    })
    expect(await plain.find({ key: 'b0' })).toBeUndefined()
    expect((await plain.find({ type: 'Text' }))?.text).toBe('Просто ответ без меток.')
    await plain.unmount()
  }
})
