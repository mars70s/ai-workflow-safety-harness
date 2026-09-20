# Git Safety Harness Validation Record

[English](validation.md) | [日本語](validation.ja.md)

## Validation target

Git Safety Harness v0.1 pre-publication candidate.

Reviewed implementation commit: `15fc65a7975cdf76cac313e312c2b122af421c0f`

Later documentation-only publication commits may differ from that reviewed commit. The source and test hashes below remain the validation identity for the implementation and test candidates.

## Source and test identity

| File | SHA256 |
| --- | --- |
| `harnesses/git/src/git-safety-harness.ps1` | `D9B48AA478387AE50049D98CC777FE7745B7A59F12E574DEE74518F5C687719A` |
| `harnesses/git/tests/verify-fail-closed.ps1` | `68CA5A2D2CF3895B2C11F45A8FAC0B0873E152B5433D79988AD7EC7F332C4CD4` |
| `harnesses/git/tests/verify-success-path.ps1` | `56998713AAF2BCE2C2CEDE541BFA74F4772043D11FBC3A6CFB69C509C2554784` |

## Validation environment

- Git 2.54.0.windows.1
- PowerShell 7.6.5
- Windows PowerShell 5.1.26100.9444
- Gitleaks 8.30.1

These are validated reference environments, not universal compatibility guarantees.

## Fail-closed results

- PowerShell 7: **14/14 PASS**
- Windows PowerShell 5.1: **14/14 PASS**
- Total: **28/28 PASS**

The cases cover the following current test-script conditions:

1. Case 1 — out-of-scope untracked file in the Write Set.
2. Case 2 — rename exposure in the staged no-renames listing.
3. Case 3 — Gitleaks unavailable through Application discovery.
4. Case 4 — expected repository root cannot be resolved.
5. Case 5 — discovered Gitleaks cannot be executed.
6. Case 6 — detached HEAD and unresolved symbolic branch.
7. Case 7 — multiple configured push URLs.
8. Case 8 — execution outside a repository and root confirmation failure.
9. Case 9 — two staged paths differing only by case.
10. Case 10 — a different valid repository supplied as the expected root.
11. Case 11 — a valid symbolic branch that does not match the expected branch.
12. Case 12 — an actual real-Gitleaks finding using a synthetic fixture rule.
13. Case 13 — an independently reachable Stage Set-specific STOP.
14. Case 14 — exactly one push URL that does not match the expected URL.

The test also validates wrapper fail-closed behavior under both shells: a valid Harness STOP returns exit 1; a missing Harness path, parameter-binding failure, and stale prior `$LASTEXITCODE` all return exit 1 with the wrapper invocation boundary exercised.

## Success results

- PowerShell 7: **3/3 PASS**
- Windows PowerShell 5.1: **3/3 PASS**
- Total: **6/6 PASS**

The positive cases are:

1. Success Case 1 — valid clean workflow.
2. Success Case 2 — LF/CRLF stderr-isolation regression with an initially unstaged allowed change. The relevant warning is reproduced on the Harness Git path; the current Harness does not interpret it as policy data. The staged scan may therefore be empty after that path.
3. Success Case 3 — non-empty allowed staged diff with a successful real-Gitleaks scan.

## Preserved revalidation evidence

A later evidence capture re-ran the unchanged source and test identities recorded above. It preserves the original validation environment, including PowerShell 7.6.5; it does not replace or rewrite that historical record.

The later evidence environment was:

- Git 2.54.0.windows.1
- PowerShell 7.6.6
- Windows PowerShell 5.1.26100.9444
- Gitleaks 8.30.1

The preserved revalidation results were:

- PowerShell 7 fail-closed: **14/14 PASS**
- Windows PowerShell 5.1 fail-closed: **14/14 PASS**
- PowerShell 7 success path: **3/3 PASS**
- Windows PowerShell 5.1 success path: **3/3 PASS**

The PowerShell 7 micro-version differs from the original validation environment (`7.6.5` versus `7.6.6`). The preserved execution logs, case-level STOP output, exit codes, and SHA256 manifest are available under [the revalidation evidence directory](evidence/validation-20260919/).

This later capture is bounded revalidation evidence for the identified source and test identities. It is not proof of universal compatibility, a security guarantee, production enforcement, or unbypassability.

## Additional validation

- M2 differential regression: the historical pre-fix Harness stopped because Git stderr contaminated policy data; the current Harness passed the same relevant fixture under both PowerShell 7 and Windows PowerShell 5.1.
- Case-sensitive path collision: PASS under both shells.
- Real Gitleaks actual finding: PASS under both shells.
- Wrapper contract under both shells: valid success => 0; Harness STOP => 1; missing Harness path => 1; parameter-binding failure => 1; stale prior `$LASTEXITCODE` => 1.
- No-global-config handling: PASS under both shells.
- GUID-based fixture-root collision resistance: PASS.

Measured or observed evidence includes unchanged synthetic remote refs, process-local PATH restoration, unchanged Git configuration in the global scope during the relevant validation, explicit case results and exit codes, source/test hashes, and real Gitleaks execution/finding where tested.

## Evidence boundaries

### Measured / observed

- The listed test results, exit codes, and source/test hashes.
- Synthetic remote refs remained unchanged.
- The process-local PATH was restored.
- Global-scope Git configuration comparison remained unchanged.
- Real Gitleaks execution and the actual finding path where tested.

### Design-bound

- The Harness itself does not execute a later push or deployment.
- The tests use synthetic local remotes.
- Later operational behavior remains outside the Harness boundary.

### Not proven / out of scope

- Universal Git, PowerShell, or Gitleaks compatibility.
- Complete secret detection.
- Semantic correctness of allowed changes.
- Inability to bypass the Harness when raw Git or shell access remains available.
- Broad network inactivity.
- Correctness of arbitrary external enforcement.
- Security of later deploy or API operations.

See [limitations.md](limitations.md) for the bounded limitation set. This is a reference Harness, not an independent security boundary.
