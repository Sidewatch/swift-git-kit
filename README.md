# Swift Git Kit

A thin, synchronous Swift wrapper over the `git` command-line tool — repository status, per-line diff markers, phantom removed-line data for inline diffs, blame, staging actions, branch identity, and worktree enumeration. Pure Foundation, zero dependencies, no libgit2.

## Features

- 📋 **Working-tree status** — `Git.statusEntries(repoRoot:)` returns one `GitStatusEntry` (path, kind, the old path of a rename) per changed file, parsed from `git status --porcelain=v1 -z` (added / modified / deleted / untracked / renamed / conflicted); `Git.status(repoRoot:)` is the same as `(path, kind)` pairs
- 📏 **Per-line gutter markers** — `Git.lineChanges(for:repoRoot:)` maps each 1-based line to a `GitChangeKind` for editor change bars; a pure deletion is keyed at the line below the removal, where its ghost rows sit
- 👻 **Inline-diff phantom rows** — `Git.removedLines(for:repoRoot:)` returns deleted lines keyed by the surviving line they belong above, for Cursor-style inline diffs
- ➕➖ **Working-tree diff stat** — `Git.diffStat(repoRoot:)` sums total insertions/deletions vs `HEAD` (`git diff --numstat`), for a "+312 −332" badge; `WorktreeSummary` carries these per worktree
- 🌲 **Whole-tree diff in one process** — `Git.workingTreeDiff(repoRoot:from:)` diffs the working tree, untracked files included as new content, against any commit (or `Git.diffBase(repoRoot:)`), through a scratch index that leaves the real one untouched; `workingTreeChangedFiles` is the parsed `--name-status` form
- 🧾 **Fast single-line blame** — `Git.blame(for:line:repoRoot:)` returns author, a short relative age, and the commit summary
- ✅ **Staging actions** — `stage`, `unstage`, and a destructive but undoable `discard` (revert-to-HEAD; an untracked or newly added file goes to the Trash; a conflicted file or a gitlink is refused)
- 📝 **Commit of chosen paths** — `Git.commit(entries:message:repoRoot:)` commits exactly the entries given through a scratch index seeded from `HEAD`, so a partial staging of any other file survives; hooks and signing run as configured, and a refusal comes back in git's own words. Refused while a merge, rebase, cherry-pick, revert, bisect or `am` is in progress (`Git.inProgressOperation(repoRoot:)`, `Git.rebaseHeadName(repoRoot:)`)
- 🧭 **Repo discovery** — `Git.repoRoot(for:)` and repo-relative path resolution; `Git.blobHashes(paths:repoRoot:)` hashes many files in one process; `Git.headContents(paths:repoRoot:)` reads their committed bytes in one
- **New repositories** — `Git.initRepository(at:)` runs `git init` in a folder (its own repository even inside another checkout) and returns the `GitRunResult`, so a failure reads in git's own words
- 🌿 **Branch identity** — `Git.currentBranch(repoRoot:)` returns the checked-out branch name (the branch the first commit will land on while `HEAD` is unborn), falling back to the short commit SHA on a detached `HEAD`; `Git.localBranches(repoRoot:)` lists real branches only
- 🛡️ **One launch point** — every call runs with literal pathspecs (`app/[id]/page.tsx` is a path, not a glob), without writing `.git/index` on a read (`GIT_OPTIONAL_LOCKS=0`, `diff.autoRefreshIndex=false`), without credential prompts, with the repository's own code kept out (`core.fsmonitor=false` always; `core.hooksPath=/dev/null` for everything but `Git.commit`, which runs the person's hooks), with the launching shell's `GIT_DIR`/`GIT_INDEX_FILE`/diff overrides stripped, with a timeout (60 s for reads, 600 s for commits, clones and captures), and with stdout decoded lossily so one stray byte cannot blank a diff. Every parsed `diff` carries `--no-ext-diff --no-textconv` and pinned prefixes and hunk context, so a user's diff configuration cannot change what is read
- 🌳 **Worktree enumeration** — `Git.worktrees(repoRoot:)` lists every `GitWorktree` (path, branch, main/linked) via `git worktree list --porcelain`, with `isCurrent(relativeTo:)` for symlink-safe "which one am I in?" checks
- 📊 **Worktree change summaries** — `Git.worktreeSummaries(repoRoot:)` pairs each worktree with a per-kind tally of its uncommitted changes (`WorktreeSummary` — `added`/`modified`/`deleted`/`untracked`/`renamed`/`conflicted`, `changeCount`, `isDirty`, plus `insertions`/`deletions`), for a parallel-agent review rail that shows "which worktree has unreviewed work". `Git.removeWorktree(_:repoRoot:force:)` archives a finished linked worktree (`git worktree remove`; refuses a dirty tree unless forced)
- **Git-dir stamp** — `GitDirStamp.resolve(repoRoot:)` finds the files whose modification times move when git state does (HEAD, the index, reflogs, `FETCH_HEAD`, in-progress markers, the upstream ref, every remote's refs and every linked worktree's HEAD); `stat()` reads them with no spawn, so a poll can tell "something changed" from a few dozen stats instead of a subprocess, and `infoExcludeMoved` says when the ignore rules did.
- 🗺️ **Status lookup map** — `GitStatusMap.build(status:repoRoot:)` turns a status list into O(1) per-path lookups: `kind(for:)` for a file's change kind and `directoryContainsChanges(_:)` for "does this collapsed folder hold changes?", keyed under every `/private/var` ↔ `/var` alias of the repo root so lookups never miss. `GitChangeKind.letter` gives the single-letter badge (A/M/D/R/U, C for a conflict)
- 🪶 **Small** — Foundation plus swift-foundation-extensions (FoundationExtensions, ProcessRunner); shells out to the system `git`
- 🧪 **Fully tested** — integration tests against throwaway repos (including linked and detached worktrees) plus direct unit tests of the diff-hunk and relative-time parsers, and the status-map path keying / ancestor marking / alias resolution

