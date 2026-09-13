# Design

Git Safety Harness is a small reference implementation for checking selected Git operation boundaries before a later action.

```text
Instruction
    ↓
Safety Harness
    ↓
Independent Enforcement where needed
    ↓
Human Approval
    ↓
Actual Effect
```

The Safety Harness is not equal to Independent Enforcement. It reports a fail-closed STOP when a configured condition cannot be verified, but the same execution principal may bypass it by invoking Git directly.

Write Set, Stage Set, and Safety Harness are explanatory project terms, not Git standard terminology.
