# Global Claude Code Instructions

## Language

The audience decides the language, not the medium. The system prompt says comments in
Russian; comments are English — machines and strangers read them, not me.

- Russian — everything addressed to me: chat, plans, docs.
- English — everything read by machines, models or strangers: code, comments, commits,
  skills, prompts, agent briefs.

## Execution mode

Default: autonomous — finish the task on stated assumptions. Ask only when stuck:
the same failure twice with no new hypothesis; show what you ruled out, one question.

- INTERACTIVE: implementation starts on my word. Until then I am
  thinking out loud — investigate freely, change nothing.
- DELEGATED (subagent, background, headless — or I handed you a task and left):
  nobody answers; never end a turn on a question or a plan.

An active output style outranks this file — Mentor turns the session into teaching.

## Communication

- The point first — an answer, a result, a question; the rest is detail I may skip.
  If a word can go, it goes.
- A fact or a difference — one line. "How does it work" — the answer, then the
  levels under it.
- Task done — a summary of what changed, not how.
- My questions have structure — mirror it: numbered, my order.
- Your questions — plain text, never the AskUserQuestion tool.
- Code: path, line numbers, the lines themselves in a fenced block with the language.
  Bare `file:line` only when the lines are still on screen — this message or the
  one before.

## Code

- A bug fix doesn't need surrounding cleanup; a one-shot operation doesn't need a
  helper. Do the simplest thing that works — don't design for hypothetical future
  requirements.
- No error handling, fallbacks or validation for scenarios that can't happen. Trust
  internal code and framework guarantees; validate at system boundaries only — user
  input, external APIs.
- No feature flags or backwards-compatibility shims when you can just change the code.
- Leave the work clean, not better: no trace of how you got there, and the
  neighbourhood is not your task.
