# copilot-cli nono Pack

`copilot-cli` is a `nono` pack for running [GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli) (`copilot`) inside a nono security sandbox.

It ships a nono profile covering the Copilot CLI config and cache directories, read access to the `gh` CLI config for auth context, and credential injection of the GitHub token from the OS keychain.

## What It Does

**Filesystem isolation**
Copilot CLI is confined to the working directory, its own config (`~/.copilot/`), cache (`~/Library/Caches/copilot/`), and read-only access to the `gh` CLI config (`~/.config/gh/`). All other paths are blocked at the kernel level.

**Credential injection**
The GitHub token (`copilot_github_token`) is read from the OS keychain (macOS Keychain / Linux Secret Service) and injected as an `Authorization: Bearer` header for requests to `https://github.com`. The token is never exposed to the child process directly.

**Network**
Outbound connections are allowed. The GitHub token is injected automatically for requests to `https://github.com` — no other credential configuration is needed.

## Installation

```bash
nono pull always-further/copilot-cli --registry https://packs.nono.sh
```

## Setup

### Step 1 — Create a fine-grained personal access token

1. Go to **GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens**
2. Click **Generate new token** (top right)
3. Fill in the token name, expiration, and resource owner
4. Under **Permissions**, make sure **Copilot Requests** is selected
5. Click **Generate token** and copy the token (`github_pat_...`)

### Step 2 — Add the token to the macOS Keychain

```bash
security add-generic-password -s "nono" -a "copilot_github_token" -w
```

Omitting the value from the command line causes `security` to prompt for it interactively, keeping the token out of shell history and the process list. The token is stored under service `nono`, account `copilot_github_token`. nono reads it from the keychain at session start and injects it as an HTTP header — the token is not passed to the `copilot` process directly.

### Step 3 — Run

```bash
nono run --profile copilot-cli -- copilot
```

## Included Artifacts

| Artifact | Type | Purpose |
|---|---|---|
| `policy.json` | profile | nono sandbox profile for GitHub Copilot CLI |
| `skills/copilot-sandbox/SKILL.md` | instruction | Teaches the agent its sandbox constraints |
| `bin/nono-hook.sh` | script | Injects capability context on permission denial |

## Policy Details

The profile:
- Extends `default` (inherits all standard deny groups)
- Allows `~/.copilot`, `~/Library/Caches/copilot`, `/usr/local/Caskroom/copilot-cli`
- Read-only access to `~/.config/gh`
- Includes `claude_code_macos`, `node_runtime`, `git_config` security groups
- Injects `copilot_github_token` from OS keychain as `Authorization: Bearer` header to `github.com`
- Workdir: read+write
- Denies `~/.nono` to prevent the agent from reading sandbox configuration

## Package Metadata

- Name: `copilot-cli`
- Pack type: `agent`
- Platforms: `macos`
- License: `Apache-2.0`
- Min nono version: `0.29.0`

## Directory Layout

```
copilot-cli/
├── bin/
│   └── nono-hook.sh
├── package.json
├── policy.json
├── README.md
└── skills/
    └── copilot-sandbox/
        └── SKILL.md
```
