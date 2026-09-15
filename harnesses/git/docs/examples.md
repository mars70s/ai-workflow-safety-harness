# Git Safety Harness — Examples

[English](examples.md) | [日本語](examples.ja.md)

These examples apply the six settings from [Getting Started](getting-started.md) to common workflow patterns. All values are synthetic examples and must be replaced with values for the real repository.

## Example 1 — Change one file

### Purpose

Allow only `README.md` to contain a change and to be staged as a commit candidate.

### Settings

| Setting | Value |
| --- | --- |
| `ExpectedRootPath` | `C:\work\example-project` |
| `AllowedFiles` | `README.md` |
| `AllowedStagedFiles` | `README.md` |
| `ExpectedBranch` | `main` |
| `Remote` | `origin` |
| `ExpectedPushUrl` | `git@github.com:example/example-project.git` |

### Current state

Only `README.md` changed, and only `README.md` is staged.

### Harness result

PASS, provided Repository Root, Write Set, Stage Set, Branch, Push URL, and Secret Scan are accepted.

### Why

The observed path is present in both relevant allow-sets. Any other changed or staged path causes STOP.

## Example 2 — Update two documentation files

### Purpose

Update the source document and its public HTML representation together.

### Settings

| Setting | Value |
| --- | --- |
| `ExpectedRootPath` | `C:\work\example-project` |
| `AllowedFiles` | `docs/article.md`, `public/article.html` |
| `AllowedStagedFiles` | `docs/article.md`, `public/article.html` |
| `ExpectedBranch` | `main` |
| `Remote` | `origin` |
| `ExpectedPushUrl` | `git@github.com:example/example-project.git` |

### Current state

Only the two listed files changed, and both are staged.

### Harness result

PASS, because the two changed paths and the two staged paths match their respective allow-sets.

### Why

The Write Set and Stage Set both contain only the two planned files.

## Example 3 — Change two files, stage one file

### Purpose

Allow two files to change while allowing only one of them to become a commit candidate.

### Settings

| Setting | Value |
| --- | --- |
| `AllowedFiles` | `docs/article.md`, `public/article.html` |
| `AllowedStagedFiles` | `docs/article.md` |
| `ExpectedBranch` | `main` |

Set `ExpectedRootPath`, `Remote`, and `ExpectedPushUrl` for the target repository as well.

### Current state

Both files changed, but only `docs/article.md` is staged.

### Harness result

PASS. `public/article.html` is allowed to change but is not in the Stage Set.

### Why

`AllowedFiles` controls the permitted change scope, while `AllowedStagedFiles` controls the permitted staged scope.

## Example 4 — Change code and tests together

### Purpose

Allow an implementation file and its test file in the same commit candidate.

### Settings

| Setting | Value |
| --- | --- |
| `AllowedFiles` | `src/example.ps1`, `tests/example.Tests.ps1` |
| `AllowedStagedFiles` | `src/example.ps1`, `tests/example.Tests.ps1` |
| `ExpectedBranch` | `main` |

Set `ExpectedRootPath`, `Remote`, and `ExpectedPushUrl` for the target repository as well.

### Current state

Both files changed and both are staged.

### Harness result

PASS, provided only the allowed code and test paths appear in the Write Set and Stage Set.

### Why

The Harness checks the path policy and Git state. It does not decide whether the code and tests are semantically correct.

## Example 5 — STOP for the wrong branch

### Purpose

The repository is correct, but the work is on the wrong branch.

### Settings

| Item | Value |
| --- | --- |
| `ExpectedBranch` | `main` |
| Current branch | `feature/test` |

### Harness result

STOP. The symbolic branch resolves successfully but does not match `ExpectedBranch`.

### Why

The workflow must not continue as though work on another branch were work intended for `main`. Detached HEAD also stops because the expected symbolic branch cannot be confirmed.

## Example 6 — STOP for a push-URL mismatch

### Purpose

The remote name is correct, but its configured push URL points to another repository.

### Settings

| Item | Value |
| --- | --- |
| `Remote` | `origin` |
| `ExpectedPushUrl` | `git@github.com:example/example-project.git` |
| Actual push URL | `git@github.com:example/other-project.git` |

### Harness result

STOP. The configured push URL does not exactly match the expected value.

### Why

The Harness checks the push destination before later operations but does not perform a push. Multiple push URLs also cause STOP because exactly one is required.

## Example 7 — STOP for an unexpected file

### Purpose

An AI-assisted task changed a file outside the allowed scope.

### Settings

| Item | Value |
| --- | --- |
| `AllowedFiles` | `docs/article.md`, `public/article.html` |
| Additional observed change | `README.md` |

### Harness result

STOP. `README.md` is not in `AllowedFiles`.

### Why

The Write Set includes tracked unstaged changes, staged changes, and non-ignored untracked paths. An unexpected file is detected even when it is not staged.

## Example 8 — Review before staging

### Purpose

Review the changes before staging any of them.

### Settings

| Item | Value |
| --- | --- |
| `AllowedFiles` | `docs/article.md`, `public/article.html` |
| `AllowedStagedFiles` | `docs/article.md` |

### Current state

Both files changed, but neither file is staged yet.

### Harness result

PASS. An empty current Stage Set contains no path outside the allowed staged set. If a file is staged later, only `docs/article.md` is allowed as a commit candidate under this policy.

### Why

`AllowedStagedFiles` does not require at least one file to be staged. It defines which currently staged paths are acceptable. If an empty Stage Set is represented in another form, verify that form with the PowerShell caller's parameter binding before relying on it.
