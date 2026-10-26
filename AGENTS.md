# Swift Git Kit

A thin, synchronous Swift wrapper over the `git` command-line tool — repository status, per-line diff markers, phantom removed-line data for inline diffs, blame, staging actions, branch identity, and worktree enumeration. Pure Foundation, zero dependencies, no libgit2.

- Module `GitKit` in `Sources/GitKit`; tests in `Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+, no dependencies unless the README says so.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.

## Module map

- `Core/` — the engine: Git (the one launch point: fixed environment, stripped variables, timeouts, lossy decode), SideBySideDiff (+ `changedWords` for modified pairs), IntralineDiff (the words that changed inside a changed line: token LCS, a rewrite under 40% shared gets nothing, UTF-16 ranges; `marks(in:)` pairs a unified diff's removed/added runs) — `nestedRepoRoots` walks with FoundationExtensions `FileManager.walk`, so a folder opened through a link finds its checkouts, and skips a folder its `skipsFolder` test names (a game engine's cache)
- `Enums/` — enums with no behaviour beyond their cases and labels: HunkRevertOutcome (edit / noChange / textChanged), GitChangeKind, GitOperation, DiffFileKind (added / deleted / renamed / modified / binary, read from a file's diff header)
- `Errors/` — every Error type, one per file: GitCommitError, GitPushError
- `Internal/` — non-public machinery: Git+Parsing, GitScratchIndex
- `Models/` — value types — the shape of a thing, nothing else: BlameInfo (`uncommitted` / `isUncommitted`: git's "Not Committed Yet" in one place), CheckoutSet (the primary repository and the checkouts nested below an opened folder, deepest first), GitBranchStatus, DiffFileSummary (one file's paths, kind and +/− counts from its diff), GitDirStamp, GitPushTarget (remote, branch, whether the push publishes), GitPendingPush (the target and the commits ahead of it), HunkRevertEdit (a UTF-16 range and the base's lines), GitLFSPointer (+Reading: the pointer Git LFS leaves where a file was not downloaded, read exactly as git-lfs's own decoder reads one — `lfs/pointer.go`: fewer than 1,024 bytes, the text trimmed, `\n` lines with a trailing `\r` dropped, version/oid/size in order with `ext-<digit>-<name>` lines before size, its three version URLs, ASCII lower-case hex), GitRunResult, GitStatusEntry, GitStatusMap, GitWorktree, HunkHeader, WorktreeSummary, SideBySideRow, GitHistoryEntry (a commit with its patch to one file or line range)
- `Extensions/` — CheckoutSet+Routing (`root(for:)` deepest-first, a nested root holds itself; `grouped` for one git call per repository; `aliases(ofOpened:)` by canonical path), HunkHeader+Section (`section(of:)` kept whole past a second `@@`; `isWhitespaceOnly`)
- `Support/` — pure helpers: HunkRevert (undo one hunk as an edit to the current text, from any unified diff; refuses when the text no longer holds the hunk; `\ No newline` honoured on the base side), GitDiffFlags (`patch(ignoringWhitespace:)`: `--ignore-all-space` for diffs a person reads, never the gutter's), DiffChunks (a multi-file diff split back per path, in order or by path; `summary(of:)`; git's C-quoted paths unquoted), NameStatusParser, PorcelainStatusParser
- `Operations/` — the engine: operations: Git+Actions, Git+Blame, Git+BlobHashes, Git+BranchStatus (`branchStatus` in one call, `isDetachedHead`, `commitExists`; `isLinkedWorktree` canonically), Git+Checkpoint, Git+Clone, Git+Commit, Git+Diff, Git+Diff (`gutterDiff`: the one-file `-U0` diff the gutter and Undo This Change share), Git+FileAtHead (`headText(of:)`, `addedLines(for:)`: the two reads every change fact starts from), Git+FileVersions (`fileVersions(path:commits:)`: one file at many commits, two cat-file runs, each distinct blob read once; only object ids are asked), Git+HeadDiff (each file's diff against HEAD from one batched run), Git+InProgress, Git+Info (+ `headCommit`, `isInsideWorkTree`), Git+Init, Git+Log (+ fileHistory across renames, lineHistory via `log -L`), Git+MergeBase, Git+Push (`pushTarget(repoRoot:)` from configuration alone; `pendingPush` — what a push would send now, nil when nothing; `push(repoRoot:)`: to exactly the tracked branch, `HEAD:<merge ref>`, whatever `push.default` says; a branch tracking nothing published with `-u` to the only remote or `origin`; the pre-push hook runs; nothing prompts), Git+Status, Git+TextDiff, Git+WorkingTreeDiff, Git+Worktree, GitDirStamp+Resolve, GitHubCLI

## Rules

Read `CONTRIBUTING.md` for the folder layout and the pull-request rules.

@CONTRIBUTING.md

- **Auditing? Read `AUDIT.md` first** — what the last full audit checked and fixed, and the known non-issues to skip; extend it, do not redo it.
