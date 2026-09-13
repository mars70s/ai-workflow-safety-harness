# Limitations

The Git Safety Harness is a bounded Layer-2 workflow control. It does not guarantee safety, provide sandbox isolation, or replace OS permissions, credential separation, repository-side protection, secret-management controls, Layer-3 enforcement, or human review.

## State and scope

- An allowed file may still contain a semantic mistake or wrong content.
- A correct remote may still be paired with wrong content.
- The selected Git checks are not full filesystem monitoring; some filesystem changes may be invisible to them.
- `assume-unchanged` and `skip-worktree` have caveats.
- Verification is point-in-time; file or index changes after verification require re-checking.
- Unusual, non-ASCII, or other path edge cases may require stronger parsing.
- Submodules, symlinks, and junctions are not comprehensively covered.
- Repository-root comparison behavior is designed and validated in the Windows reference environment and is not claimed to cover case-sensitive filesystem or root semantics beyond that environment.

## Secret Scan

- Secret Scan examines the staged Git diff passed to Gitleaks; it does not imply that every repository file, allowed unstaged file, allowed untracked file, or committed-but-not-staged content was scanned.
- A scanner cannot detect every secret.
- Gitleaks configuration and ignore mechanisms, including applicable repository-local configuration, can influence results. The Harness does not independently validate their correctness.
- A zero Gitleaks exit is accepted as success. Non-zero, null, or execution failure stops the Harness, but the numeric exit code alone is not claimed to distinguish a finding from a scanner or runtime error.

## Bypass and external influence

- Direct Git or shell invocation may bypass the Harness. API, deploy, and other external actions outside Git are out of scope.
- Git behavior may be influenced by environment or configuration outside the Harness, including `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, Git global or system configuration, hooks configuration, and line-ending configuration. This list is not exhaustive.
- Tool and version differences, as well as configuration-dependent behavior, may change results.
- Human approval can approve an incorrect state; human review is not independent enforcement.
- Time-of-check/time-of-use changes can invalidate a previously verified state.

The validated test suites provide bounded reference evidence, not exhaustive compatibility or security coverage.
