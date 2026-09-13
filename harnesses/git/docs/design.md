# Design

Git Safety Harness is a small Layer-2 reference implementation for checking selected Git operation boundaries before a later action.

```text
Instruction
    ↓
Safety Harness (Layer 2)
    ↓
Proposed workflow effect
    ├─ Human authorization/review (workflow decision gate)
    └─ External Independent Enforcement (Layer 3, separate control)
            ↓
       Actual effect, where permitted
```

Instruction, the Safety Harness, and External Independent Enforcement are distinct parts of the model. Human review or authorization is a workflow decision gate; it is not Layer 3 enforcement. The Safety Harness is not an independent security boundary. It reports a fail-closed STOP when a configured condition cannot be verified, but the same execution principal may bypass it by invoking Git directly.

Write Set, Stage Set, and Safety Harness are explanatory project terms, not Git standard terminology. The implementation is intended to validate explicit state before a later action, not to provide exhaustive Git or filesystem monitoring.
