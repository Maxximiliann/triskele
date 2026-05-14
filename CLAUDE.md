# Triskele Project — Claude Code Instructions

## Project context

Triskele is a fault-tolerant Elixir/OTP triangular arbitrage trading system
targeting the Kraken cryptocurrency exchange. Operator: Maximilian (Joseph
Polanco). Current phase: Phase 1 (Kraken Client) close-out.

**Always read at session start, in this order:**

1. This file (`~/triskele/CLAUDE.md`) — Triskele-specific overrides
2. `~/triskele-prompts/00_PROJECT_BIBLE.md` — Architectural commitments
3. `~/triskele-prompts/DEVIATIONS_LOG.md` — Documented exceptions
4. `~/.claude/projects/-home-jo-polanco-triskele/memory/phase_1_resumption.md`
   — Current state and next steps

These four documents constitute the project's source of truth. When they
conflict with default behavior (including superpowers skill defaults),
THESE WIN per the priority hierarchy below.

## Priority hierarchy

Per superpowers' own documentation, user instructions take precedence over
skill defaults. The full hierarchy:

1. **User explicit instructions** (CLAUDE.md, direct requests in conversation)
   — HIGHEST PRIORITY
2. **Bible architectural commitments** (~/triskele-prompts/00_PROJECT_BIBLE.md)
3. **DEVIATIONS_LOG entries** (documented project-specific exceptions)
4. **Superpowers skills** (workflow methodology defaults)
5. **claude-code-elixir hooks** (Elixir-specific automation defaults)
6. **Default Claude Code behavior**

When any layer conflicts with a lower layer, the higher layer wins.

## Standing instructions

### External advisor handoff via /tmp/cc-share.out

Any output the operator may need to share with an external
advisor — tool results, diffs, audit findings, decision
reports, error traces, mix test output, file overwrites — is
also written to /tmp/cc-share.out, overwriting prior contents.

- Bash invocations producing more than ~5 lines: pipe to
  `tee /tmp/cc-share.out` either inline or in a follow-up.
- Analytical/prose responses (findings, audits, decision
  proposals): write the full content to /tmp/cc-share.out via
  file tools after presenting in chat.
- Write/Edit operations: after operator approval, write the
  final file's full new content to /tmp/cc-share.out so the
  operator shares the resulting state, not the diff.
- Single file, overwritten each turn. No history.
- Exception: outputs under ~15 lines, skip the file write
  (direct copy-paste is fine).

### Update alert

Whenever you write or overwrite /tmp/cc-share.out, end your
response with a single line on its own:

  📄 /tmp/cc-share.out updated

Only print the alert when the file is actually written this
turn. Single line, no decoration, at the very end of the
response. The emoji is the visual anchor for the operator's
scan; keep the exact format.

### Terminal-echo suppression for handoff output

When writing substantive content to /tmp/cc-share.out for
advisor handoff (reports, audits, findings), do NOT duplicate
the full content in the terminal response. Reply with a
one-line confirmation noting what was written and the 📄
marker. The operator uploads the file to the advisor;
terminal duplication is redundant.

Short status messages, tool outputs, and inline answers that
aren't being written to the share file continue to render
normally.

- After every write or overwrite of /tmp/cc-share.out,
  invoke `subl /tmp/cc-share.out` (backgrounded with `&` if
  blocking is a concern). This brings the deliverable to the
  operator's editor automatically. Sublime brings the existing
  buffer forward on repeated opens — no duplicate windows.

### Reporting style

Default to compressed reporting.

- Test runs: one-line headline (pass/fail counts + brief
  failure shape). Expand only on operator request or genuine
  blocking ambiguity.
- Tool/edit application: after apply, the /tmp/cc-share.out
  write is the artifact. Skip the "what was changed" recap.
- DEVIATIONS_LOG drafts: the draft prose, lifecycle, Bible
  reference. Skip scope/applicability sections unless asked.
- Session memory notes: one sentence on what was saved, no
  quote.
- Default volume: short. Expand only when operator asks or
  when ambiguity requires surfacing.

### Document section placement

When adding new sections to project documents (CLAUDE.md,
DEVIATIONS_LOG.md, Bible sections, prompt files), check the
surrounding context for sections marked TEMPORARY,
removal-targeted, or otherwise transient before choosing
placement. Permanent content should not sit adjacent to
removal-targeted blocks — it's too easy for a future cleanup
sweep to catch the wrong section.

