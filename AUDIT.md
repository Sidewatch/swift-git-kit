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

- **A CRLF file's diff was mis-parsed** (found later the same day, in the CRLF sweep): `lineDiff` and
  `lineChangesAll` split the diff with `split(separator: "\n")`, and in Swift `"\r\n"` is ONE
  `Character`, so the content lines of a Windows-authored file were never divided. Measured in a
  scratch repo: the gutter marks stopped after the FIRST hunk (the second `@@` rode along inside
  the first hunk's removed text), a two-line deletion ghosted as one row reading `b\r\n-c\r\n`,
  and the file AFTER a CRLF file in `git diff HEAD` had its hunks filed under the CRLF file's path
  (its `diff --git` header was swallowed too). Both loops use `components(separatedBy: "\n")`
  (a UTF-16 split, what `SideBySideDiff` always used) and a ghost row drops its trailing `\r`.
  Three tests fail against the old parser. Blame's porcelain, `--numstat`, refs and porcelain
  status carry no CR before their `\n`, so their Character splits stand.

Reviewed and sound: `run` (ProcessRunner drains both streams), `repoRoot`/`relativePathIfUnderRoot`/`canonicalPath`,
`nestedRepoRoots`, status parsing (rename old-path field skipped), `lineDiff`/`lineChangesAll`/`untrackedDiff`,
checkpoint create/anchor/prune/sanitise, worktree list/remove, `GitStatusMap` aliases and merge, `HunkHeader`,
`SideBySideDiff`, log/show/clone/merge-base/blame, `GitHubCLI`.

## Hostile-environment review — 9 Oct 2026

Every finding below was reproduced against git 2.56 in a scratch repository before it was fixed,
and each fix ships with a test that fails against the previous code (the mutant is named). Do not
re-probe these; the tests pin them.

### What was probed, and the outcome

- **Pathspecs glob.** `app/[id]/page.tsx` matched `app/i/page.tsx` in `add`, `restore`, `diff`,
  `ls-files`, `log --follow`; `:colon.txt` was pathspec magic. `GIT_LITERAL_PATHSPECS=1` on every
  call fixes all of it and is harmless for blame, `diff --no-index`, `show rev:path`, `add -A`,
  `ls-files --others` and status. `:(literal)` is never used (it fails combined with the env).
  Pinned by `GitPathspecTests` (mutant M1: the variable renamed — four of five tests fail).
  Note for fixtures: two files with IDENTICAL content make `log --follow` treat one as a copy of
  the other; that is rename detection, not globbing.
- **Index rewrites on reads.** `git status` and every `git diff` form rewrite `.git/index` when a
  tracked file is stat-stale (touched, content unchanged); an agent's own `git commit` racing the
  lock fails. `GIT_OPTIONAL_LOCKS=0` stops `status` only; the diff forms are gated on
  `diff.autoRefreshIndex`, set to `false` through `GIT_CONFIG_COUNT=1` / `GIT_CONFIG_KEY_0` /
  `GIT_CONFIG_VALUE_0` so raw calls get it too. Measured: with both set, the index mtime stays put
  across status, `diff`, `diff --unified=0`, `--numstat`, `lineChangesAll`, the checkpoint reads,
  and the raw `diff --no-color HEAD -- path` the app runs; output for a stat-stale file is empty.
  Caveat found on the way: under `diff.autoRefreshIndex=false`, `diff --name-status` and `--raw`
  still list a stat-stale file as `M` (no content comparison for those formats); patch and
  `--numstat` forms do not. `workingTreeChangedFiles` therefore passes `-c diff.autoRefreshIndex=true`
  on its SCRATCH index (a `-c` outranks the env form; it refreshes the scratch copy, never the real
  index). Pinned by `GitIndexUntouchedTests` (mutants M2 `GIT_OPTIONAL_LOCKS=1`, M3
  `GIT_CONFIG_COUNT=0`). The `diff-index -p` replacement from the brief was NOT evaluated: the env
  route makes it unnecessary.
- **Inherited environment.** A `GIT_DIR` exported by the launching shell redirected every call.
  `ProcessRunner.run(removing:)` strips `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`,
  `GIT_OBJECT_DIRECTORY`, `GIT_COMMON_DIR`, `GIT_NAMESPACE`, `GIT_DIFF_OPTS`, `GIT_EXTERNAL_DIFF`,
  `GIT_CONFIG_PARAMETERS`, `GIT_GLOB_PATHSPECS`, `GIT_NOGLOB_PATHSPECS`, `GIT_ICASE_PATHSPECS`; a
  caller's `environment` is layered last and wins (how every scratch-index call works). Pinned by
  `GitRunTests` (mutant M4: `GIT_DIR` left in).
- **Lossy decode.** One non-UTF-8 byte in a diff made `String(data:encoding:)` nil and the whole
  result `""`. `String(decoding:as:)` everywhere (mutant M5: strict decode — the stray byte no
  longer appears as U+FFFD, the diff is empty).
- **Timeouts.** `Git.run` never passed one. Default 60 s (`Git.defaultTimeout`), 600 s
  (`Git.longTimeout`) for commit, add/restore/rm, checkpoint capture, clone, fetch, checkout,
  worktree remove; a timed-out run is `nil`. `ProcessRunner`'s grandchild behaviour is recorded in
  its own audit (`swift-foundation-extensions/Docs/Audits/ProcessRunner.md`): `Process` kills the
  child's process group on `terminate()`, so only a `SIGTERM`-ignoring grandchild blocked the old
  drain. Pinned by `testATimedOutRunReturnsNilPromptly` (mutant M6: timeout not passed — 5 s).
- **Hostile diff/log/blame configuration.** `diff.external` replaced every diff's output;
  `diff.interHunkContext=5` fused the hunks of a `--unified=0` diff; `diff.noprefix` /
  `diff.mnemonicPrefix` broke the `a/`/`b/` header stripping; a textconv driver shifted line
  numbers; `log.showSignature` interleaved gpg lines into `--pretty=format:` records; the
  two-commit checkpoint diff lacked `--no-color`; a global `blame.ignoreRevsFile` naming a file
  absent from the repo made every blame exit 128. Every diff carries `GitDiffFlags.plain`
  (`--no-color --no-ext-diff --no-textconv`); `--unified=0` diffs add `--inter-hunk-context=0`;
  header-parsed diffs add `--src-prefix=a/ --dst-prefix=b/`; `log`/`show` add
  `--no-show-signature`; blame retries once with `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1`.
  Pinned by `GitHostileConfigTests`, which snapshots every read API under a gitconfig holding all
  of the above (plus a repo textconv driver) and under `/dev/null`, and asserts equality plus the
  real values (mutants M7: all flags off; M8: no blame retry).
- **`--- a/my file.ts<TAB>`.** git appends a TAB to a header whose path has spaces; `headerPath`
  drops it. Covered by the hostile test's `my file.txt` (the all-files map keys it correctly).
- **Unborn `HEAD`.** `git diff HEAD` exits 128 before the first commit. `Git.diffBase(repoRoot:)`
  is `HEAD` or the empty tree (`hash-object -t tree /dev/null`, so SHA-256 repositories get the
  right id); `lineDiff`, `lineChangesAll`, `diffStat` try `HEAD` and fall back only on failure
  (no extra spawn in the common case). `currentBranch` falls back to `symbolic-ref --short HEAD`
  and now names the unborn branch (contract change; `testCurrentBranchOnUnbornHeadIsTheBranchName`
  replaces `testCurrentBranchNilForUnbornHead`). Mutants M9 (no fallback), M25 (no unborn name).
- **Pure deletion key.** `@@ -3 +2,0 @@`, `+0,0`, `+4,0` at EOF: the mark used `max(1, newStart)`
  while the ghost anchor used `newStart + 1`, so `+0,0` and `+1,0` collided on line 1 and the
  mark sat a row above its ghosts. Both now key `HunkHeader.deletionLine` (`newStart + 1`): 1 for
  a deletion before the first line, one past the last line for a deletion at EOF. Pinned by
  `GitDeletionMarkTests` (mutant M10: `max(1, newStart)`).
- **Status codes.** `AD` (added, then deleted from the tree) read as added; conflicts (`UU`,
  `AA`, `DD`, `AU`, `UA`, `DU`, `UD`) read as modified/added/deleted; the old path of a rename was
  thrown away. `GitChangeKind.conflicted` (letter `C`), `GitStatusEntry` with `oldPath`,
  `Git.statusEntries`; `Git.status` is a projection. Mapping order: conflicts first (`DD` and `UD`
  have a `D` on the working-tree side), then Y == `D`, then `??`, then the index side. Pinned by
  `GitStatusEntryTests`, which produces every code from a real repository including a submodule
  pointer bump (` M sub`) and a nested repository (`?? nested/`) (mutants M11a: no conflict
  mapping; M11b: Y == `D` not honoured).
- **Pseudo-branches and prunable worktrees.** `git branch --format` listed `(HEAD detached at …)`
  and `(no branch, rebasing rb)`; `worktree list --porcelain` listed a worktree whose directory
  was deleted (`prunable`). `localBranches` uses `for-each-ref refs/heads` + `symbolic-ref -q
  --short HEAD`; `worktrees` skips `prunable` entries. Pinned by `GitBranchIdentityTests` (mutants
  M27: `git branch` listing; M26: `prunable` kept).
- **Operations in progress.** `Git.inProgressOperation` stats `rebase-merge/`, `rebase-apply/`
  (+`applying` → `am`), `MERGE_HEAD`, `CHERRY_PICK_HEAD`, `REVERT_HEAD`, `BISECT_LOG` under
  `rev-parse --absolute-git-dir` (a linked worktree's own directory); `rebaseHeadName` reads
  `rebase-merge/head-name`. Pinned by `GitInProgressTests` with real merge, rebase and cherry-pick
  conflicts (mutant M12: `rebase-merge` not checked).
- **Commit.** The app's `reset; add -- paths; commit` wiped partial staging of unticked files,
  split renames, and mid-merge committed conflict markers as a single-parent commit.
  `Git.commit(entries:message:repoRoot:)`: refuses while an operation is in progress; scratch
  index from `read-tree HEAD` (the empty tree when unborn); `add --` of every path and every
  rename's old path, skipping a path gone from disk and absent from `HEAD` (`add` would reject its
  pathspec), refusing a directory (a nested repository would become a gitlink);
  `diff-index --cached --quiet` for "nothing to commit"; `GIT_INDEX_FILE=<scratch> git commit -q
  -m` (hooks and `commit.gpgsign` run as configured; a hook's stdout is kept in the message);
  `git reset -q -- <paths>` syncs just those paths in the real index (verified to tolerate a path
  no longer in `HEAD`). Pinned by `GitCommitTests` (mutants M13: scratch seeded from the real
  index — the unticked hunk is committed; M14: old path dropped — `A new`, not `R100`; M15: no
  in-progress check). A mutant that reports only stderr on failure is EQUIVALENT for the hook
  test: git redirects a hook's stdout to stderr, so the hook's words arrive there either way;
  `GitRunResult.message` falls back to stdout for git's own notices, which print there.
- **Discard.** `.added` went through `restore`, a permanent delete; now Trash + `rm --cached`.
  `.conflicted` and gitlinks (`ls-files -s` mode `160000`, `Git.isGitlink`) are refused. Pinned by
  `GitDiscardTests` and the rewritten `testDiscardStagedAdditionRemovesFromIndexAndMovesTheFileToTheTrash`
  (mutants M17: no refusals; M18: `.added` via `restore`).
- **Checkpoints.** (a) `git diff <checkpoint>` against the REAL index read an untracked file the
  checkpoint had captured as `D`, then the untracked splice re-added it as `A`. Replaced by
  `Git.workingTreeDiff(repoRoot:from:paths:nameStatus:)` — public, so the app's All Changes view
  can replace its one `diff --no-index` per untracked file with one spawn: copy `rev-parse
  --git-path index` (under the common dir for a linked worktree) to a scratch `GIT_INDEX_FILE`,
  `add -N --pathspec-from-file=- --pathspec-file-nul` every `ls-files --others --exclude-standard`
  path except `nested/` entries and unreadable files (either makes `diff` exit 128 — found
  while probing), then `diff <from>`. Verified output on a tree with an untracked file predating
  the checkpoint, a staged new file and a tracked edit: `A stagednew.txt / M tracked.txt`, no `D`,
  the pre-existing file absent. `add -N` stores the empty blob once if the repository lacks it
  (`testWorkingTreeComparisonDoesNotWriteObjects` now warms up once). Pinned by
  `GitCheckpointIndexTests` and `GitWorkingTreeDiffTests` (mutants M19: scratch seeded with
  `read-tree <from>` — the staged new file vanishes; M20: no intent-to-add). (b) `add -A` exited
  128 on a `chmod 000` file or a commit-less nested repository and the capture was nil;
  `--ignore-errors` with exit 1 allowed (mutant M22). (c) Capture seeds the scratch index from a
  copy of the real one — always, a conflicted index included (`add -A` resolves each entry to the
  working tree; verified) — falling back to `read-tree HEAD` only when there is no index file.
  Measured on 5,000 files: `add -A` into a copied index 0.036–0.039 s, into a `read-tree HEAD` seed
  0.28–0.34 s (stat data lost, every file re-hashed). The working-tree diff recipe on the same tree
  with one untracked file: 0.05–0.07 s, against 0.045–0.05 s for the old `diff` + one `--no-index`
  — equal for one file, and the old recipe grew by one spawn per untracked file. (d)
  `--name-status -z` parsing (`R100\0old\0new\0`, `A\0path\0`) keeps `"` and `\` in names verbatim
  (mutant M21: `-z` dropped — the path comes back C-quoted).
- **`Git.blobHashes`.** One `hash-object --stdin-paths` spawn; it stops at the first path it cannot
  open (exit 128, the hashes so far on stdout), so missing, unreadable, directory and
  newline-bearing paths are filtered out first (mutant M23: no filter — the batch fails, `[:]`).
- **Reads of a file outside the root.** `lineDiff` and `blame` used `relativePath`'s basename
  fallback and ran git against an unrelated same-named file; now `relativePathIfUnderRoot`, no
  spawn. `relativePath` stays public for display names. Pinned by `GitOutOfRootTests`, whose
  `Git.executable` is a script that leaves a marker when launched (mutant M24: the fallback back).

### Facts recorded for the app (library behaviour the orchestrator relies on)

- `GitChangeKind.conflicted` is new; `WorktreeSummary.conflicted` counts it; `GitStatusMap` keeps it.
- `Git.run(_:in:)` gained a defaulted `timeout:`; `run(_:in:environment:…)` gained `timeout:` and
  `input:`; `Git.runCapturingError` returns `GitRunResult` (status, stdout, stderr, `message`).
- `Git.clone` goes through `runCapturingError` (same environment and `longTimeout`).

## Security review — 9 Oct 2026

- **A checkout's own code ran on every status.** `core.fsmonitor` in a repository's `.git/config`
  names a command git runs on each status and diff; `.git/hooks/post-index-change` runs on a `git
  add`. A clone carries both, so opening a repository ran whatever it chose, before anyone read a
  line. `Git.fixedEnvironment` now sets `core.fsmonitor=false` for every call (`GIT_CONFIG_KEY_1`,
  the env form that outranks every file) and `Git.environment(hooks:)` adds `core.hooksPath=/dev/null`
  unless the call passes `hooks: true`; `run(_:in:environment:…)` and `runCapturingError` take the
  flag, and `Git.commit` alone passes it — a person committing expects their pre-commit hook.
  Stage, unstage, restore, checkpoints (plumbing), clone and every read run none.
  `GitHookIsolationTests`: a monitor command that touches a marker never fires through the package
  but does through bare git (so the check is not vacuous); `post-index-change` and `post-checkout`
  hooks stay silent through stage/unstage/discard while `pre-commit` fires on `Git.commit`; the
  environment names both rules. Mutants: the fsmonitor value blanked — the marker appears;
  `environment(hooks:)` always returning the base — the index hook fires; `commit` with `hooks:
  false` — the pre-commit marker is missing. `testAFailingPreCommitHookReportsItsOwnWords` stays
  green.

## Committed contents and ignore verdicts — 10 Oct 2026

- **`Git.headContents(paths:repoRoot:)`**: the raw blobs of many paths at `HEAD` from ONE
  `cat-file --batch` (no filters, so no checkout's smudge command runs). Output carries file bytes,
  so it is read undecoded through `runData`, which launches through the same private `launch` as
  every other call (the environment, stripped variables and drained pipes are one code path).
  Missing, ambiguous and tree records are skipped in step; a path with a newline is never sent (it
  would be two requests and shift every record after it). Mutants, each failing
  `GitHeadContentsTests`: the record's trailing LF not skipped (2), trees kept (2), `missing` not
  recognised (2), output decoded as UTF-8 (1), newline paths sent (1).
- **`Git.ignoredPaths(_:repoRoot:)`**: git's verdict for paths created after any cached listing
  (`GitIgnoredSet` in swift-file-tools lists only what existed when it ran), from ONE
  `check-ignore --stdin -z`. check-ignore refuses `GIT_LITERAL_PATHSPECS` ("pathspec magic not
  supported by this command: 'literal'", measured) and its stdin names paths rather than patterns,
  so that one variable is set to 0 for the call. Mutants, each failing
  `testPathsCreatedAfterAnyListingAreJudgedByGitsRules`: the literal variable left on, nothing
  ignored.

## Known non-issues (do not "fix" these again)

- `Git.remoteURL(repoRoot:remote:)` has no caller in Sidewatch — public API, kept.
- Tests take ~150 s (199 real-git tests); that is expected, not a hang.
- `testDiscardUntrackedMovesTheFileToTheTrash` and
  `testDiscardStagedAdditionRemovesFromIndexAndMovesTheFileToTheTrash` really trash a temp file
  and remove it from `~/.Trash` afterwards.
- `add -N` writing the empty blob once per repository is not an object leak: it is one object, ever.
- Under `diff.autoRefreshIndex=false` a raw `diff --name-status`/`--raw` lists a stat-stale file
  as `M`; that is git's format behaviour, and the package's own `--name-status` path refreshes its
  scratch index first.
- Hooks a `commit` runs inherit `GIT_LITERAL_PATHSPECS=1`, `diff.autoRefreshIndex=false` and
  `core.fsmonitor=false`; a hook that globs its own pathspecs would see literal matching. Documented in `Git.run`.
- `git worktree add` and `git clone` would run `post-checkout`; under `core.hooksPath=/dev/null` they do not. Deliberate: only the person's commit runs a checkout's hooks.

## History

- 17 Sep 2026 — full audit (app + all 20 libraries), Claude with David.
- 18 Sep 2026 — line-by-line logic review (see the section above); 125 tests, ~80 s.
- 18 Sep 2026 (later) — CRLF sweep across the family: the diff parsers above, Claude with David.
- 9 Oct 2026 — hostile-environment review (see the section above): pathspecs, index writes,
  inherited environment, lossy decode, timeouts, hostile config, unborn HEAD, deletion key, status
  codes, pseudo-branches, in-progress operations, commit, discard, checkpoints, blob hashes,
  out-of-root reads; 199 tests, ~155 s.
- 9 Oct 2026 — security review: `core.fsmonitor=false` on every call, `core.hooksPath=/dev/null` on every call but `Git.commit` (section above); 202 tests.
- 10 Oct 2026 — `Git.headContents`, `Git.ignoredPaths`, and `runData` over one private `launch` (section above); 210 tests.
- 23 Oct 2026 — `Git.fileVersions` / `blobIDs`: one file at many commits from two cat-file runs; only object ids are asked (a `HEAD` or `--batch` never reaches git); 5 tests, 5 mutants each failing (two only after the tests were tightened: a newline path reading the file named by its first half, and a tree taken as a blob).
- 23 Oct 2026 — `Git.push` / `GitPushError`: to the tracked branch exactly, else published with `-u`; the pre-push hook runs (the second call after `commit` to pass `hooks: true`); `pushTarget` answers from configuration alone (the Changes panel labels its button with it); `pendingPush` is what the button shows (moved here from the app); `BlameInfo.uncommitted`/`isUncommitted` replace the app's three spellings of git's word; 10 tests, 10 mutants each failing.
- 23 Oct 2026 — `HunkRevert` / `HunkRevertEdit` / `HunkRevertOutcome` / `Git.gutterDiff` (shared with `lineDiff`): 11 tests against git's real `-U0` diffs (top and end deletions, CRLF, no final newline either way, context hunks, moved-on text, a seeded fuzz undoing every change in turn back to HEAD); 6 mutants — five fail, the sixth reached a branch git cannot produce, which was removed.
