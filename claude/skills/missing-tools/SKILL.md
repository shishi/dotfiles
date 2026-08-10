---
name: missing-tools
description: Resolves missing CLI tools. Use when a command is unavailable, a shell reports command not found, or a tool must be run without installing it globally.
---

# Missing Tools

Use this workflow when a command is unavailable in the current shell.

## Priority Order

On Windows, if `command -v nix` finds nothing, steps 2–4 cannot succeed. Try step 1
only if `direnv` exists; go to "Windows without nix" below only when direnv is absent
or step 1 cannot resolve the command (`direnv exec . sh -c 'command -v <command>'`
finds nothing). A non-zero exit from the tool itself means the tool ran — that is not
a missing tool.

1. Try the current project's direnv environment:

   ```sh
   direnv exec . <command>
   ```

2. Use [comma](https://github.com/nix-community/comma) for tools from nixpkgs:

   ```sh
   , <command>
   ```

3. Use `nix run` when a specific nixpkgs package is needed:

   ```sh
   nix run nixpkgs#<package> -- <args>
   ```

4. Use `nix shell` as the last resort:

   ```sh
   nix shell nixpkgs#<package> --command <command>
   ```

## Windows without nix

A Windows machine where neither nix nor direnv provides the tool has no general
run-without-install mechanism. If the tool ships via npm or PyPI and `npx` / `uvx`
is available, prefer an ephemeral run (`npx <package>`, `uvx <package>`) — those are
runners, not global installers. Otherwise install with an OS package manager:

1. Prefer scoop (per-user, no elevation; shims land in `~/scoop/shims`, which is
   already on PATH, so the tool resolves in the current shell; already-installed
   returns exit 0, unlike winget):

   ```sh
   scoop install <package>
   ```

2. If scoop is unavailable, use winget:

   ```sh
   winget install --id <PackageId> -e --accept-package-agreements --accept-source-agreements
   ```

This is a persistent install, and a deliberate exception to the no-global-install rule
below: that rule exists to keep tool provisioning inside the reproducible project
environment (nix/direnv), and on a Windows machine without nix that layer does not
exist — neither scoop nor winget offers ephemeral execution. scoop comes first because
its per-user install keeps the footprint smallest. Language-specific global installers
(`npm i -g` etc.) remain forbidden on Windows too.

winget caveats (measured on Windows 11):

- A non-zero exit code is not evidence of failure: "already installed" returns
  non-zero, and some non-zero exits still installed successfully. Verify by resolving
  the command (`command -v <tool>`). If it does not resolve, that is still not proof
  of failure — PATH edits are not visible to the current session — so check the
  Uninstall registry (`...\CurrentVersion\Uninstall\*` under HKLM, HKLM\WOW6432Node,
  HKCU) and `Get-AppxPackage` (MSIX/msstore packages show up there rather than in
  that registry) before concluding the install failed, and tell the user the tool may
  only resolve after a new session.
- `-e` (exact match) is case-sensitive in the `--id`; a one-letter mismatch fails with
  no distinct error. "No package found" can mean a wrong ID or a `--scope` mismatch —
  confirm the ID with `winget search <name> --accept-source-agreements` first.
- Machine-scope packages raise a UAC prompt — tell the user before running.
- Run winget only from an interactive desktop session — launched from a service or
  task-scheduler context it hangs ("Timeout creating winget window").

## Notes

- Never resolve a missing command with a language-specific global installer, on any
  platform: `npm install -g`, `npm i -g`, `pnpm add -g`, `yarn global add`, `bun add -g`,
  `uv tool install`, and the like.
- The only sanctioned persistent-install path is "Windows without nix" above. Everywhere
  else, never install missing tools persistently (`brew install` included) — run them
  ephemerally via steps 1–4. A non-Windows machine without nix is a provisioning gap to
  raise with the user, not a license to install.
- Prefer `direnv exec .` first because project-local dev shells often already provide the right tool version and environment variables.
- Comma automatically finds and runs the nixpkgs package containing the requested command.
- Use fish for shell wrapping in this dotfiles environment:

  ```sh
  fish -c '<command>'
  ```
