# Audit log

Last full audit: **17 Sep 2026** — every source file covered by the MECHANICAL checks below (build warnings, tests,
dead-code and risk-pattern scans, docs drift); line-by-line logic review was targeted at the areas changed since
5 Sep 2026, not the whole tree. Nothing needs re-scanning unless it changed after that date. Add a dated line under *History* when you audit again, and keep the
*Known non-issues* list current so the next pass skips them.

## What a full audit checks

1. `swift build` warnings (none allowed except those listed under known non-issues) and `swift test` green.
2. Dead code: every `func`/type/property declared once and referenced nowhere in the app or the family
   (`grep -w` across `*.swift` AND non-Swift files — selectors and MCP names live in strings). Protocol
   requirements, `override`s, `@objc` actions and public API are NOT dead because Sidewatch does not call them.
3. Risky patterns: `Timer` without `invalidate`, `addObserver(forName:)` without `removeObserver`, `as!`, `try!`
   outside literal regexes, `fatalError` outside `init?(coder:)`, `print(` outside harnesses, TODO/FIXME left behind.
4. Docs drift: every name in CLAUDE.md's module map exists; AGENTS.md mirrors CLAUDE.md; README Usage matches the API.

## Result on 17 Sep 2026

- Build: clean. Tests: green.
- Nothing to fix in this package.

## Logic review — 18 Sep 2026

Every source file read line by line, with the app's git and review code, and each finding reproduced in a throwaway
repository before it was fixed (the tests below fail against the previous code):

- `Git.discard(_:kind:.untracked)` was a bare `removeItem`: no under-root check (the tracked kinds had one), no file
  check — and `git status -uall` reports a nested repository as ONE untracked `nested/` entry, so "discard this
  untracked file" on that row was `rm -rf` of a whole checkout, `.git` included. Now: out-of-root refused, directories
  refused, and a file goes to the Trash (`trashUntracked`), never a permanent delete. Tests:
  `testDiscardUntrackedRefusesAFileOutsideTheRepo`, `…RefusesADirectoryAndLeavesANestedRepoIntact`,
  `…MovesTheFileToTheTrash`.
- `checkpointDiff(from:to:nil, path:)` ignored `path` for the diff itself (only the spliced untracked files were
  filtered); the two-commit branch narrowed correctly. Sidewatch never passed a path here, so it was latent. Test:
  `testCheckpointDiffAgainstWorkingTreeCanNarrowToOnePath`.
- `Git.counts(_:)` was dead — `HunkHeader.parse` replaced it — and survived on its own tests. Removed with them.

Reviewed and sound: `run` (ProcessRunner drains both streams), `repoRoot`/`relativePathIfUnderRoot`/`canonicalPath`,
`nestedRepoRoots`, status parsing (rename old-path field skipped), `lineDiff`/`lineChangesAll`/`untrackedDiff`,
checkpoint create/anchor/prune/sanitise, worktree list/remove, `GitStatusMap` aliases and merge, `HunkHeader`,
`SideBySideDiff`, log/show/clone/merge-base/blame, `GitHubCLI`.

## Known non-issues (do not "fix" these again)

- `Git.remoteURL(repoRoot:remote:)` has no caller in Sidewatch — public API, kept.
- Tests take ~80 s (real git processes); that is expected, not a hang.
- `testDiscardUntrackedMovesTheFileToTheTrash` really trashes a temp file and removes it from `~/.Trash` afterwards.

## History

- 17 Sep 2026 — full audit (app + all 20 libraries), Claude with David.
- 18 Sep 2026 — line-by-line logic review (see the section above); 125 tests, ~80 s.
