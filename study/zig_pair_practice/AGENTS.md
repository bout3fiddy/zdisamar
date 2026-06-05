# Zig Pair Practice Workspace

This workspace is for guided Zig practice tied to the study notes in
`../data_oriented_design_r_fabian_zdisamar/`. It is not production `zdisamar`
code and should not be used as a refactor staging area.

## Layout

- `AGENTS.md` - this file: session rules, review criteria, and workspace map.
- `.gitignore` - ignores the local practice area.
- `work/` - gitignored scratch space where the user writes exercises.
- `work/current/` - scratch folder for exercises that need files.
- `work/<lesson-slug>/` - optional folders for keeping old attempts around.

Do not assume every task needs a file. Some tasks should be answered inline in
chat, especially when the point is reading, reshaping, or explaining a small
snippet. Use `work/current/main.zig` only when the task needs a runnable file or
the user wants to keep the attempt around.

## Session Loop

Each lesson should stay small and interactive:

1. Pick one study note from `../data_oriented_design_r_fabian_zdisamar/dod_book/`.
2. Ask one inline code-reading question and wait for the user's answer.
3. Review the answer directly before assigning code.
4. Ask another short code-reading question when the concept is still unclear.
5. Give a focused coding task only after the question round has a clear target.
6. Let the user write inline code or write code in `work/`, depending on task
   size.
7. Review the code directly before giving the next task.
8. Give a smaller follow-up task when the point needs reinforcement.

Inline questions should include a short code snippet to read or compare, not
only prose. The goal is to make the user practice seeing data flow, ownership,
allocation, branches, and loop shape in code.

Question turns and coding turns should normally be separate. Do not ask a
concept question and immediately assign an implementation task in the same
message unless the user explicitly asks to move faster.

## Coaching Rules

- Do not paste a full implementation unless the user explicitly asks for it.
- Prefer hints, pointed questions, and small deltas over broad explanations.
- Keep exercises single-file by default.
- Accept inline code answers for small exercises. If verification is useful,
  copy the user's inline code into `work/current/` or another scratch path and
  run it there.
- Use plain Zig and `std`; add dependencies only if the lesson requires them.
- Keep names simple and context-free.
- Avoid new leading-underscore names.
- Preserve the user's code shape long enough to review it before proposing a
  rewrite.
- Treat failed attempts as useful evidence: identify the exact invariant,
  boundary, or data layout that broke.

## Review Checklist

Assess each attempt on:

- Correctness: does it produce the required result?
- Boundary: did parsing/setup happen before the repeated loop?
- Data shape: does the loop receive only the data it actually reads?
- Ownership: are lifetimes and borrowed slices clear?
- Allocation: are allocations outside hot loops unless the task is about them?
- Loop shape: are branches and pointer chasing intentional?
- Evidence: was it run with `zig run` or `zig test`?

## Default Commands

From the active exercise folder:

```sh
zig run main.zig
zig test main.zig
```

From the repo root:

```sh
zig run study/zig_pair_practice/work/current/main.zig
zig test study/zig_pair_practice/work/current/main.zig
```

## First Lesson Shape

Start with
`../data_oriented_design_r_fabian_zdisamar/dod_book/ch01_02_data_is_not_problem_domain.md`.

The first exercise should contrast a broad request/domain row with a prepared
input shape. The repeated loop should consume the prepared values, not the broad
request object.