## Requirements

- macOS 14+
- Swift 6.2+ (Swift 6 language mode)
- A working `git` on disk (defaults to `/usr/bin/git`; override via `Git.executable`)

> **Platform note:** this wraps the `git` binary via `Process`, so it is macOS-only (not iOS/tvOS/watchOS).

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Sidewatch/swift-git-kit.git", from: "0.1.0")
]
```

## Usage

```swift
import GitKit

// Locate the repository containing a file.
guard let root = Git.repoRoot(for: someFileURL) else { return }

// What changed?
for entry in Git.statusEntries(repoRoot: root) {
    print(entry.kind.letter, entry.path, entry.oldPath ?? "")   // e.g. R  Sources/New.swift Sources/Old.swift
}

// Per-line change bars for the gutter. A pure deletion is keyed at the line below the
// removal (1 for a deletion before the first line; one past the last line for one at the end).
let marks = Git.lineChanges(for: fileURL, repoRoot: root)   // [Int: GitChangeKind]

// Removed lines to ghost inline, keyed by the new-file line they sit above.
let removed = Git.removedLines(for: fileURL, repoRoot: root)   // [Int: [String]]

// The whole working tree, untracked files included, as one diff — one process, the index untouched.
let everything = Git.workingTreeDiff(repoRoot: root, from: Git.diffBase(repoRoot: root))
let changed = Git.workingTreeChangedFiles(repoRoot: root, from: "HEAD")   // [GitStatusEntry]

// Each open file's diff against HEAD from ONE batched git diff: untracked files as all-new,
// clean files "", an unborn HEAD against the empty tree. Every reading diff takes `ignoringWhitespace`
// (`--ignore-all-space`); the gutter's line marks above never do.
let perFile = Git.headDiffs(paths: ["a.swift", "new.txt"], repoRoot: root, ignoringWhitespace: true)  // [String: String]
let chunks = DiffChunks.byPath(everything ?? "")   // a multi-file diff split back per file
let summary = DiffChunks.summary(of: chunks["a.swift"] ?? "")   // DiffFileSummary: paths, kind, +/− counts