Place permanent additions before transient sections, with at
least one heading or section break separating them. If the
only natural insertion point is adjacent to transient
content, add a comment marker or move the transient section
to make the structural separation visible.

### Tooling preferences

For codebase searches, use rg (ripgrep) instead of find/grep
chains. ripgrep is installed at /usr/bin/rg and auto-ignores
deps/, _build/, .git/, and .gitignore-listed paths.

Common patterns:
  rg "pattern" apps/                    # search apps/
  rg --type elixir "TransportError"     # filter by language
  rg -l "Mint.WebSocket"                # files only
  rg -A 5 "defmodule"                   # 5 lines of context after

Use grep/find only as fallback if rg is unavailable in the
current environment.

### Test execution patterns

For iterative test loops (writing tests, fixing failures,
re-running after small edits), prefer `mix test --stale` over
full-suite runs. Mix tracks file-change dependencies and runs
only affected tests, typically completing in 1-5 seconds vs.
~20 seconds for the full kraken_client suite.

For rerunning previously-failed tests after a fix, use
`mix test --failed`. Combines with --stale:
`mix test --stale --failed`.

Run the full suite at gate-check boundaries:
- Before any git commit (the pre-commit hook handles this
  automatically)
- Before marking a Phase 1 item complete
- After dependency updates or PLT rebuilds
- After test_helper.exs or mix.exs changes

For tests filtered by tag (e.g., `--only phase_1`), --stale
applies within the filtered set.

For sustained development sessions where you're iterating on
a single module or describe block, run `mix test.watch --only
<tag>` in a dedicated pane. The watcher reruns affected tests
automatically on file save, eliminating the "save, switch
panes, type mix test, wait" loop. Combines with all standard
mix test flags. Ctrl-C twice to stop.

## Operator policy

The operator (Maximilian) handles ALL of the following:

- `git push` operations (any branch, any remote)
- `gh pr` operations (create, merge, close)
- Branch deletion
- Force-pushes
- GitHub repo configuration changes
- API key / secret management

Claude Code creates commits (signed with GPG, per existing setup) but NEVER
pushes. When work is ready to push, surface this to the operator with a
clear "ready to push" status.

## Phase 1 close-out overrides (TEMPORARY — remove after Phase 1 merges)

### Override 1: TDD Iron Law grandfathering

The TDD Iron Law (superpowers:test-driven-development) requires deletion
of any production code that was not preceded by a failing test. This
applies fully from Phase 2 onward.

For Phase 1 close-out work specifically:

- **Existing Phase 1 modules** (commits 24be22d through ef77676 on
  branch phase-1/kraken-client) are GRANDFATHERED. Writing tests for
  them does NOT invoke the deletion clause.
- **Treatment of these tests**: characterization-test-first.
  Write the test, verify it passes against the existing module,
  do NOT delete the module if the test passes immediately.
- **Reference**: Michael Feathers, *Working Effectively With Legacy
  Code*, characterization test pattern.

This override applies ONLY to the following modules:

- `Triskele.KrakenClient.WebSocket.Public`
- `Triskele.KrakenClient.WebSocket.Auth`
- All Type modules in `apps/triskele_kraken_client/lib/triskele/kraken_client/types/`
- `Triskele.KrakenClient.REST`
- All other Phase 1 modules already committed

It does NOT apply to:

- `Triskele.KrakenClient.WebSocket.Private` (new module — full TDD)
- Any Phase 2+ work (full TDD)
- The CRC fixture fix (the failing test already exists; the fix is
  for the fixture, not new code)

Document: DEVIATIONS_LOG.md entry DEV-003.

### Override 2: Brainstorming skip

The superpowers:brainstorming skill is a hard gate before implementation.
For Phase 1 close-out specifically, the resumption notes at
`~/.claude/projects/-home-jo-polanco-triskele/memory/phase_1_resumption.md`
serve as the design document.

Skip the brainstorming skill for Phase 1 close-out work. Invoke
`superpowers:writing-plans` directly with the resumption notes as the
design input.

This override applies until Phase 1 closes (PR merged). Phase 2+ work
follows the brainstorming gate fully.

Document: DEVIATIONS_LOG.md entry DEV-004.

### Override 3: CRC fixture diagnosis requires operator escalation

The first concrete task in Phase 1 close-out is fixing the CRC fixture
in `book_maintenance_test.exs`. Yesterday's analysis was wrong (we
removed zeros when we should have added them, or there's a bug in
crc_str/1).

**DO NOT dispatch a subagent for CRC diagnosis.** Instead:

