# Safety Harness Principles

The common workflow model is:

1. Instruction
2. Safety Harness
3. External Independent Enforcement

A Harness is an executable workflow control between an instruction and an effect. It should:

- fail closed when required state cannot be verified;
- enforce exact scope and explicit authorization;
- validate explicit repository or workflow state;
- avoid silent repair and preserve unexpected state;
- distinguish Harness checks from independent security isolation;
- make direct or raw access bypasses explicit;
- verify success rather than infer it; and
- stop on unexpected state instead of autonomously repairing it.

Independent controls remain necessary when the workflow must resist bypass by the same execution principal.