// The file as HEAD has it, the lines the working tree added, and HEAD's commit.
let before = Git.headText(of: "a.swift", repoRoot: root)        // nil for a new file
let added = Git.addedLines(for: "a.swift", repoRoot: root)      // [String]
let sha = Git.headCommit(repoRoot: root)                         // nil before the first commit

// The words that changed inside changed lines, for tinting over the line's own colour.
let words = IntralineDiff.marks(in: diffText.components(separatedBy: "\n"))   // [line index: [NSRange]]
let pair = IntralineDiff.ranges(old: "timeout: 30", new: "timeout: 60")    // old ["30"], new ["60"]

// History: one file's commits with their patches (across renames), or one line range's (git log -L).
let fileHistory = Git.fileHistory(path: "Sources/App.swift", repoRoot: root)             // [GitHistoryEntry]
let rangeHistory = Git.lineHistory(path: "Sources/App.swift", lines: 40...62, repoRoot: root)

// Who last touched line 42?
if let blame = Git.blame(for: fileURL, line: 42, repoRoot: root) {
    print("\(blame.author) · \(blame.timeAgo) · \(blame.summary)")
}

// Staging actions.
Git.stage(fileURL, repoRoot: root)
Git.unstage(fileURL, repoRoot: root)
Git.discard(fileURL, kind: .modified, repoRoot: root)   // destructive; false for a conflict or a gitlink

// Commit exactly the ticked entries; other files' partial staging is left as it was.
switch Git.commit(entries: ticked, message: "Fix the thing", repoRoot: root) {
case .success(let sha): print("committed", sha)
case .failure(.operationInProgress(let op)): print("finish the \(op) first")
case .failure(.nothingToCommit): print("nothing to commit")
case .failure(.failed(let stderr)): print(stderr)   // a hook's refusal, in its own words
}
if let op = Git.inProgressOperation(repoRoot: root) {
    print(op, Git.rebaseHeadName(repoRoot: root) ?? "")   // e.g. rebase feature-x
}

// Everything a branch indicator shows, in one call (off the main thread).
let status = Git.branchStatus(repoRoot: root)      // branch, detached, operation, ahead/behind, worktrees
let linked = status.isLinkedWorktree(root)          // a `git worktree add` checkout, not the main one
let alive = Git.commitExists(storedSHA, repoRoot: root)

// A folder holding several repositories: which one a file belongs to, and one git call per repository.
let checkouts = CheckoutSet(primary: Git.repoRoot(for: folder), nested: nestedRoots)
let owner = checkouts.root(for: fileURL)            // the deepest checkout holding it, else the primary
let (byRoot, outside) = checkouts.grouped(openFiles) // [root: [file: relative path]]

// A hunk header's section heading, and hunks that only change whitespace.
let section = HunkHeader.section(of: "@@ -10,3 +10,4 @@ func render() {")   // "func render() {"
let reindentOnly = HunkHeader.isWhitespaceOnly(hunkBodyLines)

// Which branch is checked out? (short SHA when HEAD is detached)
let branch = Git.currentBranch(repoRoot: root)   // e.g. "main"

// Hash many working-tree files in one process; a missing or unreadable path has no key.
let hashes = Git.blobHashes(paths: ["a.swift", "b.swift"], repoRoot: root)   // [String: String]
let before = Git.headContents(paths: ["a.swift", "b.swift"], repoRoot: root) // [String: Data], raw blobs at HEAD, one cat-file
switch Git.push(repoRoot: root) {                                 // the tracked branch, or published with -u
case .success(let target): print("pushed to", target.name)       // "origin/main"; target.publishes when -u set it
case .failure(.noRemote), .failure(.detachedHead): break
case .failure(.failed(let stderr)): print(stderr)                // a rejection or a pre-push hook, in git's words
}
if let diff = Git.gutterDiff(for: fileURL, repoRoot: root),                  // the -U0 diff the gutter marks
    case .edit(let edit) = HunkRevert.edit(at: 42, in: text, diff: diff) {    // the change at line 42 …
    textView.insertText(edit.replacement, replacementRange: edit.range)      // … put back as HEAD has it, undoably
}
let versions = Git.fileVersions(path: "a.swift", commits: [sha1, sha2], repoRoot: root) // [Data?], nil where a commit lacks it
let ignored = Git.ignoredPaths(["dist/new.js", "src/a.swift"], repoRoot: root)  // Set<String>, git check-ignore, one run