1. Read the "CRITICAL: Yesterday's fixture fix was wrong" section of
   the resumption notes
2. Status: BLOCKED. Report to operator with the Possibility 1 / 2 framework
3. Operator will consult claude.ai for diagnostic work
4. Operator returns with a specific hypothesis to test
5. Apply the targeted fix directly (small enough for parent agent —
   no subagent needed under the anti-over-delegation threshold)
6. Run tests, verify all 3 CRC tests now pass
7. Proceed to other Phase 1 close-out work

After CRC is resolved, the rest of Phase 1 close-out can use the full
subagent-driven-development workflow.

## Phase 1 close-out work plan

Source of truth: `~/.claude/projects/-home-jo-polanco-triskele/memory/phase_1_resumption.md`

Summary of remaining work after CRC fix:

1. `mix dialyzer` (verification step, no subagent needed)
2. `WebSocket.PublicTest` — characterization tests for existing module
3. `WebSocket.AuthTest` — characterization tests using Mox
4. `WebSocket.Private` — new module + tests (full TDD applies here; architecture per DEV-010 in triskele-prompts)
5. Application supervisor wiring (depends on item 4)
6. Live smoke test against `wss://ws.kraken.com/v2`
7. PR creation and merge (operator handles)

Items 2, 3, 4 are strictly serial per the project decision. Each must
complete (including spec review and code quality review) before the next
starts.

## Phase 2+ commitments (PERMANENT)

These apply once Phase 1 merges to main:

### Full TDD enforcement

All new modules and features follow superpowers:test-driven-development
with no overrides. RED-GREEN-REFACTOR cycle, watch tests fail before
implementing.

The Iron Law applies: production code without a preceding failing test
is deleted.

### Full brainstorming gate

All new features go through superpowers:brainstorming before any
implementation. The brainstorming skill produces a design document
saved to `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`.

### Worktree pattern

All new work happens in isolated worktrees per superpowers:using-git-worktrees.
The convention is `.worktrees/<branch-name>` at project root (already
added to `.gitignore`).

## Subagent dispatch rules

When the parent agent dispatches a subagent (via Task tool, per
superpowers:subagent-driven-development):

### Context injection requirement

Subagents do NOT auto-read CLAUDE.md. The parent MUST include relevant
Bible references in each dispatch prompt. Specifically:

- For code-writing subagents: include Bible §2 (Inviolable Rules),
  §4 (Code Style), §7 (Error Handling), §14 (Quality Gates)
- For test-writing subagents: include Bible §14 plus any test-pattern
  specifics relevant to the module under test
- For QA/review subagents: include DEVIATIONS_LOG entries plus the
  Bible sections relevant to the work being reviewed

The parent is responsible for context translation. Sub-agents focus on
their specific task without bootstrapping overhead.

### Model selection

Per superpowers:subagent-driven-development model guidance, adapted for
Triskele:

| Role | Model | When |
|------|-------|------|
| Parent (this session) | Opus 4.7 | Always |
| Implementer subagent | Sonnet 4.6 | Code writing (most tasks) |
| Implementer subagent | Opus 4.7 | Architecture decisions, complex integration |
| Spec compliance reviewer | Opus 4.7 | All review tasks |
| Code quality reviewer | Opus 4.7 | All review tasks |
| Search/enumeration | Haiku 4.5 | File listing, grep across codebase |
| Diagnostic | Sonnet 4.6 | Run command, parse output, summarize |

### Anti-over-delegation thresholds

The parent handles tasks directly (NO subagent) when:

- Change is < 30 lines
- Single file, no architectural decisions
- Reading a single file to answer a specific question
- Single diagnostic command (git status, ls, etc.)
- Routing decisions between subagents
- Composing dispatch prompts for other subagents
- Communicating with operator (escalation, status updates)

The parent dispatches a subagent when:

- Change creates a new file
- Change modifies > 30 lines
- Task requires reading > 3 files
- Search across > 5 files
- Test run requiring output interpretation
- Research requiring external doc reading

### Standard dispatch protocol

Every dispatch prompt the operator composes for a subagent
includes implicit conventions. The phrase "Standard dispatch
protocol applies" in a dispatch indicates the following
constants without restating them:

- Scope is explicit: which files are in scope, which are
  out of scope. Files commonly tempting to "fix in
  passing" — .credo.exs, .formatter.exs, mix.exs,
  DEV-* files, unrelated production modules — are listed
  as explicitly out of scope.
