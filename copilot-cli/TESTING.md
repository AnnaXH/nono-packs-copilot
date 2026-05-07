# Local Testing Guide

The CI publish pipeline requires GitHub's Sigstore OIDC token service and cannot be fully simulated locally. Use the steps below to validate everything before pushing a tag.

## Automated tests (steps 1–4)

Run from the repo root:

```bash
bash copilot-cli/test.sh
```

Or from the pack directory:

```bash
bash test.sh
```

`test.sh` covers: package.json validation, artifact path checks, hook script unit tests (all positive and negative cases), and nono profile smoke tests. All tests print `PASS` / `FAIL` with a summary at the end. Exit code is non-zero if any test fails.

---

## Manual steps

### 5. Plugin wiring

Create the symlink that the nono wiring directive would normally create on install:

```bash
mkdir -p "$HOME/.copilot/installed-plugins/always-further"
ln -sfn "$(pwd)/copilot-cli" "$HOME/.copilot/installed-plugins/always-further/nono"
```

Verify Copilot CLI can see the plugin:

```bash
copilot extensions list
```

Remove when done:

```bash
rm "$HOME/.copilot/installed-plugins/always-further/nono"
```

### 6. End-to-end plugin test inside Copilot CLI

> **Note:** This is the only step that verifies the hooks actually fire inside Copilot CLI. It also validates the unconfirmed assumptions documented in NOTES.md (Gap 3: symlink is sufficient for hook loading; Gap 2: hook output format is accepted).

**Prerequisites:** symlink from step 5 must be in place and `nono` must be installed.

Start a Copilot CLI session inside the nono sandbox:

```bash
nono run --profile ./copilot-cli/policy.json -- copilot
```

Then inside the session, ask Copilot to run a bash command that will be blocked by the sandbox. For example:

> "Run `cat /etc/sudoers`"

**Expected behaviour:**
- The bash tool call fails with `Operation not permitted` or `EACCES`
- The `PostToolUseFailure` or `PostToolUse` hook fires
- Copilot's response includes the sandbox diagnostic: allowed paths and the two options (re-run with `nono run --allow`, or use the `copilot-cli` profile)

**If the diagnostic does not appear**, the hooks are not loading. Check:
1. The symlink points to the correct directory: `ls -la ~/.copilot/installed-plugins/always-further/nono`
2. Copilot CLI recognises the plugin: `copilot extensions list`
3. Whether Copilot CLI requires explicit plugin registration beyond the symlink (see NOTES.md Gap 3)

**SessionStart** — verify the boundary message fires at session start. It should appear immediately when the session opens, before any tool use.

### 7. Dry-run the CI workflow (optional)

[`act`](https://github.com/nektos/act) can parse and trace the workflow steps without executing them:

```bash
brew install act
act workflow_dispatch -W .github/workflows/publish-copilot-cli.yml --dry-run
```

This shows the job graph and step order but will not run any steps. The actual publish step (`agent-sign`) requires GitHub's OIDC token service and cannot run locally regardless of `act` configuration.

### 8. Push to CI

Once all local checks pass, push a tag to trigger the publish workflow:

```bash
git tag copilot-cli-v1.0.0
git push origin copilot-cli-v1.0.0
```

To re-run without a new tag, use the **Actions** tab in GitHub and trigger `publish-copilot-cli` via `workflow_dispatch`.
