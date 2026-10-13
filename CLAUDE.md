# Swift Git Kit

A thin, synchronous Swift wrapper over the `git` command-line tool — repository status, per-line diff markers, phantom removed-line data for inline diffs, blame, staging actions, branch identity, and worktree enumeration. Pure Foundation, zero dependencies, no libgit2.

- Module `GitKit` in `Sources/GitKit`; tests in `Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+, no dependencies unless the README says so.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.

## Module map

- `Core/` — the engine: Git (the one launch point: fixed environment, stripped variables, timeouts, lossy decode), SideBySideDiff
- `Enums/` — enums with no behaviour beyond their cases and labels: GitChangeKind, GitOperation
- `Errors/` — every Error type, one per file: GitCommitError
- `Internal/` — non-public machinery: Git+Parsing, GitScratchIndex
- `Models/` — value types — the shape of a thing, nothing else: BlameInfo, GitDirStamp, GitRunResult, GitStatusEntry, GitStatusMap, GitWorktree, HunkHeader, WorktreeSummary, SideBySideRow
- `Support/` — pure helpers: GitDiffFlags, NameStatusParser, PorcelainStatusParser
- `Operations/` — the engine: operations: Git+Actions, Git+Blame, Git+BlobHashes, Git+Checkpoint, Git+Clone, Git+Commit, Git+Diff, Git+InProgress, Git+Info, Git+Init, Git+Log, Git+MergeBase, Git+Status, Git+TextDiff, Git+WorkingTreeDiff, Git+Worktree, GitDirStamp+Resolve, GitHubCLI

## Rules

@CONTRIBUTING.md

- **Auditing? Read `AUDIT.md` first** — what the last full audit checked and fixed, and the known non-issues to skip; extend it, do not redo it.
