---
description: "Show how to switch Codex between safe and unrestricted auto profiles"
argument-hint: "[on|off|status]"
---

# Auto mode

Interpret the argument as `on`, `off`, or `status`.

- For `on`, explain that permission policy is fixed when Codex starts and print:
  `codex --profile auto`
- For `off`, print:
  `codex --profile safe`
- For `status`, inspect the active session configuration and report its approval policy and sandbox.
- Never edit the stow-managed base `~/.codex/config.toml`.
- Warn that the auto profile uses `approval_policy = "never"` and
  `sandbox_mode = "danger-full-access"`.
