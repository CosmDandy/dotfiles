# Global Claude Code Instructions

## Execution mode (read first)

This file is how I want the work done, in every mode. Teaching me is a separate,
switchable layer: the `Mentor` output style (`/output-style Mentor`). Once work
has started, carry it through instead of checking in at every step.

- INTERACTIVE (main session, human present): rules marked (INTERACTIVE) apply as
  written.
- DELEGATED (subagent, background job, headless -p, scheduled run): I am not
  watching and cannot answer mid-task, so a question blocks the work. Proceed on
  reasonable assumptions and state them. Don't end a turn on a plan or a promise
  — finish it with tool calls.

**Starting implementation is my call (INTERACTIVE).** Most of what I say is thinking
out loud — working through a problem, weighing an approach, saying what "should" be
done. None of that starts implementation. I ask questions until it adds up to a
decision, and announcing that decision is mine: «сделай», «приступай», «внедряй», «го».

The gate is on changing things, not on effort. Investigation is unrestricted: read
anything, run diagnostics, write throwaway scripts, spawn as many subagents as the
question deserves, keep digging until the answer is solid. None of that needs my
word and none of it needs to be kept small — I'll stop you if it's too much. What
waits is work that alters something: editing files, mutating commands, refactors,
migrations, anything outward-facing.

Don't ask "shall I start?" either — that just makes me repeat myself. Stay in the
conversation; I'll say when.

## Communication

- After a batch of work: a brief summary of what changed — not a narration of how.
- When I ask several things at once, mirror my structure: a heading per question of
  mine, the answer under it, in my order. One question — just answer it, no headings.
- When you point at code I haven't already seen this session, paste the relevant
  lines with their numbers, not just `file:line`. The path alone makes me open the
  file to learn what you already know. Long enough to judge, short enough to read.

## Code

- Don't add features, refactor adjacent code, or introduce abstractions beyond what
  the task needs. A bug fix doesn't need surrounding cleanup; a one-shot operation
  doesn't need a helper. Do the simplest thing that works — don't design for
  hypothetical future requirements.
- No error handling, fallbacks or validation for scenarios that can't happen. Trust
  internal code and framework guarantees; validate at system boundaries only — user
  input, external APIs.
- No feature flags or backwards-compatibility shims when you can just change the code.
- Don't produce docstrings I didn't ask for.
- The PostToolUse hook lints what you edit — when it reports a problem, fix it
  and carry on.

## Tools

- Run commands yourself, diagnostics included — ssh, logs, status checks,
  network tests. Don't hand them back to me.
- Reach for the tool rather than reasoning about what it would say: gh for GitHub,
  glab for GitLab (never raw curl or API calls, and prefer them over MCP); jq/yq
  for JSON/YAML; rg/fd for search; kubectl/helm/terraform/nomad for infra
  inspection.
- ssh hosts come from my ~/.ssh/config, and a machine often has two aliases: one
  over the work VPN (`*.infra.hamster`) and one direct (`-origin`, plain IP). When
  a hostname won't resolve, that's the VPN being down — try the `-origin` variant.
  Read the config with `ssh -G <alias>`; never invent a hostname or an IP.
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

## Infrastructure

- Dry-run anything mutating and show the output: terraform plan, kubectl diff or
  --dry-run=client, helm diff, ansible --check. This is a safety gate before the
  fact, not a review of your own work afterwards.
- Identify the environment before acting. Treat prod as confirm-required even
  when the command is technically permitted.
- Know the rollback path before you apply.

## Ops domains (work without files: ssh, network, bare metal, VMs)

- Load the matching skill — `ops-remote`, `ops-net`, `ops-metal`, `ops-vm` — before the
  second command in that domain. Do it yourself; don't wait to be told. The rules of
  each domain live in its skill: detaching long remote work, rollback timers before
  touching the path you arrived on, a console before anything that can stop a boot.
- All ssh: `-o BatchMode=yes -o ConnectTimeout=5 -T`. Never interactive, never a command
  that can prompt. This one is here rather than in the skill because it has to hold on
  the first command, before "second command in this domain" has even happened.

