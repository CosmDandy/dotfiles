import { Plugin } from "@opencode/plugin/tui"
import { createEffect, createMemo, createSignal, For, onCleanup, Show } from "solid-js"
import { useTerminalDimensions } from "@opentui/solid"
import { Limits } from "./rpc"
import { limitSegments } from "./presentation.mjs"
import { contextSummary } from "./context.mjs"

const money = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" })

export default Plugin.define({
  id: "dotfiles-chatgpt-limits",
  setup(context) {
    const client = context.client.rpc(Limits)
    const [value, setValue] = createSignal()
    const [now, setNow] = createSignal(Date.now())
    let disposed = false
    let pending = false
    const active = createMemo(() => {
      const route = context.ui.router.current()
      return route.type === "session" && context.data.session.message.list(route.sessionID).length > 0
    })
    const refresh = async () => {
      if (pending || !active()) return
      pending = true
      try {
        const result = await client.read({})
        if (!disposed) setValue(result)
      } catch {
        if (!disposed) setValue({ status: "unavailable" })
      } finally {
        if (!disposed) setNow(Date.now())
        pending = false
      }
    }
    createEffect(() => { if (active()) void refresh() })
    const timer = setInterval(() => void refresh(), 15_000)
    const removeFooter = context.ui.slot({
      append: "prompt.footer",
      render: (props) => {
        const dimensions = useTerminalDimensions()
        const [palette, setPalette] = createSignal<string[]>([])
        let mounted = true
        onCleanup(() => { mounted = false })
        createEffect(() => {
          context.themeMode
          void context.renderer.getPalette({ size: 16 }).then((colors) => {
            if (mounted && !disposed) setPalette(colors.palette)
          }).catch(() => {})
        })
        const color = (name: string) => {
          if (name === "dim") return context.theme.text.muted
          const index = { red: 1, green: 2, cyan: 6 }[name]
          return palette()[index] ?? context.theme.text.muted
        }
        const status = createMemo(() => {
          if (!props.sessionID) return []
          const session = context.data.session.get(props.sessionID)
          if (!session) return []
          const usage = contextSummary(
            context.data.session.message.list(props.sessionID),
            context.data.location.model.list(session.location),
            session.revert?.messageID,
          )
          const cost = context.data.session.cost(props.sessionID)
          return [usage, cost > 0 ? money.format(cost) : undefined].filter(Boolean)
        })
        const showLimits = createMemo(() => Boolean(
          props.sessionID && context.data.session.message.list(props.sessionID).length > 0,
        ))
        const shortcut = (id: string) => context.keymap.shortcuts(id)[0]
        return (
          <Show when={props.mode === "normal"} fallback={
            <text fg={context.theme.text.muted}>esc {dimensions().width < 44 ? "shell" : "exit shell mode"}</text>
          }>
            <Show when={status().length > 0} fallback={
              <Show when={dimensions().width >= 44}>
                <text fg={context.theme.text.muted}>{shortcut("agent.cycle")} agents</text>
              </Show>
            }>
              <box flexDirection="row" flexShrink={0}>
                <text fg={context.theme.text.muted} wrapMode="none">{status().join(" · ")}</text>
              </box>
            </Show>
            <Show when={showLimits()}>
              <text fg={context.theme.text.muted} wrapMode="none" truncate flexShrink={0}>
                <For each={limitSegments(value(), now(), dimensions().width)}>
                  {(segment, index) => <>
                    <Show when={index() > 0}><span style={{ fg: color("dim") }}> · </span></Show>
                    <span style={{ fg: color(segment.color) }}>{segment.text}</span>
                  </>}
                </For>
              </text>
            </Show>
            <Show when={dimensions().width >= 44}>
              <text fg={context.theme.text.muted} wrapMode="none" flexShrink={0}>
                <span style={{ fg: context.theme.text.base }}>{shortcut("command.palette.show")}</span> commands
              </text>
            </Show>
          </Show>
        )
      },
    })
    return () => {
      disposed = true
      removeFooter()
      clearInterval(timer)
    }
  },
})