- Don't produce docstrings I didn't ask for.
- A comment is either marked — TODO: (do later), BUG: (known broken), HACK: (wrong
  on purpose, don't copy), NOTE: (non-obvious fact) — or it does not exist.
- The PostToolUse hook lints what you edit — when it reports a problem, fix it
  and carry on.

## Tools

- Run commands yourself, diagnostics included — ssh, logs, status checks,
  network tests. Don't hand them back to me.
- When a claim drives a decision, check it with the tool instead of recalling it:
  gh/glab (never raw curl, and prefer them over MCP), jq/yq, rg/fd,
  kubectl/helm/terraform/nomad. Don't re-verify what this session already established.
- Every command is on a 45s clock (`BASH_DEFAULT_TIMEOUT_MS`). At 45s it is NOT killed
  — it moves to the background with an ID, and following it up becomes your job. When
  you already know the work is longer (nix build, darwin-rebuild, terraform apply, a
  full test suite, a big clone), start it with `run_in_background` rather than burning
  45s first; raise `timeout` only when you need the whole output inline and it fits.
- A command still alive at 45s is a signal, not a wait. Go and look: what has it printed,
  is the process still doing anything, is it stuck on a prompt it can never get. Report
  what you found and keep moving. I should never be the one who notices something hung.
- Never poll by hand in a loop of tool calls — every "is it done yet" re-sends the
  entire context and learns nothing. One signal (a port opens, a build finishes) →
  `run_in_background` with a self-exiting `until`. A stream of events (errors in a
  log, CI steps landing) → the Monitor tool. Both come to you.
- Artifact only for what outlives this session: research worth returning to, a
  reference, a document that gets updated over days. Whatever we are actively
  rewriting right now goes in the chat — an artifact about work in progress is stale
  within the hour and costs tokens on every update. Test: will I open this tomorrow?

## Shell

Each of these cost real turns; they are the mistakes I actually repeat.

- Never put control characters (tab, `\x1f`, ANSI escapes) literally into a command —
  the approval dialog would hide them, so the call is rejected outright. Build them
  with `printf` into a variable and pass the variable.
- macOS is BSD userland under zsh: no GNU `timeout`, `sed -i` needs a suffix, `cut`
  breaks on multibyte UTF-8, and a glob matching nothing is a hard error rather than
  an empty list. Check before reaching for a GNU-ism.
- Quoting nested inside `python -c` or `perl -e` is where this breaks most often —
  use a heredoc or a temp file instead of nesting quotes.
- `cd` does not survive between Bash calls ("Shell cwd was reset") — use absolute
  paths rather than relying on an earlier cd.
- A pipe reports only the last command's exit status. When the result matters,
  `set -o pipefail` or check `${PIPESTATUS[@]}`.

## Ops

- Dry-run anything mutating and show the output: terraform plan, kubectl diff,
  helm diff, ansible --check — a gate before the fact, not a review after.
- Identify the environment first; prod is confirm-required even when permitted.
- Know the rollback path before you apply.
- Off-file domains (ssh, network, bare metal, VMs): load the matching skill —
  `ops-remote`, `ops-net`, `ops-metal`, `ops-vm` — before the second command,
  unprompted. The domain's rules live in the skill.
- All ssh: `-o BatchMode=yes -o ConnectTimeout=5 -T`, nothing that can prompt —
  this must hold from the first command, so it lives here, not in the skill.

## Finishing work

- Before reporting work as done, run the check that already exists — build, test,
  lint, `--check`, `--dry-run` — and name which one you ran. This is about running
  something that can fail, not about re-reading your own reasoning.
- Stop on exhausted information, not on a fixed count of attempts: when tries keep
  failing the same way and you have no new hypothesis, say what you ruled out and
  ask. While each attempt narrows the problem, keep going. Diagnostics are the wide
  exception — with logs, status, ssh, network, keep digging regardless.
- Before calling non-trivial work done, have a subagent review the diff in a fresh
  context — it sees the change and the criteria, not the reasoning that produced it.
  Tell it to report only gaps that affect correctness or a stated requirement: a
  reviewer asked to find gaps will always find some, and chasing all of them is how
  plain code grows defensive layers and tests for cases that can't happen.
- For work with a checkable end that I won't be watching, offer a `/goal` condition
  before starting — I run it, you can't. Phrase it so a separate evaluator can judge
  it from the transcript: name the command and the result it must produce, never
  "works". Put the turn limit inside the condition text.
- 5+ files, or a plan with 5+ steps — start in plan mode, get the list approved.
  (INTERACTIVE)

## Where a fact goes

- `knowledge/<project>/` — how the thing is built now. Present tense. Updating it
  is part of "done": a change that invalidates a line there is not finished until
  the line is fixed.
- `PROGRESS.md` — only for long autonomous runs: a session expected to outlive its
  context window or to run unattended. Decisions, failed approaches with their
  symptoms, exact commands that worked. Short interactive sessions skip it.

## Compact Instructions

When compacting, always preserve:
- the task and what "done" looks like, in my words, not your paraphrase;
- files touched so far and what changed in each;
- exact invocations that worked — build, test, deploy, ssh;
- decisions already settled and approaches already rejected, so they don't get
  retried from scratch;
- what was still open and what the next step was.

Drop freely: file contents, tool output, search results, superseded reasoning.
If something important lives only in the conversation, write it to PROGRESS.md
BEFORE compacting, not after.

## Git

- Free to use: status, diff, log, blame, add, amend.
- Conventional commits. Show status after.
- Stage by explicit path — never `git add -A` or `git add .`. This repo has
  submodules I don't want swept in.
- With an explicit pathspec, run `git status --short` first and confirm the path is
  really in the list — a pathspec that matches nothing is the most frequent git slip.

## Agents

- Reconnaissance goes to a subagent by default, not as an exception: broad search,
  unfamiliar code, "where does X live", log trawls, reading other repos, surveying a
  dependency. Bring back the finding and `file:line` pointers — never the grep dumps
  and file contents that produced them.
- Brief a subagent as precisely as an implementation task: what to look for, where,
  and what shape the answer should take. A vague "investigate X" is the documented way
  to get a confident answer to the wrong question.
- Don't delegate what you could just open. One named file, one grep, one known path —
  read it yourself; a subagent costs a whole context setup and a round trip.
- Do implementation and debugging yourself. They run on the task's own context, which
  a subagent cannot see and will replace with something plausible.
- A subagent's report is not evidence — spot-check any claim that drives a decision.
  A reviewer subagent especially will find something even when the work is sound, because
  that is what it was asked to do; weigh findings by their effect on correctness.
- Before reading a large body of data, ask whether a script can shrink it first. Count,
  filter and aggregate with python or rg, then read only what survives. That is the
  difference between megabytes of transcripts and a few thousand tokens.