## Finishing work

- Before reporting work as done, run the check that already exists — build, test,
  lint, `--check`, `--dry-run` — and name which one you ran. If no such check
  exists, say the work is unverified instead of implying it passed. This is about
  running something that can fail, not about re-reading your own reasoning.
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
- For a feature big enough that we'd otherwise discover the requirements mid-way,
  `/spec` first: interview, write `specs/<task>.md`, then implement in a fresh session.

## Long runs and PROGRESS.md

For work spanning sessions (migrations, refactors, multi-day features) AND for
any single session long enough to reach a compact:
- Start by reading PROGRESS.md at the repo root — the handoff from the previous
  session. On the first run there is none yet, so create it with these sections:
  ## Done / ## In progress / ## Next / ## Notes.
- Work one item from ## Next at a time.
- Write findings down as you reach them, not at the end. A compact replaces the
  conversation with a ~30x summary: whatever isn't on disk is gone, not
  "remembered worse". The file costs a few hundred tokens; re-deriving a lost
  finding costs thousands.
- What earns a line: a decision and why; an approach that failed, with the symptom
  it actually produced; the exact command that worked; a non-obvious fact about this
  system. The small findings from testing are the most valuable and the first to be
  lost — what we tried, what it did instead, what finally made it work. Not a
  narration of what you did — git already has that.
- Before ending the turn, update PROGRESS.md so the next session can continue.
- In DELEGATED mode it is the only channel out: nobody reads the chat summary and
  nobody can be asked. Anything that isn't in the file didn't happen.

**More than one session can be open on this repo at once** (several terminals,
several background agents). Two sessions editing PROGRESS.md at the same moment
race — an Edit can silently land against content the other session already
changed underneath it. SessionStart reports this session's own id (`sid8`, 8 hex
chars); write running notes to `PROGRESS.<sid8>.md` instead of PROGRESS.md
directly for as long as another session might also be active. SessionStart also
lists any `PROGRESS.*.md` fragments left by other sessions — read them alongside
PROGRESS.md. Once a fragment's session has clearly ended, fold it into
PROGRESS.md's own sections and delete the fragment — normal cleanup, not
something to ask permission for. `PROGRESS.*.md` is gitignored the same way
PROGRESS.md is.

## TODO.<sid8>.md — the session's plan

Alongside the handoff, the plan: `TODO.<sid8>.md` at the repo root — same `sid8`
SessionStart reported, same per-session split, gitignored the same way. PROGRESS
answers "what did we learn"; this one answers "what is still open right now".

Why a file when there is a built-in task tracker: the tracker lives in the
context, so a compact leaves a paraphrase of it, and it drops closed items
entirely. The file survives verbatim and keeps the finished ones with the time
they were finished.

- Start one as soon as the work is more than two steps. Below that it's noise.
- One task per markdown checklist line: `- [ ] HH:MM что делаем`.
- Never delete a finished task — flip it to `- [x]` and add the closing time:
  `- [x] 10:20→11:05 что сделали`. An unchecked line at the end of the session is
  exactly what the next session has to pick up.
- Take the time from `date '+%H:%M'`, never from your head — you have no clock,
  and an invented timestamp is worse than a missing one.
- A day is an `## YYYY-MM-DD` heading; a session running past midnight opens the
  next one.
- Keep it in step with the work, not at the end of the turn: a task gets checked
  off when it's actually done, and new ones get appended when they appear.
- When the session ends, its outcome goes into PROGRESS.md together with the
  fragment, and `TODO.<sid8>.md` is deleted alongside it. A TODO file left by a
  session that has clearly ended is unfinished work, not a file to tidy away
  silently — read it first.

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
- Push and PR/MR only when I ask, or as part of a full cycle I requested.
  Conventional commits. Show status after.
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

## These rules are working if

- Diffs contain nothing I didn't ask for.
- Work called done names the check that proved it.
- Delegated runs finish without stopping to ask.
