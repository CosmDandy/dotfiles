import { stripVTControlCharacters } from "node:util";
import type { ExtensionAPI, ExtensionContext, ExtensionUIContext, ExtensionWidgetOptions } from "@earendil-works/pi-coding-agent";

export const fleetFooterEvent = "dotfiles:fleet-footer";
export type FleetFooterUpdate = { label?: string; shown?: boolean };

const fleetWidget = "subagent-fleet-status";
type WidgetFactory = NonNullable<Parameters<ExtensionUIContext["setWidget"]>[1]>;

export function fleetFooterContext(pi: ExtensionAPI) {
  const wrapped = new WeakMap<ExtensionUIContext, ExtensionUIContext>();
  const publish = (label?: string) => {
    const update: FleetFooterUpdate = { label };
    pi.events.emit(fleetFooterEvent, update);
    return update.shown;
  };

  return (ctx: ExtensionContext): ExtensionContext => {
    if (ctx.mode !== "tui") return ctx;
    const ui = ctx.ui;
    let view = wrapped.get(ui);
    if (!view) {
      const setWidget = (key: string, content: WidgetFactory | string[] | undefined, options?: ExtensionWidgetOptions) => {
        if (typeof content !== "function") return ui.setWidget(key, content, options);
        if (key !== fleetWidget) return ui.setWidget(key, content, options);
        ui.setWidget(key, (tui, theme) => {
          const widget = content(tui, theme);
          return {
            render(width) {
              const lines = widget.render(width);
              // FleetView's collapsed summary is one row; leave the interactive roster to the package.
              const summary = lines.length === 1 ? stripVTControlCharacters(lines[0]).trimStart() : "";
              const count = /^(\d+) active agents?\b/.exec(summary)?.[1];
              const label = count ? `${count} agent${count === "1" ? "" : "s"} ↓`
                : /^Async runs \d+\//.test(summary) ? "0 agents ↓" : undefined;
              return publish(label) && label ? [] : lines;
            },
            invalidate: () => widget.invalidate(),
            dispose() {
              publish();
              widget.dispose?.();
            },
          };
        }, options);
      };
      view = new Proxy(ui, { get: (target, key, receiver) => key === "setWidget" ? setWidget : Reflect.get(target, key, receiver) });
      wrapped.set(ui, view);
    }
    return new Proxy(ctx, { get: (target, key, receiver) => key === "ui" ? view : Reflect.get(target, key, receiver) });
  };
}
