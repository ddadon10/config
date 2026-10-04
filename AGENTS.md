# Environment

- You are in a Docker container. You cannot run Docker.
- You cannot run `git pull` or `git push`. When merging another branch into the current branch, merge
  `origin/<other-branch>` into this branch directly.
- Use `rg` instead of `grep`, and `fd` instead of `find`.

# Workflow

- Do not expand the scope beyond what the request requires.
- Keep validation proportional to the change. Run focused checks once after related edits, and run broad test suites
  only when requested or clearly necessary.
- Treat my corrections as instructions for the rest of the conversation. Apply them to later responses and actions
  unless I explicitly revise them.
- Use a todo list for any task that is not a single straightforward change.

# Code Style

- Inline simple one-off functions. Do not extract a single-use helper or assign a literal to a single-use variable.
- When creating or editing configuration files, omit settings that merely repeat default values unless the request
  explicitly requires pinning or documenting one.
- Keep code on one line when it fits within 120 columns unless syntax or the project formatter requires wrapping. This
  includes trivial or single statement functions and methods.

# Request-Specific Instructions

## Plan

When I ask you to plan, preserve every stated requirement, constraint, and exclusion. Write a self-contained,
outcome-focused plan that a reader with only the current working tree can implement. Resolve material design decisions,
name the exact files and interfaces involved, and include verifiable milestones, validation criteria, expected results,
and recovery guidance. Include code or configuration excerpts only where needed to eliminate ambiguity.

Choose a short name that identifies the task, format it as `UPPER_SNAKE_CASE`, and save the plan as
`{TASK_NAME}_EXECPLAN.md`. Do not begin implementation unless I ask you to. The ExecPlan must contain these sections
in order:

1. `Purpose and Context` defines the goal, observable result, assumptions, and relevant repository state.
2. `Plan of Work` specifies the milestones, affected files and interfaces, concrete steps, validation, and recovery.
3. `Progress` uses checkboxes to track completed, in-progress, and remaining work, including the exact next action.
4. `Findings and Decisions` records discoveries, evidence, decisions, validation results, outcomes, and lessons learned.
5. `Audit Log` records every change made elsewhere in the ExecPlan, stating when it occurred, what changed, and why.

When implementing the plan, treat it as the living source of truth and keep it current at every stopping point. Whenever
the `Audit Log` is updated, automatically create a local commit containing the ExecPlan and all task-related changes
covered by the update, with a clear message and description. Stage only task-related changes, never include unrelated
user changes, and never push. After compaction, reread the entire ExecPlan and inspect the working tree before continuing.

## Explore

When I ask you to explore, inspect relevant local code and evidence, and research official documentation and original
upstream repositories. When exploring, create and use a directory under `/workspace/.agentexploration` if that parent
directory exists; otherwise, create and use a directory under `/data/share/agentexploration`. Keep a concise journal inside
the created directory and report the journal's path. You may use that directory without asking to store files and
subdirectories, clone relevant repositories, and write and run exploratory code when useful.

Return a direct synthesis backed by precise local references and official HTTPS links. For external source code, link
to exact lines in the original repository (GitHub, GitLab, Codeberg, etc.), preferably at a fixed commit, never to the
temporary clone. Distinguish verified facts, inference, and unresolved gaps.

## Suggest

When I ask you to suggest, present three viable and materially different options that fit the known context. Put the
simplest option that fully satisfies the request first and label it `(Recommended)`. Make the second and third options
genuinely different approaches, not minor variations of the first. Prefer compact code snippets with useful inline
comments, followed by at most one short explanation. If code is not applicable, use one concise description instead.
If fewer than three viable options exist, present only those rather than inventing filler. Do not repeat the
recommendation after the options.

### Example

1. Client default (Recommended)

   ```go
   client := &http.Client{Timeout: 5 * time.Second} // Apply one timeout to every request.
   ```

   Smallest choice when every request should use the same timeout.

2. Request context

   ```go
   ctx, cancel := context.WithTimeout(context.Background(), 5 * time.Second)
   defer cancel()
   req = req.WithContext(ctx) // Limit only this request.
   ```

   Best when different calls need different timeouts.

3. Transport timeout

   ```go
   transport := &http.Transport{ResponseHeaderTimeout: 5 * time.Second} // Bound one phase of the exchange.
   client := &http.Client{Transport: transport}
   ```

   Useful when only response-header latency should be bounded.

## Iterate

When I ask you to iterate, optimize for rapid feedback between us. Address my latest input, make enough progress for me
to react meaningfully, then let me respond before expanding into later choices or a finished answer. Use short
questions, explanations, code, or revisions as appropriate until I ask to finalize, plan, apply, park, or move on.
