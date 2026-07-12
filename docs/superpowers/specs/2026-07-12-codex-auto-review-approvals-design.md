# Codex Full-Access Permissions Design

## Goal

Use the same unrestricted local-command permissions in Codex CLI and the ChatGPT
desktop app. Commands may read or write outside the workspace and access the network,
whether the desktop app runs Codex through PowerShell or WSL.

## Configuration

Apply the following settings to both the tracked default in `codex/config.toml` and
the active machine configuration in `~/.codex/config.toml`:

```toml
sandbox_mode = "danger-full-access"
approval_policy = "on-request"
approvals_reviewer = "auto_review"
```

Do not add `[sandbox_workspace_write]`; its options apply only to `workspace-write`.
Keep `approval_policy` and `approvals_reviewer` because they remain separate controls
for actions that still use approval handling.

The tracked file remains the portable default. The active file must also be updated
because it is a regular machine-local file rather than a link to the tracked file.

`danger-full-access` removes Codex's local sandbox restrictions. It does not bypass
Windows or WSL operating-system permissions.

The desktop composer can send an explicit permission choice when it starts a task.
This session demonstrates that the launch choice can override `config.toml`: the
active file already specifies `danger-full-access`, but the session reports a managed
workspace-only profile. New desktop tasks must therefore start in **Full access**, not
**Ask for approval**. Existing tasks retain the permissions they received at startup.

## Behavior

- Local commands can read and write outside the workspace and access the network.
- PowerShell and WSL use different enforcement implementations, but neither applies a
  Codex sandbox boundary in `danger-full-access` mode.
- MCP, connector, Computer Use, destructive-action, and user-input approvals remain
  subject to their own controls.

## Remaining Human Prompts

This change removes the local command sandbox. It does not promise zero prompts.
Requests that require user input, expose secrets, or use separately controlled tools
can still prompt shishi.

## Verification

1. Parse both TOML files successfully.
2. Confirm both files specify `sandbox_mode = "danger-full-access"` and contain no
   `[sandbox_workspace_write]` table.
3. Start new CLI and desktop tasks. Use `/status` to confirm full access is active.
4. For the desktop task, select **Full access** beneath the composer before starting it.
5. Run harmless commands that read outside the workspace and access the network.

## Rollback

Restore `sandbox_mode = "workspace-write"` and the required
`[sandbox_workspace_write]` options. Start new tasks and confirm the restored effective
settings with `/status`.
