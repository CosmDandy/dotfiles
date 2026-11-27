import { execFile } from "node:child_process";
import { existsSync, realpathSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { stripVTControlCharacters } from "node:util";
import { formatReadLineRange, getLanguageFromPath, getMarkdownTheme, highlightCode, isToolCallEventType } from "@earendil-works/pi-coding-agent";
import type { CodemodeToolDetails, ExtensionAPI, Theme, ToolRenderers } from "@earendil-works/pi-coding-agent";
import { colorToRgb, mixColors, parseColor, rgbColor, Markdown, Text, sliceByColumn, truncateToWidth, visibleWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";

const pulseInterval = 120;
const timingInset = 3;
const minToolTimingMs = 10_000;
const livePreviewDelayMs = 600;
const codemodePreviewRows = 8;
const bashTailRows = 5;
const sshTailRows = 10;
const graphemes = new Intl.Segmenter(undefined, { granularity: "grapheme" });

// Keep contrast subtle: lighter than the Solarized dark canvas, darker than the light canvas.
const expandedBackgrounds = { dark: rgbColor(10, 51, 62), light: rgbColor(241, 234, 215) };
const lightTimingBackground = rgbColor(255, 249, 234);

function expandedRows(rows: string[], expanded: boolean, width: number, theme: Theme): string[] {
  if (!expanded) return rows;
  const bg = expandedBackgrounds[theme.appearance];
  const open = theme.style("", { bg }).replace(/\x1b\[49m$/, "");
  return rows.map(row => {
    const padding = " ".repeat(Math.max(0, width - visibleWidth(row)));
    return theme.style(row.replace(/\x1b\[(?:0|49)?m/g, reset => reset + open) + padding, { bg });
  });
}

function runningPulse(title: string, theme: Theme, step: number, strongLightPulse: boolean): string {
  const text = stripVTControlCharacters(title);
  const start = text.match(/^ */)![0];
  const segments = [...graphemes.segment(text.slice(start.length))];
  if (segments.length === 0) return text;
  const length = visibleWidth(text) - start.length;
  const { r, g, b } = colorToRgb(theme.colors.toolOutput);
  // Short calls need a complete, distinct sweep before they disappear.
  const cycle = Math.max(8, Math.min(36, Math.round(6 + length / 3)));
  const phase = (step % cycle) / cycle;
  const peak = (1 - Math.abs(2 * phase - 1)) * (segments.length - 1);
  const spread = Math.min(16, Math.max(1.5, length * 0.26));
  const contrast = Math.max(18, 34 - Math.round(length / 3));
  let output = start, run = "", previous = 0;
  const paint = (value: string, shade: number) => {
    const shift = (channel: number) => Math.max(0, Math.min(255, channel + shade));
    return theme.style(value, { fg: rgbColor(shift(r), shift(g), shift(b)) });
  };
  for (let i = 0; i < segments.length; i++) {
    const distance = Math.min(1, Math.abs(i - peak) / spread);
    const wave = Math.cos(distance * Math.PI);
    const shade = Math.round(contrast * (strongLightPulse ? -1.5 * (wave + 1) : wave));
    if (shade !== previous && run) { output += paint(run, previous); run = ""; }
    run += segments[i].segment;
    previous = shade;
  }
  return output + paint(run, previous);
}

function clean(text: string): string {
  return stripVTControlCharacters(text).replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "");
}

function shellLog(text: string): string {
  // Keep SGR colors, not cursor moves, window commands or other terminal controls.
  return text.split(/(\x1b\[[0-9;:]{0,64}m)/g)
    .map((part, index) => index % 2 ? part : clean(part).replace(/[\x80-\x9f]/g, ""))
    .join("");
}

function preview(args: Record<string, unknown>): string {
  const value = args.path ?? args.file_path ?? args.command ?? args.pattern ?? args.query ?? args.url;
  return clean(typeof value === "string" ? value : JSON.stringify(args)).replace(/\s+/g, " ").trim();
}

function shortenPath(path: string, marker: string, minWidth: number, maxWidth: number): string {
  const prefix = maxWidth - visibleWidth(marker) >= minWidth ? marker : "";
  const room = maxWidth - visibleWidth(prefix);
  const width = visibleWidth(path);
  if (width <= room) return prefix + path;
  return prefix + "…" + (room > 1 ? sliceByColumn(path, width - room + 1, room - 1, true) : "");
}

function resolveToolPath(path: string, cwd: string): string | undefined {
  let target = path.replace(/^@/, "").replace(/[\u00A0\u2000-\u200A\u202F\u205F\u3000]/g, " ");
  if (target === "~" || target.startsWith(`~${sep}`)) target = join(homedir(), target.slice(1));
  if (target.startsWith("file://")) {
    try { target = fileURLToPath(target); } catch { return undefined; }
  }
  return resolve(cwd, target);
}

const listTools = new Set(["grep", "find", "ls"]);

function listSummary(name: string, output: string, details?: Record<string, unknown>): string {
  const limited = Boolean(details?.truncation || details?.matchLimitReached || details?.resultLimitReached || details?.entryLimitReached);
  const rows = (limited ? output.split("\n\n[")[0] : output).trimEnd().split("\n");
  const count = name === "grep" ? rows.filter(row => /^.+?:\d+: /.test(row)).length
    : !output || (name === "find" ? output === "No files found matching pattern" : output === "(empty directory)") ? 0 : rows.length;
  const noun = name === "grep" ? (count === 1 ? "match" : "matches") : name === "find" ? (count === 1 ? "file" : "files") : (count === 1 ? "entry" : "entries");
  return `${count} ${noun}${limited ? " (limited)" : ""}`;
}

type ShellSearch = { noun: "match line" | "path"; scope: string };

function shellSearch(command: unknown): ShellSearch | undefined {
  // Recognize only direct invocations; output from a pipeline or script has no reliable search count.
  if (typeof command !== "string" || /[\n\r|;&<>`$\\]/.test(command)) return undefined;
  const words = command.trim().match(/'(?:[^']*)'|"(?:[^"]*)"|[^\s'"]+/g) ?? [];
  const [name, ...args] = words;
  const unquote = (word: string) => word.replace(/^(?:'(.*)'|"(.*)")$/, "$1$2");
  if (name === "find") {
    const stop = args.findIndex(word => word.startsWith("-"));
    const paths = stop < 0 ? args : args.slice(0, stop);
    for (let i = Math.max(0, stop); stop >= 0 && i < args.length; i++) {
      if (args[i] === "-print") continue;
      if (!/^-((i?name)|(i?path)|type|maxdepth|mindepth)$/.test(args[i]) || !args[i + 1]) return undefined;
      i++;
    }
    if (paths.length) return { noun: "path", scope: paths.map(unquote).join(" ") };
  }
  if (name === "rg") {
    let files = false, explicitPattern = false;
    const operands: string[] = [];
    for (let i = 0; i < args.length; i++) {
      const word = args[i];
      if (word === "--") { operands.push(...args.slice(i + 1)); break; }
      if (word === "--files" || word === "-l" || word === "--files-with-matches") { files = true; continue; }
      if (/^-[nHiFwsS]+$/.test(word) || /^--(?:line-number|no-heading|hidden|fixed-strings|ignore-case|smart-case|with-filename)$/.test(word)) continue;
      if (["-g", "--glob", "-t", "--type", "-e", "--regexp"].includes(word) && args[i + 1]) {
        if (word === "-e" || word === "--regexp") explicitPattern = true;
        i++;
        continue;
      }
      if (word.startsWith("-")) return undefined;
      operands.push(word);
    }
    const listFiles = args.includes("--files");
    if (!listFiles && !explicitPattern && !operands.length) return undefined;
    const paths = operands.slice(listFiles || explicitPattern ? 0 : 1);
    return { noun: files ? "path" : "match line", scope: paths.map(unquote).join(" ") || "." };
  }
  return undefined;
}

const devopsPrograms = new Set([
  "docker", "docker-compose", "ansible", "ansible-playbook", "ansible-inventory", "terraform", "tofu",
  "kubectl", "helm", "talosctl", "top", "htop", "free", "df", "ss", "journalctl",
]);
const groupedOptions = new Set([
  "--context", "--namespace", "--kubeconfig", "--nodes", "--endpoints", "--selector", "--output",
  "--inventory", "--limit", "--project-name", "--file", "--unit", "--since", "--until", "-n", "-o", "-f", "-i", "-u",
]);

function shellProgram(command: string): string | undefined {
  const word = /^[ \t]*(?:sudo[ \t]+)?([\w./-]+)(?=[ \t]|\\\r?\n|$)/.exec(command.trimEnd())?.[1];
  return word && basename(word);
}

function simpleShellWords(command: string): string[] | undefined {
  // Preserve shell spelling without evaluating expansions or interpreting compound commands.
  const gap = /(?:[ \t]+|\\\r?\n)*/y;
  const word = /(?:[^\s'"\\|;&<>()`#]+|'[^']*'|"(?:[^"\\`$]|\$(?!\()|\\[^\r\n])*"|\\[^\r\n])+/y;
  const words: string[] = [];
  let index = 0;
  while (index < command.length) {
    gap.lastIndex = index;
    gap.exec(command);
    if (gap.lastIndex === command.length) break;
    if (words.length && gap.lastIndex === index) return undefined;
    word.lastIndex = gap.lastIndex;
    const token = word.exec(command);
    if (!token) return undefined;
    words.push(token[0]);
    index = word.lastIndex;
  }
  return words;
}

type ShellLink = ";" | "&&" | "||" | "|" | "|&";
type ShellStep = { link: ShellLink; words: string[]; redirected: boolean };
type BashPreview = { steps: { link: ShellLink; text: string; head: string }[]; badges: string[] };

const compoundShellWords = /^(?:\{|\}|!|\[\[|\]\]|if|then|elif|else|fi|for|while|until|select|case|esac|do|done|function|coproc|time)$/;

function scanShellSteps(source: string): { steps: ShellStep[]; heredoc: boolean } | undefined {
  // This is a display-only lexer, not a shell parser. Unsupported syntax keeps the original preview.
  const space = /(?:[ \t\r]|\\\r?\n)+/y;
  const word = /(?:[^\s'"\\|;&<>()\x60$]+|\$\{[A-Za-z_]\w*\}|\$(?![({\[])|'[^']*'|"(?:[^"\\\x60$]|\$\{[A-Za-z_]\w*\}|\$(?![({\[])|\\[\s\S])*"|\\(?:\r?\n|[^\r\n]))+/y;
  const operator = /&&|\|\||\|&|[;|]/y;
  const redirect = /(?:&>>?|[0-9]*(?:<<<|<<-|<<|<&|<>|>>|>&|>\||[<>]))/y;
  const eat = (pattern: RegExp, at: number) => {
    pattern.lastIndex = at;
    return pattern.exec(source)?.[0];
  };
  const steps: ShellStep[] = [];
  let current: ShellStep = { link: ";", words: [], redirected: false };
  const docs: { delimiter: string; stripTabs: boolean; quoted: boolean }[] = [];
  let heredoc = false;
  const end = (link: ShellLink) => {
    steps.push(current);
    current = { link, words: [], redirected: false };
  };
  let i = 0;
  while (i < source.length) {
    const whitespace = eat(space, i);
    if (whitespace) { i += whitespace.length; continue; }
    if (source[i] === "#") {
      const newline = source.indexOf("\n", i);
      i = newline < 0 ? source.length : newline;
      continue;
    }
    if (source[i] === "\n") {
      if (current.redirected && !current.words.length) return;
      if (current.words.length) end(";");
      i++;
      for (const { delimiter, stripTabs, quoted } of docs) {
        let closed = false;
        while (i < source.length) {
          const newline = source.indexOf("\n", i);
          const next = newline < 0 ? source.length : newline;
          const line = source.slice(i, next);
          i = next + 1;
          // In an unquoted heredoc, a line continuation can join a would-be closing delimiter.
          if (!quoted && /(?:^|[^\\])(?:\\\\)*\\$/.test(line)) return;
          if ((stripTabs ? line.replace(/^\t+/, "") : line) === delimiter) { closed = true; break; }
        }
        if (!closed) return;
      }
      docs.length = 0;
      continue;
    }
    const sep = eat(operator, i) as ShellLink | undefined;
    if (sep) {
      if (!current.words.length) return;
      end(sep);
      i += sep.length;
      continue;
    }
    const op = eat(redirect, i);
    if (op) {
      i += op.length;
      i += eat(space, i)?.length ?? 0;
      const target = source[i] !== "#" && eat(word, i);
      if (!target) return;
      i += target.length;
      current.redirected = true;
      if (/(?:^|\d)<<-?$/.test(op)) {
        const marker = /^(['"]?)([\w-]+)\1$/.exec(target);
        if (!marker) return;
        docs.push({ delimiter: marker[2], stripTabs: op.endsWith("-"), quoted: Boolean(marker[1]) });
        heredoc = true;
      } else {
        if (/[&]$/.test(op)) current.words.push(op + target);
        else current.words.push(op, target);
      }
      continue;
    }
    const token = eat(word, i);
    if (!token) return;
    // A continued word can include the file descriptor for the following redirect.
    if (/\\\r?\n/.test(token) && /[<>]/.test(source[i + token.length] ?? "")) return;
    current.words.push(token);
    i += token.length;
  }
  if (current.words.length) end(";");
  if (docs.length || current.link !== ";" || !steps.length) return;
  for (const { words } of steps) {
    const program = words.find(token => !shellAssignment.test(token));
    if (!words.length || program && compoundShellWords.test(program)) return;
  }
  return { steps, heredoc };
}

const shellAssignment = /^([A-Za-z_]\w*)=(.*)$/s;
const shellLiteral = (word: string): string | undefined => /^'[^']*'$/.test(word) || /^"[^"$\\\x60]*"$/.test(word)
  ? word.slice(1, -1) : /^[\w./:@%,+= -]+$/.test(word) && !word.includes(" ") ? word : undefined;

function shellDisplayWord(word: string, vars?: Map<string, string>): string {
  const reference = /^"\$(?:([A-Za-z_]\w*)|\{([A-Za-z_]\w*)\})(\/[\w./-]*)?"$/.exec(word);
  const value = reference && vars?.get(reference[1] ?? reference[2]);
  const literal = value !== undefined && value !== null ? value + (reference?.[3] ?? "") : shellLiteral(word);
  if (literal && /^(?:\/|\.\.?\/)/.test(literal) && visibleWidth(literal) > 36) {
    const path = shortenPath(literal, "", 0, 32).replace(/^…[^/]*\//, "…/");
    return word.startsWith('"') || word.startsWith("'") ? word[0] + path + word[0] : path;
  }
  return word.replace(/\\\r?\n/g, "").replace(/\s*\r?\n\s*/g, " ");
}

function shellSetup(words: string[]): boolean {
  if (words[0] !== "set" || words.length < 2) return false;
  for (let i = 1; i < words.length; i++) {
    if (/^[+-][eEufx]+$/.test(words[i])) continue;
    if (!/^[+-][eEufx]*o$/.test(words[i]) || words[++i] !== "pipefail") return false;
  }
  return true;
}

function bashPreview(command: string): BashPreview | undefined {
  const parsed = scanShellSteps(command);
  if (!parsed) return;
  const { steps, heredoc } = parsed;
  const vars = new Map<string, string>();
  let i = 0, cwd = "", setup = false, env = false, guarded = false;
  for (; i + 1 < steps.length; i++) {
    const { words, link, redirected } = steps[i];
    const next = steps[i + 1].link;
    if (redirected || ![";", "&&"].includes(link) || ![";", "&&"].includes(next)) break;
    // A single badge cannot describe a fallback or a later unconditional command.
    if (next === "&&" && steps.slice(i + 2).some(step => step.link === "||" || step.link === ";")) break;
    const assignments = words.map(word => shellAssignment.exec(word));
    if (assignments.every(Boolean)) {
      for (const match of assignments) {
        const value = shellLiteral(match![2]);
        if (value === undefined) vars.delete(match![1]);
        else vars.set(match![1], value);
      }
      env = true;
    } else if (shellSetup(words)) {
      setup = true;
    } else if (words[0] === "cd" && words.length === 2 && !words[1].startsWith("-") && shellLiteral(words[1])) {
      cwd = shellDisplayWord(words[1], vars);
    } else if (next === "&&" && (words[0] === "test" || words[0] === "[" && words.at(-1) === "]")) {
      guarded = true;
    } else {
      break;
    }
    guarded ||= next === "&&";
  }
  let shortened = false;
  const summarized = steps.slice(i).map(({ words, link }, index) => {
    let start = 0;
    if (index === 0) {
      start = words.findIndex(word => !shellAssignment.test(word));
      if (start > 0) env = true;
      else start = 0;
    }
    const display = words.slice(start).map(word => {
      const text = shellDisplayWord(word, index === 0 ? vars : undefined);
      shortened ||= text !== word;
      return text;
    });
    const path = display.findIndex(word => /^['"]?…\//.test(word));
    return { link, text: display.join(" "), head: display.slice(0, path < 0 ? 1 : path + 1).join(" ") };
  });
  const badges = [guarded && "guarded", cwd && "cwd " + cwd, heredoc && "heredoc", env && "env", setup && !cwd && "setup"].filter((item): item is string => Boolean(item));
  if (summarized.length === 1 && !badges.length && !shortened && !command.includes("\n")) return;
  return { steps: summarized, badges };
}

function bashPreviewLine(preview: BashPreview, width: number): string {
  const [first, second] = preview.steps;
  const link = second?.link === ";" ? " ; " : " " + second?.link + " ";
  const guarded = preview.badges.includes("guarded") ? width >= 22 ? " · guarded" : " · ?" : "";
  const essential = (n: number) => (preview.steps.length > n ? " · +" + (preview.steps.length - n) : "") + guarded;
  const minimum = (step: typeof first) => Math.min(visibleWidth(step.text), Math.max(8, visibleWidth(step.head)));
  const pair = second && minimum(first) + minimum(second) + link.length + essential(2).length <= width;
  let badges = essential(pair ? 2 : 1);
  for (const badge of preview.badges) {
    if (badge === "guarded") continue;
    const next = badges + " · " + badge;
    if (visibleWidth(next) + minimum(first) + (pair ? minimum(second) + link.length : 0) <= width) badges = next;
  }
  const available = Math.max(0, width - visibleWidth(badges));
  if (!pair) return truncateToWidth(truncateToWidth(first.text, available) + badges, width);
  const room = available - link.length;
  const right = Math.min(visibleWidth(second.text), Math.max(minimum(second), Math.floor(room / 2)), room - minimum(first));
  const left = Math.min(visibleWidth(first.text), room - right);
  return truncateToWidth(first.text, left) + link + truncateToWidth(second.text, room - left) + badges;
}

function devopsCommandLines(words: string[], width: number): string[] {
  const lines: string[] = [];
  let line = "$";
  for (let i = 0; i < words.length; i++) {
    const word = words[i];
    const group = groupedOptions.has(word) && words[i + 1] && !words[i + 1].startsWith("-") ? `${word} ${words[++i]}` : word;
    if (visibleWidth(line + " " + group) > width && line !== "$") {
      lines.push(line);
      line = " ";
    }
    line += " " + group;
  }
  return [...lines, line];
}

function elapsedLabel(durationMs: number | undefined): string {
  return durationMs !== undefined && Number.isFinite(durationMs) && durationMs >= minToolTimingMs
    ? `${(durationMs / 1000).toFixed(1)} s` : "";
}

function mcpSummary(output: string, structured: unknown): string {
  let data = structured;
  if (data === undefined && /^[\[{]/.test(output.trimStart())) {
    try { data = JSON.parse(output); } catch { /* Unstructured text has no reliable count. */ }
  }
  const record = data as Record<string, unknown> | null | undefined;
  const items = Array.isArray(data) ? data : [record?.results, record?.items, record?.matches].find(Array.isArray);
  return Array.isArray(items) ? `${items.length} ${items.length === 1 ? "result" : "results"}` : "Done";
}

function knowledgeResponse(output: string, structured: unknown): Record<string, unknown> | undefined {
  const parse = (value: unknown): unknown => {
    if (typeof value !== "string") return value;
    try { return JSON.parse(value); } catch { return undefined; }
  };
  const data = parse(structured ?? output);
  if (!data || typeof data !== "object") return undefined;
  const record = data as Record<string, unknown>;
  const result = "result" in record ? parse(record.result) : record;
  return result && typeof result === "object" ? result as Record<string, unknown> : undefined;
}

type KnowledgeCard = { summary: string; fields: [string, string][] };

function knowledgeCard(action: string, data: Record<string, unknown> | undefined): KnowledgeCard | undefined {
  if (!data) return undefined;
  if (action === "propose_note" || action === "propose_edit") {
    if (typeof data.pr !== "string" || typeof data.path !== "string") return undefined;
    const number = /\/pull\/(\d+)\/?$/.exec(data.pr)?.[1];
    const state = data.new_pr === true ? "Opened" : data.new_pr === false ? "Updated" : "";
    const fields: KnowledgeCard["fields"] = [["Note", data.path], ["Pull request", data.pr]];
    if (typeof data.branch === "string") fields.push(["Branch", data.branch]);
    return { summary: `${state} PR${number ? ` #${number}` : ""}`.trim(), fields };
  }
  if (action === "list_proposals" && Array.isArray(data)) {
    const fields: KnowledgeCard["fields"] = [];
    for (const item of data) {
      if (typeof item?.topic !== "string" || typeof item.pr !== "string") return undefined;
      fields.push([item.topic, item.pr]);
    }
    return { summary: `${data.length} open ${data.length === 1 ? "PR" : "PRs"}`, fields };
  }
  if (action === "related") {
    const fields: KnowledgeCard["fields"] = [];
    let total = 0;
    for (const [key, label] of [["parents", "Parents"], ["children", "Children"], ["links_out", "Outgoing"], ["backlinks", "Backlinks"]]) {
      const items = data[key];
      if (!Array.isArray(items)) return undefined;
      const paths = items.map(item => item?.path ?? item?.name);
      if (!paths.every(path => typeof path === "string")) return undefined;
      total += items.length;
      if (paths.length) fields.push([label, paths.join("\n")]);
    }
    return { summary: `${total} ${total === 1 ? "relation" : "relations"}`, fields };
  }
  if (action === "status" && typeof data.notes === "number") {
    const fields: KnowledgeCard["fields"] = [];
    for (const [key, label] of [["notes", "Notes"], ["chunks", "Chunks"], ["edges", "Edges"], ["unresolved_links", "Unresolved links"], ["multi_parent_notes", "Multi-parent notes"], ["last_sync", "Last sync"]]) {
      const value = data[key];
      if (typeof value === "number" || typeof value === "string") fields.push([label, String(value)]);
    }
    if (Array.isArray(data.parent_cycles)) fields.push(["Parent cycles", data.parent_cycles.length ? JSON.stringify(data.parent_cycles) : "None"]);
    return { summary: `${data.notes} ${data.notes === 1 ? "note" : "notes"}`, fields };
  }
  return undefined;
}

const services = new Map([["tool_search", "find tools"], ["list_mcp_resources", "list resources"], ["list_mcp_resource_templates", "list templates"], ["read_mcp_resource", "read resource"]]);

function serviceItems(tool: string, result: { content: readonly { type: string; text?: string }[]; details?: unknown; structuredContent?: unknown }) {
  let data = result.structuredContent as Record<string, unknown> | undefined;
  if (!data && tool.startsWith("list_") && result.content[0]?.type === "text") {
    try { data = JSON.parse(result.content[0].text ?? ""); } catch { return undefined; }
  }
  const items = tool === "tool_search" ? (result.details as { loaded?: unknown })?.loaded : tool === "list_mcp_resources" ? data?.resources : tool === "read_mcp_resource" ? result.content : data?.resourceTemplates;
  if (!Array.isArray(items)) return undefined;
  const noun = tool === "tool_search" ? "tool" : tool === "list_mcp_resources" ? "resource" : tool === "read_mcp_resource" ? "part" : "template";
  const errors = Array.isArray(data?.errors) ? data.errors : [];
  return { items, errors, cursor: data?.nextCursor, summary: `${items.length} ${noun}${items.length === 1 ? "" : "s"}${errors.length ? ` · ${errors.length} failed` : ""}` };
}

function exaMatches(output: string) {
  if (!output.startsWith("Title: ")) return undefined;
  const hits = output.split(/\n---\n(?=\s*Title: )/).map(block => {
    const match = block.trim().match(/^Title: ([^\n]+)\nURL: (https?:\/\/[^\s]+)(?=\n|$)/);
    if (!match) return undefined;
    return { title: match[1], heading: match[2], snippet: block.match(/\nHighlights:\s*([\s\S]*)/)?.[1] };
  });
  return hits.every(hit => hit !== undefined) ? hits : undefined;
}

function searchExcerpt(snippet: string, knowledge: boolean): string {
  const lines = clean(snippet).split("\n")
    .filter(line => !/^\s*(?:[~`]{3}|(?:\*\s*){3,}$|(?:-\s*){3,}$|(?:_\s*){3,}$)/.test(line))
    .map(line => line.replace(/^\s*(?:>\s*)+/, "").replace(/^\s*#{1,6}\s+/, "")
      .replace(/\[([^\[\]\n]+)\]\([^\s)]+\)/g, "$1")
      .replace(/\*\*|__|`/g, "").trim())
    .filter(Boolean);
  const text = lines.join("\n");
  return knowledge ? text.replace(/(?<!\[)\[([\p{L}\p{N}_-]+)\](?!\])/gu, "$1") : text;
}

type FileScope = "project" | "tmp" | "external";
type PathScopeCache = { cwd: string; path: string; scope: FileScope };

function canonicalPath(path: string): string {
  // A write target may not exist yet, but an existing parent can still be a symlink.
  const suffix: string[] = [];
  for (;;) {
    try { return join(realpathSync(path), ...suffix.reverse()); } catch { /* Try the parent. */ }
    const parent = dirname(path);
    if (parent === path) return join(path, ...suffix.reverse());
    suffix.push(basename(path));
    path = parent;
  }
}

function within(root: string, path: string): boolean {
  const child = relative(root, path);
  return child !== ".." && !child.startsWith(`..${sep}`) && !isAbsolute(child);
}

const editPreviewLines = 12;
const highlightLimit = 16_000;

function highlighted(text: string, language: string | undefined, plain: (text: string) => string): string {
  return language && text.length <= highlightLimit ? highlightCode(text, language).join("\n") : plain(text);
}

function diffTokens(line: string): string[] {
  return line.match(/[\p{L}\p{M}\p{N}_$]+|\s+|[^\s]/gu) ?? [];
}

function changedTokens(before: string, after: string): [Set<number>, Set<number>] | undefined {
  if (before.length + after.length > highlightLimit) return undefined;
  const left = diffTokens(before), right = diffTokens(after);
  // Keep intraline comparison bounded for minified files and generated diffs.
  if (left.length > 128 || right.length > 128) return undefined;
  const lcs = Array.from({ length: left.length + 1 }, () => new Uint8Array(right.length + 1));
  for (let i = left.length - 1; i >= 0; i--) {
    for (let j = right.length - 1; j >= 0; j--) {
      lcs[i][j] = left[i] === right[j] ? 1 + lcs[i + 1][j + 1] : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
    }
  }
  const removed = new Set<number>(), added = new Set<number>();
  let i = 0, j = 0;
  while (i < left.length || j < right.length) {
    if (i < left.length && j < right.length && left[i] === right[j]) { i++; j++; }
    else if (i < left.length && (j === right.length || lcs[i + 1][j] >= lcs[i][j + 1])) removed.add(i++);
    else added.add(j++);
  }
  return [removed, added];
}

type DiffRow = { text: string; number?: string } | { sign: "+" | "-" | "~"; number: string; code: string; changed?: Set<number> };

function prepareDiff(diff: string) {
  const lines = diff.split("\n");
  const parsed = lines.map(line => /^([+\-])([ \t]*\d+[ \t])(.*)$/.exec(line));
  const fragments = new Map<number, Set<number>>();
  const inlineInsertions = new Set<number>();
  const hidden = new Set<number>();
  for (let i = 0; i < lines.length;) {
    if (parsed[i]?.[1] !== "-") { i++; continue; }
    const start = i;
    while (parsed[i]?.[1] === "-") i++;
    const added = i;
    while (parsed[i]?.[1] === "+") i++;
    if (added - start !== i - added) continue;
    for (let offset = 0; offset < added - start; offset++) {
      const oldIndex = start + offset, newIndex = added + offset;
      const pair = changedTokens(parsed[oldIndex]![3], parsed[newIndex]![3]);
      if (pair) {
        fragments.set(oldIndex, pair[0]);
        fragments.set(newIndex, pair[1]);
        if (pair[0].size === 0 && pair[1].size > 0) {
          hidden.add(oldIndex);
          inlineInsertions.add(newIndex);
        }
      }
    }
  }
  const keep = new Set<number>();
  for (let i = 0; i < lines.length; i++) {
    if (!parsed[i]) continue;
    for (const direction of [-1, 1]) {
      for (let offset = 1; offset <= 2; offset++) {
        const j = i + direction * offset;
        if (!/^ [ \t]*\d+[ \t]/.test(lines[j] ?? "")) break;
        keep.add(j);
      }
    }
  }
  const rows: DiffRow[] = [];
  const stats = { added: 0, removed: 0, modified: 0 };
  let gap = false;
  for (let i = 0; i < lines.length; i++) {
    if (hidden.has(i)) continue;
    const match = parsed[i];
    if (!match && !keep.has(i)) { gap = rows.length > 0; continue; }
    if (gap) { rows.push({ text: " …" }); gap = false; }
    if (!match) {
      const [, number, text] = /^ [ \t]*(\d+)[ \t](.*)$/.exec(lines[i])!;
      rows.push({ number, text });
      continue;
    }
    const [, marker, number, code] = match;
    const sign = inlineInsertions.has(i) ? "~" : marker === "+" ? "+" : "-";
    stats[sign === "~" ? "modified" : sign === "+" ? "added" : "removed"]++;
    rows.push({ sign, number: number.trim(), code, changed: fragments.get(i) });
  }
  return { diff, rows, stats };
}

type PreparedDiff = ReturnType<typeof prepareDiff>;
type DeltaRow = { number?: string; kind: string; text: string };
type DeltaOutput = { full: DeltaRow[]; preview: DeltaRow[]; digits: number };
type DeltaView = { patch: string; appearance: Theme["appearance"]; visible: boolean; output?: DeltaOutput };

function previewDelta(lines: DeltaRow[]): DeltaRow[] {
  const kinds = lines.map(row => row.kind);
  const keep = new Set<number>();
  for (let i = 0; i < lines.length; i++) {
    if (kinds[i] !== "+" && kinds[i] !== "-") continue;
    keep.add(i);
    for (const direction of [-1, 1]) {
      for (let offset = 1; offset <= 2; offset++) {
        const j = i + direction * offset;
        if (kinds[j] !== " ") break;
        keep.add(j);
      }
    }
  }
  if (!keep.size) return lines;
  const rows: DeltaRow[] = [];
  let last = -1;
  for (let i = 0; i < lines.length; i++) {
    if (!keep.has(i)) continue;
    if (last >= 0 && i > last + 1) rows.push({ kind: "", text: "…" });
    rows.push(lines[i]);
    last = i;
  }
  const extra = rows.length - editPreviewLines;
  return extra > 0 ? [...rows.slice(0, editPreviewLines), { kind: "", text: `… ${extra} more lines` }] : rows;
}

const diffPalette = {
  light: {
    add: { bg: "#e7eccf", emphasis: "#cedd9e", text: "#445812", number: "#425b16" },
    remove: { bg: "#f2dfce", emphasis: "#e6b49a", text: "#733d24", number: "#962e24" },
  },
  dark: {
    add: { bg: "#243321", emphasis: "#40572a", text: "#a6b58b", number: "#acca79" },
    remove: { bg: "#392620", emphasis: "#65372a", text: "#c69e89", number: "#ef9b8b" },
  },
};

function renderDelta(patch: string, cwd: string, appearance: Theme["appearance"]): Promise<DeltaOutput | undefined> {
  const { add, remove } = diffPalette[appearance];
  return new Promise(done => {
    const child = execFile("delta", [
      "--no-gitconfig", "--paging=never", "--true-color=always", `--${appearance}`,
      "--file-style=omit", "--hunk-header-style=omit", "--keep-plus-minus-markers",
      "--syntax-theme=none", "--zero-style=normal", "--line-numbers",
      "--line-numbers-left-format={nm}|", "--line-numbers-right-format={np}|",
      `--plus-style="${add.text}" "${add.bg}"`, `--plus-emph-style="${add.text}" "${add.emphasis}"`,
      `--minus-style="${remove.text}" "${remove.bg}"`, `--minus-emph-style="${remove.text}" "${remove.emphasis}"`,
    ], {
      cwd, encoding: "utf8", timeout: 2_000, maxBuffer: 1024 * 1024,
    }, (error, output) => {
      if (error || !output.trim()) { done(undefined); return; }
      // Keep color attributes, not cursor movement or erase-to-end commands.
      const lines = output.trimEnd().split(/(\x1b\[[0-9;:]*m)/).map((part, i) => i % 2 ? part : clean(part)).join("")
        .replace(/^\n+/, "").split("\n");
      const full: DeltaRow[] = lines.map(line => {
        const [left, right] = line.split("|", 2);
        if (right === undefined) return { kind: "", text: stripVTControlCharacters(line) };
        const text = line.slice(left.length + right.length + 2).replace(/^\x1b\[0m/, "");
        const kind = stripVTControlCharacters(text)[0];
        return { number: stripVTControlCharacters(kind === "-" ? left : right).trim(), kind,
          text: text.replace(/^((?:\x1b\[[0-9;:]*m)*)([+-])/, "$1$2 ") };
      });
      done({ full, preview: previewDelta(full), digits: full.reduce((max, row) => Math.max(max, row.number?.length ?? 0), 0) });
    });
    child.stdin?.on("error", () => {});
    child.stdin?.end(clean(patch));
  });
}

function quietMetadata(theme: Theme, text: string, expanded = false): string {
  return theme.style(text, {
    fg: theme.appearance === "light" ? mixColors(theme.colors.borderMuted,
      expanded ? expandedBackgrounds.light : lightTimingBackground, expanded ? 0.12 : 0.20, "srgb") : rgbColor(89, 102, 106),
    dim: !expanded && theme.appearance === "light",
  });
}

function diffNumber(number: string, digits: number, kind: string, theme: Theme, expanded: boolean): string {
  const label = number.padStart(digits) + " ";
  if (kind === " ") return quietMetadata(theme, label, expanded);
  const palette = diffPalette[theme.appearance][kind === "-" ? "remove" : "add"];
  return theme.style(label, { fg: parseColor(palette.number), bg: parseColor(palette.bg) });
}

function quietDiff(rows: DiffRow[], digits: number, theme: Theme, expanded: boolean): string {
  return rows.map(row => {
    if ("text" in row) {
      const prefix = row.number ? diffNumber(row.number, digits, " ", theme, expanded) + "  " : "";
      return prefix + (row.number ? theme.fg("toolDiffContext", row.text) : quietMetadata(theme, row.text, expanded));
    }
    const { sign, code, changed } = row;
    const color = sign === "-" ? "toolDiffRemoved" : "toolDiffAdded";
    const palette = diffPalette[theme.appearance][sign === "-" ? "remove" : "add"];
    const text = changed ? diffTokens(code).map((part, index) => changed.has(index) ? theme.fg(color, part) : part).join("") : code;
    return diffNumber(row.number, digits, sign, theme, expanded)
      + theme.style(theme.fg(sign === "~" ? "warning" : color, sign) + " " + text, { bg: parseColor(palette.bg) });
  }).join("\n");
}

function indentedLines(text: string, padding: string, width: number): string[] {
  const indent = padding + " ";
  return new Text(text, 0, 0).render(Math.max(1, width - indent.length))
    .map(row => truncateToWidth(indent + row, width));
}

type CodemodeCall = CodemodeToolDetails["calls"][number];
type BashInput = { command: string; summary?: BashPreview | null; argsHead?: string };

function bashInput(command: string, args?: Record<string, unknown>): BashInput {
  return { command: clean(command).replace(/[\x80-\x9f]/g, ""), argsHead: args && JSON.stringify(args).slice(0, 200) };
}

function storedBashPreview(input: BashInput): BashPreview | null {
  return input.summary === undefined ? input.summary = bashPreview(input.command) ?? null : input.summary;
}

function nestedBashInputs(calls: readonly CodemodeCall[], parentId: string, recorded?: Map<string, BashInput>): Map<CodemodeCall, BashInput> {
  const inputs = new Map<CodemodeCall, BashInput>();
  let slot = 0;
  for (const call of calls) {
    if (call.id.startsWith(parentId + "/models.")) continue;
    slot++;
    if (call.name !== "bash") continue;
    const candidate = call.id === parentId + "/?" ? recorded?.get(parentId + "/" + slot) : undefined;
    const preview = call.args.endsWith("...") ? call.args.slice(0, -3) : call.args;
    // Pi assigns native child IDs in dispatch order, before event handlers can reorder delivery.
    const pending = preview && candidate?.argsHead?.startsWith(preview) ? candidate : undefined;
    const known = recorded?.get(call.id) ?? pending;
    if (known) { inputs.set(call, known); continue; }
    try {
      const command = JSON.parse(call.args)?.command;
      if (typeof command === "string") inputs.set(call, bashInput(command));
    } catch { /* A truncated preview is not a complete shell command. */ }
  }
  return inputs;
}

function codemodeLabel(name: string): string {
  if (name === "codex_web_search") return "search · codex";
  const mcp = /^mcp__(.+?)__(.+)$/.exec(name);
  return mcp ? `${mcp[2].replaceAll("_", " ")} · ${mcp[1]}` : name;
}

const codemodeTargetKeys = ["path", "file_path", "command", "query", "text", "title", "url", "pattern", "uri", "server"];

function codemodeTarget(call: CodemodeCall, expanded: boolean): string {
  if (!call.args.startsWith("{")) return clean(call.args).replace(/[\x80-\x9f]/g, ""); // Model calls carry a provider/model ID instead of JSON.
  let args: Record<string, unknown>;
  try { args = JSON.parse(call.args); } catch {
    // Pi can cut the JSON preview in the middle of an escape. Keep only complete characters in the first field.
    const head = call.args.endsWith("...") ? call.args.slice(0, -3) : call.args;
    const first = /^\{"([^"\\]+)":("(?:[^"\\\u0000-\u001f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*)(")?/.exec(head);
    args = first ? { [first[1]]: JSON.parse(first[2] + '"') + (first[3] ? "" : "...") } : {};
  }
  const target = codemodeTargetKeys.map(key => args[key]).find(value => typeof value === "string")
    ?? (Array.isArray(args.urls) ? args.urls[0] : undefined);
  if (typeof target !== "string") return "";
  const range = call.name === "read" ? formatReadLineRange(args.offset, args.limit) : "";
  if (call.name === "bash") return clean(expanded ? target : target.split("\n", 1)[0]).replace(/[\x80-\x9f]/g, "");
  return preview({ query: target }).replace(/[\x80-\x9f]/g, "") + range;
}

function codemodeProblem(call: CodemodeCall): boolean {
  return call.status === "error" || call.status === "cancelled";
}

function codemodeSummary(calls: readonly CodemodeCall[], partial: boolean, started: boolean, failed: boolean): string {
  const counts = new Map<string, number>();
  let errors = 0, cancelled = 0;
  for (const call of calls) {
    const label = clean(codemodeLabel(call.name));
    counts.set(label, (counts.get(label) ?? 0) + 1);
    if (call.status === "error") errors++;
    if (call.status === "cancelled") cancelled++;
  }
  const activity = calls.length ? [...counts].map(([label, count]) => `${count} ${label}`).join(", ")
    : partial ? started ? "Running script" : "Preparing script" : failed ? "" : "No tool calls";
  return [failed ? "Failed" : "", errors ? `${errors} failed` : "", cancelled ? `${cancelled} cancelled` : "", activity].filter(Boolean).join(" · ");
}

function codemodeCallLines(call: CodemodeCall, theme: Theme, padding: string, width: number, expanded: boolean, step: number | undefined, bash?: BashInput): string[] {
  const title = clean(codemodeLabel(call.name));
  const target = bash ? expanded ? bash.command : bash.command.split("\n", 1)[0] : codemodeTarget(call, expanded);
  const summary = bash && !expanded && storedBashPreview(bash);
  const status = call.status === "ok" ? theme.fg("success", "✓") : call.status === "error" ? theme.fg("error", "✗")
    : theme.fg(call.status === "cancelled" ? "muted" : "warning", call.status === "cancelled" ? "⊘" : "…");
  const time = elapsedLabel(call.durationMs);
  const cost = call.cost ? `$${call.cost >= 0.01 ? call.cost.toFixed(2) : call.cost.toPrecision(2)}` : "";
  const meta = [time, cost].filter(Boolean).join(" · ");
  const prefix = padding + " " + status + " ";
  const prefixWidth = visibleWidth(prefix);
  const room = Math.max(1, width - prefixWidth);
  const suffix = meta && room > visibleWidth(title) + meta.length ? quietMetadata(theme, " " + meta, expanded) : "";
  const limit = Math.max(1, room - visibleWidth(suffix));
  const targetRoom = limit - visibleWidth(title) - 1;
  const display = summary ? bashPreviewLine(summary, Math.max(0, targetRoom))
    : !expanded && targetRoom > 0 && (call.name === "read" || call.name === "edit" || call.name === "write")
    ? shortenPath(target, "", 0, targetRoom) : target;
  const heading = theme.fg("toolTitle", theme.bold(title)) + (display ? theme.fg("toolOutput", " " + display) : "");
  const short = expanded ? heading : truncateToWidth(heading, limit);
  const text = call.status === "running" && step !== undefined ? runningPulse(short, theme, step, theme.appearance === "light") : short;
  const rows = expanded ? wrapTextWithAnsi(text, limit) : [text];
  rows[rows.length - 1] += suffix;
  const lines = rows.map((row, i) => truncateToWidth((i === 0 ? prefix : " ".repeat(prefixWidth)) + row, width));
  if (expanded && call.error) lines.push(...indentedLines(theme.fg("error", clean(call.error)), padding + "  ", width));
  return lines;
}

function shownCodemodeCalls(calls: readonly CodemodeCall[], live: boolean): readonly CodemodeCall[] {
  if (calls.length <= codemodePreviewRows) return calls;
  // Keep trouble and in-flight work visible, but preserve start order when drawing the selection.
  const prioritized = live ? [...calls.filter(codemodeProblem), ...calls.filter(call => call.status === "running"),
    ...calls.filter(call => call.status === "ok").reverse()] : calls;
  const shown = new Set(prioritized.slice(0, codemodePreviewRows));
  return calls.filter(call => shown.has(call));
}

function cacheLines(render: (width: number) => string[]) {
  let cached: { width: number; lines: string[] } | undefined;
  return {
    render(width: number) {
      if (cached?.width !== width) cached = { width, lines: render(width) };
      return cached.lines;
    },
    invalidate() { cached = undefined; },
  };
}

export default function compactTools(pi: ExtensionAPI) {
  const pending = new Map<string, () => void>();
  let timer: ReturnType<typeof setInterval> | undefined;
  let interactive = false;
  let active = false;
  let session = 0;
  let deltaQueue = Promise.resolve();
  const projectRoots = new Map<string, string>();
  const writeKinds = new Map<string, string>();
  const codemodeBash = new Map<string, Map<string, BashInput>>();
  const finishedRows = new Map<object, { width: number; lines: string[]; bytes: number }>();
  let finishedBytes = 0;
  const finishedBudget = 24 * 1024 * 1024;

  function discardRows(key: object) {
    const saved = finishedRows.get(key);
    if (!saved) return;
    finishedBytes -= saved.bytes;
    finishedRows.delete(key);
  }

  function finishedComponent(state: Record<string, unknown>, variant: string, inputs: unknown[], render: (width: number) => string[]) {
    const slots = (state.finishedRows ??= new Map<string, unknown[]>()) as Map<string, unknown[]>;
    const previous = slots.get(variant);
    const key = previous?.length === inputs.length && previous.every((value, i) => value === inputs[i]) ? previous : inputs;
    if (key !== previous) {
      if (previous) discardRows(previous);
      slots.set(variant, key);
    }
    const component = cacheLines(width => {
      const saved = finishedRows.get(key);
      if (saved?.width === width) {
        finishedRows.delete(key);
        finishedRows.set(key, saved);
        return saved.lines;
      }
      discardRows(key);
      const lines = render(width);
      const bytes = lines.reduce((sum, line) => sum + 32 + line.length * 2, 0) + 64;
      if (bytes <= finishedBudget) {
        while (finishedBytes + bytes > finishedBudget || finishedRows.size >= 4096) {
          discardRows(finishedRows.keys().next().value!);
        }
        finishedRows.set(key, { width, lines, bytes });
        finishedBytes += bytes;
      }
      return lines;
    });
    return { render: component.render, invalidate() { discardRows(key); component.invalidate(); } };
  }

  function clearFinishedRows() {
    finishedRows.clear();
    finishedBytes = 0;
  }
  const tempRoots = [tmpdir(), "/tmp", "/var/tmp"].map(path => canonicalPath(resolve(path)));

  function fileScope(toolName: string, args: Record<string, unknown> | undefined, cwd: string, state: Record<string, unknown>): FileScope | undefined {
    if (toolName !== "read" && toolName !== "write" && toolName !== "edit") return undefined;
    const path = args?.path ?? args?.file_path;
    if (typeof path !== "string" || !path) return undefined;
    const cached = state.pathScope as PathScopeCache | undefined;
    if (cached?.path === path && cached.cwd === cwd) return cached.scope;
    let root = projectRoots.get(cwd);
    if (root === undefined) {
      root = canonicalPath(resolve(cwd));
      for (let dir = root; ; dir = dirname(dir)) {
        if (existsSync(join(dir, ".git"))) { root = dir; break; }
        if (dirname(dir) === dir) break;
      }
      projectRoots.set(cwd, root);
    }
    const target = resolveToolPath(path, cwd);
    if (!target) return undefined;
    const absolute = canonicalPath(target);
    const scope = within(root, absolute) ? "project" : tempRoots.some(dir => within(dir, absolute)) ? "tmp" : "external";
    state.pathScope = { cwd, path, scope } satisfies PathScopeCache;
    return scope;
  }

  function stop() {
    if (timer) clearInterval(timer);
    timer = undefined;
    pending.clear();
  }

  let paneHidden = false;
  let unsubscribe: (() => void)[] = [];
  const invalidatePending = () => { for (const invalidate of pending.values()) invalidate(); };
  pi.on("session_start", (_event, ctx) => {
    for (const off of unsubscribe) off();
    paneHidden = false;
    unsubscribe = [
      pi.events.on("dotfiles:pane-hidden", value => { paneHidden = value === true; }),
      pi.events.on("dotfiles:animation-tick", invalidatePending),
    ];
    stop();
    active = false;
    projectRoots.clear();
    writeKinds.clear();
    clearFinishedRows();
    codemodeBash.clear();
    interactive = ctx.mode === "tui";
    if (interactive) {
      for (const entry of ctx.sessionManager.getEntries()) {
        if (entry.type !== "message" || entry.message.role !== "toolResult" || entry.message.toolName !== "codemode") continue;
        const inputs = new Map<string, BashInput>();
        for (const call of entry.message.nestedCalls?.calls ?? []) {
          const command = call.arguments?.command;
          if (call.name === "bash" && typeof command === "string") inputs.set(call.id, bashInput(command, call.arguments));
        }
        if (inputs.size) codemodeBash.set(entry.message.toolCallId, inputs);
      }
    }
    session++;
  });
  pi.on("tool_call", (event, ctx) => {
    if (!interactive || !isToolCallEventType("write", event)) return;
    const target = resolveToolPath(event.input.path, ctx.cwd);
    if (target) writeKinds.set(event.toolCallId, existsSync(target) ? "Overwritten" : "New file");
  });
  pi.on("agent_start", () => { active = true; });
  pi.on("agent_end", () => {
    active = false;
    stop();
  });
  pi.on("session_shutdown", () => {
    for (const off of unsubscribe) off();
    unsubscribe = [];
    clearFinishedRows();
    codemodeBash.clear();
    interactive = false;
    active = false;
    stop();
  });
  pi.on("tool_execution_start", event => {
    if (!interactive) return;
    if (event.toolName === "codemode" && !event.parentToolCallId) {
      codemodeBash.set(event.toolCallId, new Map());
    } else if (event.toolName === "bash" && event.parentToolCallId && typeof event.args?.command === "string") {
      const inputs = codemodeBash.get(event.parentToolCallId);
      if (!inputs) return;
      inputs.set(event.toolCallId, bashInput(event.args.command, event.args));
      pending.get(event.parentToolCallId)?.();
    }
  });
  pi.on("tool_execution_end", event => {
    pending.delete(event.toolCallId);
    if (pending.size === 0) stop();
  });

  // Only rendering changes; tool definitions, execution and model-facing results stay intact.
  pi.registerToolRenderer(toolName => {
    const mcp = toolName.startsWith("mcp__");
    const [server, action] = mcp ? toolName.slice(5).split(/__(.*)/, 2) : [];
    const list = listTools.has(toolName);
    const codemode = toolName === "codemode";
    const bash = toolName === "bash";
    const fileCall = toolName === "read" || toolName === "edit" || toolName === "write";
    const knowledge = server === "knowledge" && (action === "search" || action === "read");
    const exa = server === "exa" && (action === "web_search_exa" || action === "web_fetch_exa");
    const searchMcp = action === "search" || action === "web_search_exa";
    const proposal = server === "knowledge" && (action === "propose_note" || action === "propose_edit");
    const cardTool = proposal || (server === "knowledge" && ["list_proposals", "related", "status"].includes(action));
    const service = services.get(toolName);
    const friendlyMcp = knowledge || exa || cardTool || service;
    const matchesFor = (output: string, structured: unknown) => knowledge
      ? knowledgeResponse(output, structured)?.results : exaMatches(output);
    const renderers: ToolRenderers = {
      renderShell: "self",
      renderCall(args, theme, context) {
        const expanded = context.expanded;
        const running = context.isPartial && context.executionStarted && interactive && active;
        if (running) {
          context.state.pulseStartedAt ??= Date.now();
          pending.set(context.toolCallId, context.invalidate);
          timer ??= setInterval(() => {
            if (!paneHidden) invalidatePending();
          }, pulseInterval);
          timer.unref();
        } else {
          pending.delete(context.toolCallId);
          if (pending.size === 0) stop();
        }

        const liveMs = running ? Math.max(0, Date.now() - (context.state.pulseStartedAt as number)) : 0;
        const pulseStep = Math.floor(liveMs / pulseInterval);
        const scope = fileScope(toolName, args, context.cwd, context.state);
        const quiet = scope === "tmp" && !context.isError;
        const pathColor = scope === "project" ? "accent" : scope === "external" ? "warning" : scope === "tmp" ? "muted" : "toolOutput";
        const pathMarker = scope === "tmp" || scope === "external" ? `[${scope}] ` : "";
        const prepared = context.state.preparedDiff as PreparedDiff | undefined;
        const delta = context.state.deltaView as DeltaView | undefined;
        const deltaOutput = delta?.appearance === theme.appearance ? delta.output : undefined;
        const compactStats = toolName === "edit" && !context.isPartial && !context.isError ? prepared?.stats : undefined;
        const stats = deltaOutput && compactStats ? {
          added: compactStats.added + compactStats.modified,
          removed: compactStats.removed + compactStats.modified,
          modified: 0,
        } : compactStats;
        const label = service ? service : exa ? `${searchMcp ? "search" : "fetch"} · exa`
          : clean(action ? `${action.replaceAll("_", " ")} · ${server}` : toolName);
        const target = action === "propose_note" && proposal ? args?.title
          : cardTool ? args?.path : knowledge ? searchMcp ? args?.text : args?.path : args?.query;
        const urls = exa && !searchMcp && Array.isArray(args?.urls) ? args.urls : [];
        const argsPreview = service ? clean([args?.query, args?.server, args?.uri].filter(x => typeof x === "string").join(" · ") || (toolName.startsWith("list_") ? "all servers" : "")).replace(/\s+/g, " ") : friendlyMcp
          ? searchMcp && typeof target === "string" ? preview({ query: JSON.stringify(target) })
            : cardTool && typeof target === "string" ? clean(proposal && action === "propose_note" ? target : basename(target, ".md")).replace(/\s+/g, " ")
            : knowledge && typeof target === "string"
              ? clean(basename(target, ".md") + (typeof args?.heading === "string" ? ` › ${args.heading}` : "")).replace(/\s+/g, " ")
              : typeof urls[0] === "string" ? clean(urls[0]) + (urls.length > 1 ? ` +${urls.length - 1}` : "") : ""
          : bash || codemode || mcp ? "" : toolName === "ls"
          ? preview({ path: args?.path ?? "." }) : list
            ? [args?.pattern, args?.path ?? "."].filter(value => typeof value === "string").map(value => preview({ path: value })).join(" · ")
            : preview(args ?? {});
        const readRange = toolName === "read" && typeof args?.path === "string" && argsPreview
          ? formatReadLineRange(args.offset, args.limit) : "";
        const outcome = !context.isPartial && !context.isError
          ? toolName === "write" ? writeKinds.get(context.toolCallId) ?? "Written" : context.state.outcome as string | undefined
          : undefined;
        const padding = " ".repeat(context.outputPad);
        const rawCommand = bash && typeof args?.command === "string" ? args.command : "";
        let shell = context.state.bashInput as { raw: string; input: BashInput } | undefined;
        if (bash && shell?.raw !== rawCommand) {
          shell = { raw: rawCommand, input: bashInput(rawCommand) };
          context.state.bashInput = shell;
        }
        const command = shell?.input.command ?? "";
        const complete = context.argsComplete || context.executionStarted || !context.isPartial;
        const program = bash ? shellProgram(command) : undefined;
        const devops = !expanded && complete && program && devopsPrograms.has(program) ? simpleShellWords(command.trimEnd()) : undefined;
        const shellSummary = !expanded && complete && shell && !devops ? storedBashPreview(shell.input) : undefined;
        const timing = elapsedLabel(context.isPartial ? liveMs : context.durationMs);
        const status = toolName === "bash" && context.isError && !context.isPartial ? "Failed" : undefined;
        const metadata = [status ?? (friendlyMcp ? outcome : undefined), timing].filter(Boolean).join(" · ");
        const timeout = toolName === "bash" && typeof args?.timeout === "number" && Number.isFinite(args.timeout) && args.timeout > 0
          ? ` (timeout ${args.timeout} s)` : "";
        const argumentsText = expanded && !codemode && !list && !friendlyMcp && !["bash", "edit", "read"].includes(toolName)
          ? clean(JSON.stringify(args ?? {}, null, 2)) : "";
        const render = (width: number) => {
          const available = width - timingInset;
          const meta = metadata && available >= 16 ? quietMetadata(theme, truncateToWidth(metadata, Math.floor(available * 0.5)), expanded) : "";
          const compactWidth = Math.max(1, Math.floor(width * 0.7));
          const titleWidth = meta ? Math.min(compactWidth, available - visibleWidth(meta) - 1) : expanded ? width : compactWidth;
          const animate = (text: string) => running ? runningPulse(text, theme, pulseStep, codemode && theme.appearance === "light") : text;
          const withMeta = (left: string) => meta ? left + " ".repeat(Math.max(1, available - visibleWidth(left) - visibleWidth(meta)))
            + meta + " ".repeat(timingInset) : left;
          const withLastMeta = (rows: string[]) => {
            if (meta) {
              const last = rows.length - 1;
              if (visibleWidth(rows[last]) + visibleWidth(meta) < available) rows[last] = withMeta(rows[last]);
              else rows.push(withMeta(""));
            }
            return rows;
          };
          const paint = (rows: string[]) => expandedRows(rows, expanded, width, theme);
          if (codemode) {
            // The result slot receives the runtime snapshot before this component draws its first frame.
            const calls = context.state.codemodeCalls as CodemodeCall[] | undefined;
            const summary = codemodeSummary(calls ?? [], context.isPartial, context.executionStarted, context.isError);
            const title = padding + theme.fg(context.isError ? "error" : "toolOutput", theme.bold("codemode"));
            const room = titleWidth - visibleWidth(title) - 1;
            const text = room > 2 ? " " + animate(truncateToWidth(theme.fg("toolOutput", `· ${summary}`), room)) : "";
            return paint([truncateToWidth(withMeta(title + text), width)]);
          }
          if (devops) {
            const title = theme.fg(context.isError ? "error" : "accent", theme.bold("DEVOPS"));
            const header = truncateToWidth(withMeta(padding + truncateToWidth(animate(title + timeout), Math.max(0, titleWidth - padding.length))), width);
            const lines = devopsCommandLines(devops.map(word => shellDisplayWord(word)), Math.max(1, width - padding.length - 1));
            const script = highlighted(lines.join("\n"), "bash", text => theme.fg("toolOutput", text));
            return [header, ...indentedLines(script, padding, width)];
          }
          if (bash) {
            const lines = command.split("\n");
            const source = expanded ? command : lines[0];
            const shell = !expanded ? theme.fg("toolOutput", source)
              : context.isError ? source.split("\n").map(line => theme.fg("error", line)).join("\n")
              : context.isPartial && !context.argsComplete ? source
              : highlighted(source, "bash", text => theme.fg("toolOutput", text));
            const [first, ...rest] = shell.split("\n");
            const title = source ? first : "…";
            const marker = "$";
            const prompt = (room: number) => room > padding.length + marker.length + 1
              ? theme.fg(expanded ? (context.isError ? "error" : "toolTitle") : "toolOutput", theme.bold(marker)) + " " : "";
            if (expanded) {
              const prefix = padding + prompt(width);
              const indent = padding + " ";
              const titleRoom = Math.max(1, width - Math.max(visibleWidth(prefix), indent.length));
              const firstRows = wrapTextWithAnsi(animate(title), titleRoom);
              const rows = firstRows.map((row, i) => (i === 0 ? prefix : indent) + row);
              if (rest.length) {
                for (const row of wrapTextWithAnsi(rest.join("\n"), Math.max(1, width - indent.length))) rows.push(indent + row);
              }
              if (timeout) {
                const last = rows.length - 1;
                if (visibleWidth(rows[last]) + visibleWidth(timeout) <= width) rows[last] += quietMetadata(theme, timeout, expanded);
                else rows.push(indent + quietMetadata(theme, timeout.trimStart(), expanded));
              }
              return paint(withLastMeta(rows).map(row => truncateToWidth(row, width)));
            }
            const limit = timeout && titleWidth - visibleWidth(timeout) >= 6 ? quietMetadata(theme, timeout) : "";
            const extra = !shellSummary && lines.length > 1 && titleWidth - visibleWidth(limit) >= 18
              ? " " + quietMetadata(theme, `+${lines.length - 1} lines`) : "";
            const search = outcome ? theme.fg("muted", ` · ${outcome}`) : "";
            const availableTitle = titleWidth - visibleWidth(limit) - visibleWidth(extra);
            const badge = availableTitle - visibleWidth(search) >= 12 ? search : "";
            const room = availableTitle - visibleWidth(badge);
            const prefix = padding + prompt(room);
            const commandRoom = Math.max(0, room - visibleWidth(prefix));
            const text = shellSummary ? theme.fg("toolOutput", bashPreviewLine(shellSummary, commandRoom)) : truncateToWidth(title, commandRoom);
            const header = prefix + animate(text) + limit + extra + badge;
            return paint([truncateToWidth(withMeta(header), width)]);
          }
          const prefix = quiet ? theme.fg("muted", label) : theme.fg(context.isError ? "error" : "toolTitle", theme.bold(label));
          const counts = stats ? [
            stats.added ? theme.fg(quiet ? "muted" : "success", `+${stats.added}`) : "",
            stats.removed ? theme.fg(quiet ? "muted" : "error", `−${stats.removed}`) : "",
            stats.modified ? theme.fg(quiet ? "muted" : "warning", `~${stats.modified}`) : "",
          ].filter(Boolean).join(" ") : "";
          const badge = outcome && !friendlyMcp ? theme.fg("muted", ` · ${outcome}`) : "";
          const title = padding + prefix;
          const compactPath = !expanded && fileCall && argsPreview;
          const minPathWidth = compactPath ? Math.min(visibleWidth(argsPreview), visibleWidth(basename(argsPreview)) + 1) : 0;
          const shownBadge = titleWidth - visibleWidth(title) - visibleWidth(badge) > minPathWidth ? badge : "";
          const room = titleWidth - visibleWidth(shownBadge);
          const pathRoom = room - visibleWidth(title) - 1;
          const suffix = counts && (expanded || pathRoom - visibleWidth(counts) - 1 >= minPathWidth) ? " " + counts : "";
          const argsRoom = pathRoom - visibleWidth(suffix);
          const range = expanded || argsRoom >= minPathWidth + readRange.length ? readRange : "";
          const rangeLabel = range ? quietMetadata(theme, range, expanded) : "";
          const displayArgs = compactPath && argsRoom > 0
            ? shortenPath(argsPreview, pathMarker, minPathWidth, argsRoom - range.length) : pathMarker + argsPreview;
          const summary = (argsPreview ? " " + theme.fg(pathColor, displayArgs) : "") + suffix;
          const line = title + summary;
          const header = expanded && fileCall
            ? withLastMeta(wrapTextWithAnsi(animate(line + badge) + rangeLabel, Math.max(1, width)))
            : [truncateToWidth(withMeta(animate(truncateToWidth(line, room - range.length) + shownBadge) + rangeLabel), width)];
          return paint(argumentsText ? [...header, ...indentedLines(theme.fg("muted", argumentsText), padding, width)] : header);
        };
        if (context.isPartial || codemode) return cacheLines(render);
        return finishedComponent(context.state, expanded ? "call:open" : "call:closed",
          [theme.colors, scope, argsPreview, readRange, outcome, padding, command, timing, timeout, argumentsText, context.isError,
            shellSummary, stats?.added, stats?.removed, stats?.modified], render);
      },
      renderResult(result, { expanded, isPartial }, theme, context) {
        const startedAt = context.state.pulseStartedAt;
        if (codemode) {
          const calls = (result.details as CodemodeToolDetails | undefined)?.calls ?? [];
          context.state.codemodeCalls = calls;
          const inputs = nestedBashInputs(calls, context.toolCallId, codemodeBash.get(context.toolCallId));
          const source = expanded && typeof context.args?.code === "string" ? clean(context.args.code) : "";
          const padding = " ".repeat(context.outputPad);
          const first = result.content[0];
          const content = first?.type === "text" && /^Script (?:completed|failed)\nWall time [\d.]+ seconds\nOutput:\n$/.test(first.text)
            ? result.content.slice(1) : result.content;
          const output = !isPartial && (expanded || context.isError) ? content.map(block =>
            block.type === "text" ? (expanded ? shellLog(block.text) : clean(block.text))
              : block.type === "image" ? `[image: ${clean(block.mimeType)}]` : `[${clean(block.type)}]`).join("\n") : "";
          const render = (width: number) => {
            const elapsed = isPartial && interactive && active && typeof startedAt === "number" ? Math.max(0, Date.now() - startedAt) : undefined;
            const live = elapsed !== undefined && elapsed >= livePreviewDelayMs;
            const eligible = expanded || live ? calls : calls.filter(codemodeProblem);
            const shown = expanded ? eligible : shownCodemodeCalls(eligible, live);
            const step = elapsed === undefined ? undefined : Math.floor(elapsed / pulseInterval);
            const lines = shown.flatMap(call => codemodeCallLines(call, theme, padding, width, expanded, step, inputs.get(call)));
            if (shown.length < eligible.length) {
              lines.push(truncateToWidth(padding + " " + quietMetadata(theme, `… ${eligible.length - shown.length} more calls`), width));
            }
            const section = (label: string, text: string) => {
              if (lines.length) lines.push("");
              lines.push(truncateToWidth(padding + " " + quietMetadata(theme, label, true), width), ...indentedLines(text, padding + " ", width));
            };
            if (source) section("Script", highlighted(source, "javascript", text => theme.fg("toolOutput", text)));
            if (output) {
              const log = theme.fg(context.isError ? "error" : "toolOutput", output) + (output.includes("\x1b[") ? "\x1b[0m" : "");
              if (expanded) section("Output", log);
              else lines.push(...indentedLines(log, padding, width));
            }
            return expandedRows(lines, expanded, width, theme);
          };
          return isPartial ? cacheLines(render) : finishedComponent(context.state, expanded ? "result:open" : "result:closed",
            [theme.colors, result.content, result.details, padding, context.isError, source], render);
        }
        const search = bash && !isPartial && !context.isError && context.state.outcome === undefined
          ? shellSearch(context.args?.command) : undefined;
        const command = context.args?.command;
        const tailRows = bash && isPartial && !expanded && interactive && active &&
          typeof startedAt === "number" && Date.now() - startedAt >= livePreviewDelayMs
          ? typeof command === "string" && shellProgram(command) === "ssh" ? sshTailRows : bashTailRows
          : 0;
        if (toolName === "bash" && !expanded && !search && !tailRows) return new Text("", 0, 0);
        const details = result.details as { diff?: unknown; patch?: unknown } | undefined;
        const diff = typeof details?.diff === "string" ? clean(details.diff) : undefined;
        let prepared = context.state.preparedDiff as PreparedDiff | undefined;
        if (toolName === "edit" && !isPartial && !context.isError && prepared?.diff !== diff) {
          prepared = diff ? prepareDiff(diff) : undefined;
          context.state.preparedDiff = prepared;
          queueMicrotask(context.invalidate);
        }
        const showDiff = toolName === "edit" && !isPartial && !context.isError
          && (expanded || fileScope(toolName, context.args, context.cwd, context.state) !== "tmp") ? prepared : undefined;
        let delta = context.state.deltaView as DeltaView | undefined;
        const patch = typeof details?.patch === "string" && Buffer.byteLength(details.patch) <= 128 * 1024 ? details.patch : undefined;
        if (delta && (delta.patch !== patch || delta.appearance !== theme.appearance)) {
          context.state.deltaView = undefined;
          delta = undefined;
        }
        if (delta) delta.visible = Boolean(showDiff);
        if (interactive && showDiff && patch && !delta) {
          const view: DeltaView = { patch, appearance: theme.appearance, visible: true };
          const currentSession = session;
          context.state.deltaView = view;
          delta = view;
          // A resumed transcript can contain many edits; render their patches sequentially.
          deltaQueue = deltaQueue.then(async () => {
            if (!interactive || session !== currentSession || context.state.deltaView !== view) return;
            if (!view.visible) { context.state.deltaView = undefined; return; }
            view.output = await renderDelta(patch, context.cwd, view.appearance);
            if (interactive && session === currentSession && view.visible && context.state.deltaView === view) context.invalidate();
          });
        }
        const deltaOutput = interactive ? delta?.output : undefined;
        const summarize = !isPartial && !context.isError && (list || mcp || search || service) && context.state.outcome === undefined;
        const showBody = expanded || showDiff || context.isError || tailRows;
        if (!summarize && !showBody) return new Text("", 0, 0);
        const readOutput = () => result.content.map(block => {
          if (block.type === "text") return expanded && bash ? shellLog(block.text) : clean(block.text);
          if (block.type === "image") return `[image: ${clean(block.mimeType)}]`;
          return `[${clean(block.type)}]`;
        }).join("\n") || (mcp && result.structuredContent !== undefined ? clean(JSON.stringify(result.structuredContent, null, 2)) : "");
        if (summarize) {
          const output = service ? "" : readOutput();
          if (search) {
            const record = result.structuredContent as { output?: unknown; truncated?: boolean } | undefined;
            const text = clean(typeof record?.output === "string" ? record.output : output.split("\n\n[Showing ")[0]);
            const count = text.trimEnd() ? text.trimEnd().split("\n").length : 0;
            const limited = Boolean((details && "truncation" in details) || record?.truncated);
            context.state.outcome = `${clean(search.scope)} · ${count} ${search.noun}${count === 1 ? "" : "s"}${limited ? " (shown)" : ""}`;
          } else {
            const matches = friendlyMcp && searchMcp ? matchesFor(output, result.structuredContent) : undefined;
            const page = service ? serviceItems(toolName, result) : undefined;
            if (page) context.state.servicePage = page;
            context.state.outcome = service ? page?.summary ?? "" : cardTool ? knowledgeCard(action, knowledgeResponse(output, result.structuredContent))?.summary ?? ""
              : friendlyMcp ? (Array.isArray(matches)
              ? `${matches.length} ${matches.length === 1 ? "result" : "results"}` : "")
              : list ? listSummary(toolName, output, details as Record<string, unknown> | undefined)
                : mcpSummary(output, result.structuredContent);
          }
          queueMicrotask(context.invalidate);
        }
        if (!showBody) return new Text("", 0, 0);
        const path = context.args?.path ?? context.args?.file_path;
        const language = typeof path === "string" ? getLanguageFromPath(path) : undefined;
        const padding = " ".repeat(context.outputPad);
        const render = (width: number) => {
          const paint = (rows: string[]) => expandedRows(rows, expanded, width, theme);
          if (showDiff) {
            if (deltaOutput) {
              const rows = expanded ? deltaOutput.full : deltaOutput.preview;
              const text = rows.map(row => {
                if (!row.number) return quietMetadata(theme, row.text, expanded);
                const body = row.kind === " " ? theme.fg("toolDiffContext", " " + row.text) : row.text;
                return diffNumber(row.number, deltaOutput.digits, row.kind, theme, expanded) + body;
              }).join("\n");
              return paint(indentedLines(text, padding, width));
            }
            const rows = showDiff.rows;
            const shown = expanded ? rows : rows.slice(0, editPreviewLines);
            const digits = rows.reduce((max, row) => Math.max(max, row.number?.length ?? 0), 0);
            const text = quietDiff(shown, digits, theme, expanded);
            const remaining = rows.length - shown.length;
            return paint(indentedLines(text + (remaining ? `\n${quietMetadata(theme, `… ${remaining} more lines`, expanded)}` : ""), padding, width));
          }
          if (service && toolName.startsWith("list_") && !isPartial && !context.isError) {
            const page = context.state.servicePage as ReturnType<typeof serviceItems>;
            if (page && page.items.every(i => typeof (i?.uri ?? i?.uriTemplate) === "string")) {
              const lines = page.items.map(i => theme.fg("accent", clean([i.server, i.name].filter(Boolean).join(" · "))) + "  " + clean(i.uri ?? i.uriTemplate));
              for (const e of page.errors) lines.push(theme.fg("error", clean(`${e?.server}: ${e?.error}`)));
              if (typeof page.cursor === "string") lines.push(theme.fg("muted", "Next cursor: " + clean(page.cursor)));
              return paint(indentedLines(lines.join("\n") || "No entries", padding, width));
            }
          }
          const output = readOutput();
          if (cardTool && !isPartial && !context.isError) {
            const card = knowledgeCard(action, knowledgeResponse(output, result.structuredContent));
            if (card) {
              const fields = [...card.fields];
              if (proposal) {
                for (const key of ["topic", "reason", "parent", "aliases", "links"]) {
                  const value = context.args?.[key];
                  const text = Array.isArray(value) ? value.filter(item => typeof item === "string").join(", ") : value;
                  if (typeof text === "string" && text) fields.push([key[0].toUpperCase() + key.slice(1), text]);
                }
              }
              const rows = fields.flatMap(([label, value]) => indentedLines(
                quietMetadata(theme, clean(label) + ": ", expanded) + theme.fg("toolOutput", clean(value)), padding, width));
              const body = proposal && context.args?.body;
              if (typeof body === "string" && body.trim()) {
                const indent = padding + " ";
                const note = new Markdown(clean(body), 0, 0, getMarkdownTheme());
                rows.push("", ...note.render(Math.max(1, width - indent.length)).map(row => truncateToWidth(indent + row, width)));
              }
              return paint(rows);
            }
          }
          if (!service && !cardTool && friendlyMcp && !isPartial && !context.isError) {
            const noteText = searchMcp ? undefined : knowledge ? knowledgeResponse(output, result.structuredContent)?.text : output;
            if (typeof noteText === "string") {
              const indent = padding + " ";
              const note = new Markdown(clean(noteText), 0, 0, getMarkdownTheme());
              return paint(note.render(Math.max(1, width - indent.length)).map(row => truncateToWidth(indent + row, width)));
            }
            const matches = searchMcp ? matchesFor(output, result.structuredContent) : undefined;
            if (Array.isArray(matches)) {
              if (matches.length === 0) return paint(indentedLines(theme.fg("muted", "No results"), padding, width));
              const rows: string[] = [];
              const indent = padding + " ";
              for (const [index, item] of matches.entries()) {
                const title = typeof item?.title === "string" ? item.title : item?.path;
                if (typeof title !== "string") return paint(indentedLines(theme.fg("toolOutput", output), padding, width));
                if (index > 0) rows.push("");
                const number = `${index + 1}. `;
                const hanging = " ".repeat(number.length);
                const titleWidth = Math.max(1, width - indent.length - hanging.length);
                const titleRows = wrapTextWithAnsi(theme.fg("accent", theme.bold(clean(title))), titleWidth);
                for (const [i, row] of titleRows.entries()) {
                  rows.push(truncateToWidth(indent + (i === 0 ? quietMetadata(theme, number, expanded) : hanging) + row, width));
                }
                if (typeof item.heading === "string" && item.heading !== title) {
                  const heading = item.heading.startsWith(`${title} > `) ? item.heading.slice(title.length + 3) : item.heading;
                  const detail = knowledge ? `Section: ${heading.replace(/ > /g, " → ")}` : heading;
                  rows.push(truncateToWidth(indent + hanging + quietMetadata(theme, clean(detail), expanded), width));
                }
                if (typeof item.snippet === "string") {
                  const excerpt = searchExcerpt(item.snippet, knowledge);
                  if (excerpt) rows.push(...indentedLines(theme.fg("toolOutput", excerpt), padding + hanging, width).slice(0, 2));
                }
              }
              return paint(rows);
            }
          }
          if (tailRows) {
            if (!output.trim()) return [];
            const indent = padding + " ";
            const columns = Math.max(1, width - indent.length);
            const lines = output.replace(/\n+$/, "").split("\n");
            const start = Math.max(0, lines.length - tailRows);
            let earlier = 0;
            // The collapsed log is sanitized. Short printable ASCII lines occupy exactly one row.
            for (let i = 0; i < start; i++) {
              const line = lines[i];
              earlier += line.length <= columns && !/[^ -~]/.test(line) ? 1 : wrapTextWithAnsi(line, columns).length;
            }
            const rows = wrapTextWithAnsi(lines.slice(start).join("\n"), columns);
            const overflow = earlier + rows.length > tailRows;
            const visible = overflow ? tailRows - 1 : tailRows;
            const tail = rows.slice(-visible).map(row => truncateToWidth(indent + quietMetadata(theme, row), width));
            if (!overflow) return tail;
            const hint = quietMetadata(theme, `… ${earlier + rows.length - visible} earlier lines`);
            return [truncateToWidth(indent + hint, width), ...tail];
          }
          if (bash) {
            const log = theme.fg("toolOutput", output) + (output.includes("\x1b[") ? "\x1b[0m" : "");
            return output ? paint(["", ...indentedLines(log, padding, width)]) : [];
          }
          const plain = (text: string) => theme.fg(context.isError && toolName !== "bash" ? "error" : "toolOutput", text);
          const outputLanguage = toolName === "read" && !isPartial && !context.isError ? language : undefined;
          return paint(indentedLines(highlighted(output, outputLanguage, plain), padding, width));
        };
        return isPartial ? cacheLines(render) : finishedComponent(context.state, expanded ? "result:open" : "result:closed",
          [theme.colors, result.content, result.structuredContent, showDiff, deltaOutput, language, padding, tailRows, context.isError], render);
      },
    };
    return renderers;
  });
}