- Deliverable goes to /tmp/cc-share.out under a heading
  matching the dispatch title. The deliverable structure
  is specified in the dispatch with section headers.
- If a blocker is encountered at any step (scope violation,
  unexpected file state, contradictory evidence, unclear
  instruction), STOP, write findings to /tmp/cc-share.out
  under a "## Blocker" heading, and wait for operator
  direction. Do not improvise around the blocker.
- Commits are local only — no push, no PR. The operator
  handles git push and PR work.
- One outer task per dispatch. No "while I'm here"
  cleanups, no adjacent-file fixes, no scope expansion.
- Echo suppression for /tmp/cc-share.out per standing
  instructions (already documented in this file at
  "### Terminal-echo suppression for handoff output").

When a dispatch prompt omits these reminders and instead
writes "Standard dispatch protocol applies", treat that as
shorthand for the full list above.

### Deliverable schema norms

Subagent deliverables to /tmp/cc-share.out follow these
quality norms:

- Prefer 3-5 sharp sections to 8-10 broad ones. Every
  section should answer a specific question the operator
  posed in the dispatch.
- Cite targeted lines (file:line and a few-line excerpt)
  over full source dumps. Full function bodies are
  warranted only when the surrounding code is load-bearing
  for the question being answered.
- When proposing a fix, specify: file, function or line
  range, exact change shape (str_replace pattern, new
  lines, or one-token replacement). Do not implement.
- When a verification step produces unexpected results,
  report what was found and STOP. Do not pivot mid-
  dispatch to investigate adjacent concerns.
- Hypothesis rankings: when multiple causes are plausible,
  enumerate them with one-sentence justifications each and
  a clear "MOST LIKELY" or numeric ranking. Do not bury
  the recommendation in prose.

## Escalation triggers

Escalate to operator (status: BLOCKED) when any of these occur:

1. **Bible deviation needed**: A task requires diverging from a Bible
   commitment. Manager flags and stops. Operator decides whether to
   approve the deviation (adding to DEVIATIONS_LOG) or reject.

2. **Subagent loop**: Same task has cycled through 2 revision rounds
   in QA without converging. Stop, write the situation to a brief
   summary, escalate.

3. **CRC diagnosis or similar diagnostic ambiguity**: Tasks explicitly
   marked in resumption notes or DEVIATIONS_LOG as requiring operator
   consultation. Per Phase 1 close-out, this includes the CRC fixture.

4. **Push/merge actions**: All git push and gh pr operations.
   Never executed by Claude Code; always operator-handled.

5. **Plugin/tooling failures**: superpowers or claude-code-elixir plugin
   produces unexpected behavior or errors that the parent agent cannot
   resolve.

6. **Architectural uncertainty**: Genuine "should this go in module A
   or module B" decisions that have lasting implications. Surface to
   operator rather than guess.

## Notification protocol for escalation

When raising an escalation, the parent agent should:

1. Output a banner that's hard to miss:

   ```
   ════════════════════════════════════════════════════════════
     ⚠️  OPERATOR ESCALATION REQUIRED
     Context: [brief summary]
     File: [if relevant]
     See full details below
   ════════════════════════════════════════════════════════════
   ```

2. Provide complete context — what was being attempted, what went
   wrong, what options exist
3. If applicable, attempt `notify-send` for desktop notification:

   ```bash
   notify-send -u critical "Claude Code escalation" "Operator action required in Triskele session" 2>/dev/null
   ```

4. Wait for operator response before proceeding

## Git workflow

- Branch: feature work on `phase-<N>/<feature-name>` branches
- Worktrees: `.worktrees/<branch-name>` at project root (Phase 2+)
- Commits: signed with GPG (`-S` flag, already in git config)
- Pre-commit hook at `.git/hooks/pre-commit` runs `mix format` + `mix credo`
- Tests run before commit via the same hook
- Push: operator-only

## Quality gates

Per Bible Section 14, every commit must satisfy:

```
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
mix dialyzer
```

The claude-code-elixir plugin runs the first three automatically on
edit. The pre-commit hook runs them again at commit time (defense in
depth — both layers retained per architectural decision).

Phase-tagged tests run with `mix test --only phase_N`.

## When in doubt

- Check the Bible first
- Check DEVIATIONS_LOG for documented exceptions
- Check this CLAUDE.md for overrides
- If still uncertain, escalate to operator — do NOT guess on
  architectural decisions

The operator's time is valuable but architectural mistakes cost more.
A 30-second escalation prevents a 30-minute rework.