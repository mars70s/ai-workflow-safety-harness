# Git Safety Harness

A reference implementation of a soft, fail-closed Safety Harness for selected Git workflow boundaries.

## Validated gates

1. Repository Root
2. Write Set
3. Stage Set
4. Branch
5. Push URL
6. Secret Scan
7. fail-closed STOP behavior

The Harness does not perform `git push`. It validates the configured state before a later action.

## Validation reference environments

- Git 2.54.0.windows.1
- PowerShell 7.6.5
- Windows PowerShell 5.1.26100.9444
- Gitleaks 8.30.1

The fail-closed suite passed 16/16 across PowerShell 7 and Windows PowerShell 5.1. The success-path suite passed 4/4 across both shells using real Gitleaks 8.30.1. These are reference and test environments, not universal compatibility guarantees.

## Provenance

Current locally recovered and validated working source was adopted as the v0.1 baseline. Earlier exact file lineage is not asserted.

## Limitations

The Harness does not guarantee safety, act as a sandbox, or provide an independent security boundary. Known limitations include:

- semantic mistakes inside allowed files;
- a correct remote paired with wrong content;
- raw Git or shell bypass;
- incomplete secret detection;
- filesystem changes invisible to selected Git checks;
- `assume-unchanged` and `skip-worktree` behavior;
- human approval of wrong state;
- deploy, API, and other external actions outside Git;
- time-of-check/time-of-use changes;
- path edge cases;
- submodules, symlinks, and junctions; and
- tool and version differences.

See [design.md](docs/design.md) and [limitations.md](docs/limitations.md).
