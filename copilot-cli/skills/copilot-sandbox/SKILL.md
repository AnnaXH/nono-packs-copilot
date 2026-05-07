---
name: copilot-sandbox
description: Understands nono security sandbox constraints for GitHub Copilot CLI. Use when running inside a nono sandbox, when operations fail with permission errors, or when a tool use is denied.
---

# Working inside a nono sandbox

The user has launched you with `nono run --profile copilot-cli -- copilot`. nono enforces filesystem and network limits at the OS level (Landlock on Linux, Seatbelt on macOS). Approval flows inside Copilot cannot grant access that nono hasn't already permitted.

## Identifying a sandbox denial

The denial signature is in the failed tool's output:

- "Operation not permitted"
- "Permission denied"
- "EACCES" / "EPERM"
- "landlock"
- "sandbox: deny"

When you see any of these on a `bash`, `view`, `edit`, or `create` tool failure, it is a nono boundary — not macOS TCC, not Full Disk Access, not Unix file permissions, not a Copilot approval. Do NOT suggest:

- System Settings / Privacy & Security
- `chmod`, `chown`, `sudo`
- "grant Full Disk Access to your terminal"

## What the sandbox allows

Your active profile (`copilot-cli`) grants access to:

- **Working directory**: full read+write access to the directory from which `copilot` was launched
- **Copilot config**: `~/.copilot/` — readwrite
- **Copilot cache**: `~/Library/Caches/copilot/` — readwrite (macOS)
- **gh CLI config**: `~/.config/gh/` — read-only (for GitHub auth context)
- **Network**: allowed — unrestricted outbound
- **GitHub token**: injected automatically from the OS keychain under credential key `copilot_github_token`

Everything else is blocked at the kernel level. There is no escalation path from inside the sandbox.

## Diagnosing

Run `nono why` to see exactly why access was denied:

```bash
nono why --path /the/blocked/path --op read
```

The output names the rule that blocked the path and suggests the minimum grant to allow it.

Always run `nono why` before telling the user what to do.

## Two options to present to the user

### Option A — quick fix (one-off)

Exit Copilot and restart with the path explicitly allowed:

```
nono run --allow /path/to/needed -- copilot
```

### Option B — persistent fix (write a profile)

Save a JSON file at `~/.config/nono/profiles/<chosen-name>.json` extending the active profile and adding the path. Minimal example for read-only access:

```json
{
  "extends": "copilot-cli",
  "meta": { "name": "<chosen-name>", "version": "1.0.0" },
  "filesystem": { "read": ["/path/to/needed"] }
}
```

Filesystem field choices:
- `"read"` — read-only directory or file access
- `"write"` — write-only access (rare)
- `"allow"` — read+write directory access

For a single file, use `"allow_file"` / `"read_file"` / `"write_file"` instead.

After saving, the user starts sessions with:

```
nono run --profile <chosen-name> -- copilot
```

## Checking current capabilities

If `NONO_CAP_FILE` is set, it points to a JSON file listing exactly what this sandbox can access:

```bash
cat "$NONO_CAP_FILE" | jq .
```

Fields:
- `fs`: array of filesystem capabilities (`path`, `resolved`, `access`)
- `net_blocked`: `true` if network is blocked

## Working directory redirects

If a tool fails because a process tried to write outside the working directory for a **non-critical, recoverable reason** (caching, temp files), and the tool supports redirecting that path via a flag or environment variable, retry with the output redirected into the working directory. Inform the user and suggest adding the folder to `.gitignore` if it would otherwise be committed.

For load-bearing writes (config that must live at a specific path, credentials, lock files), follow the denial handling flow above instead.

## What you should NOT do

- Do not retry the failing operation in a different way. The sandbox is OS-enforced; alternative paths hit the same boundary.
- Do not edit the pack-installed profile at `~/.config/nono/packages/always-further/copilot-cli/policy.json` — it is overwritten on every `nono pull`.