// Raw calls go through the same launch point (environment, timeout, lossy decode).
let out = Git.run(["diff", "--no-color", Git.diffBase(repoRoot: root), "--", "a.swift"], in: root)
let result = Git.runCapturingError(["commit", "-m", "msg"], in: root, timeout: Git.longTimeout)
print(result.status, result.stdout, result.stderr, result.message)

// All worktrees of the repository, main first.
for tree in Git.worktrees(repoRoot: root) {
    let marker = tree.isCurrent(relativeTo: root) ? "→" : " "
    print(marker, tree.branch ?? "(detached)", tree.path.path, tree.isMain ? "[main]" : "")
}

// Cheap change detection: resolve once (three spawns), then stat on every tick (none).
if var stamp = GitDirStamp.resolve(repoRoot: root) {
    let before = stamp.stat()
    // … later …
    if stamp.stat() != before { print("git state moved") }
}
```

### Using a non-default git

```swift
Git.executable = "/opt/homebrew/bin/git"
```

### Proving a mode runs no git

`Git.launchCount` counts every launch in the process, a failing command included. Read it, do the work, read it
again: a host's "git off" mode can show it launches nothing.

## Notes

- All calls are **synchronous** and cheap. When scanning a whole repository, dispatch them off the main queue.
- `discard` is **destructive**: `.untracked` and `.added` files are moved to the Trash (a directory — how `git status` lists a nested repository — is refused, never removed); `.renamed` returns under its old name; all other kinds are restored from `HEAD`, discarding local edits. Every kind refuses a path outside the repository, a `.conflicted` file, and a gitlink (`Git.isGitlink(_:repoRoot:)`).
- Actions like `unstage` (`git restore --staged`) require an existing `HEAD` — i.e. a repository with at least one commit. Diffs "versus `HEAD`" fall back to the empty tree before the first commit (`Git.diffBase(repoRoot:)`), so staged files show as new; `currentBranch` names the unborn branch.
- Escape hatch: `Git.run(_:in:)` runs any raw `git` invocation and returns its stdout (`nil` on failure or timeout); `Git.runCapturingError` keeps stderr and the status. Both run under the package's fixed environment: literal pathspecs, no index writes on reads, no terminal prompts, the launching shell's `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`, `GIT_COMMON_DIR`, `GIT_NAMESPACE`, `GIT_DIFF_OPTS`, `GIT_EXTERNAL_DIFF`, `GIT_CONFIG_PARAMETERS` and the pathspec overrides removed. A caller's `environment` is layered last and wins. Every call also sets `core.fsmonitor=false` and, unless it passes `hooks: true`, `core.hooksPath=/dev/null` — a checkout's monitor command and hooks are its own code, run only by the person's `Git.commit`. Hooks a `commit` runs inherit this environment.
- Under `diff.autoRefreshIndex=false`, a raw `diff --name-status` or `--raw` lists a stat-stale (touched but unchanged) file as `M`; patch and `--numstat` forms do not. `workingTreeChangedFiles` refreshes its scratch index first and is exact.
- `relativePath(_:root:)` keeps a basename fallback for display names only; no read or mutating operation uses it — a file outside the repository is refused (empty / `nil` / `false`) without running git.

## For agents

Read `CONTRIBUTING.md` first: the folder layout and the PR rules. `swift test` is the whole
check, and a new test must fail before the change it covers. `AGENTS.md` carries a
module map (`CLAUDE.md` imports it).

## License

MIT — see [LICENSE](LICENSE).
