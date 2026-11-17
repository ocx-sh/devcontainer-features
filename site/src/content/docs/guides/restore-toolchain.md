---
title: Restore the project toolchain on create
description: Make a dev container fetch the tools pinned in ocx.toml and ocx.lock, choose which groups to restore, and skip the restore when you want to.
---
<!-- doc_type: how-to -->
<!-- doc_tier: everyday -->

This page shows how to get the tools pinned in your project's `ocx.toml` into a dev container.
Afterwards, `ocx exec -- <tool>` and a bare `<tool>` in a new terminal run the locked version.
The restore needs no option: the default feature entry does it.

## What the restore does {#hook}

After the container is created, the feature runs `ocx pull` as the remote user in the workspace folder.
The command reads `ocx.toml` and `ocx.lock` and fetches the locked tools into the private store `~/.ocx` of that user.
The result depends on which project files exist.

| Project files in or above the workspace | What happens |
|---|---|
| No `ocx.toml` | Nothing. The feature stays silent. |
| `ocx.toml` and `ocx.lock` | The locked tools are fetched. |
| `ocx.toml` without `ocx.lock` | A warning is printed and the container still starts. |

The restore never fails container creation.
A Codespaces prebuild runs the same step, so a prebuild already holds the tools.

## Commit the project files {#project-files}

Commit both `ocx.toml` and `ocx.lock`.
The lock pins each tool to an exact digest, so every container restores the same builds.

<!-- doc: restore-default -->
```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
  }
}
```

With both files in the workspace, run the pinned tool after the container starts.

```console
$ ocx exec -- jq --version
jq-1.8.2
```

A missing lock prints this warning during creation.
Run `ocx lock` in the project, commit `ocx.lock`, and rebuild.

<!-- doc: restore-no-lock -->
```console
ocx-feature: warning: ocx pull failed with exit code 78.
  attempted: /usr/local/bin/ocx pull
  fix: run "ocx lock" in the project and commit ocx.lock
```

## Restore specific groups {#groups}

Tools in `ocx.toml` live in the top-level `[tools]` table, the default group, or in named `[group.<name>.tools]` tables.
The `pullGroups` option takes a comma-separated list and passes it to `ocx pull -g`.
An empty value restores the default group only.

A named list replaces the default, so it restores only the groups it names.
Add `default` to the list to keep the top-level tools.

<!-- doc: restore-groups -->
```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {
      "pullGroups": "default,ci"
    }
  }
}
```

An unknown group name prints a warning with exit code 64 and the hint `probably an unknown group in the pullGroups option`.
The container still starts.

## Skip the restore {#skip}

Set `pull` to `false` to fetch nothing on create.
The feature still installs `ocx`, and you restore by hand with `ocx pull` when you want the tools.

<!-- doc: restore-pull-off -->
```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {
      "pull": false
    }
  }
}
```

## Activate the tools in every terminal {#activate}

The option `shellActivation` is on by default.
A new interactive shell that starts inside the project puts the tools of the default group on its path, composed once when the shell starts.

<!-- doc: restore-activation -->
```bash
bash -ic 'command -v jq'
```

The command prints a path inside `.ocx/toolchain/links/default/jq/content/` of the project.

Three limits apply.

- The path is not refreshed at each prompt. After `ocx add` or `ocx pull`, open a new terminal or run the tool through `ocx exec -- <command>`.
- Non-interactive shells, such as `sh -lc '...'`, do not get the tools on their path.
- Only the default group is on the path. Run tools from other groups with `ocx exec -g <group> -- <command>`.

Projects under `/workspaces/*` activate without a prompt.
The `consentPaths` option changes that list with colon-separated paths, and an empty value makes every project ask first.

## See the tools in VS Code {#vscode}

The feature adds the extension `ocx-sh.ocx` to `customizations.vscode.extensions`.
The extension activates on workspaces that contain an `ocx.toml`, so it does nothing in other projects.
It puts the project tools on the path of the editor's own processes, such as language servers.
To also apply them to integrated terminals, set the VS Code setting `ocx.env.applyToTerminals` to `true`.

## When the restore fails {#failures}

A failed restore prints one warning that names the exit code, the command and a fix.
The container still starts.

| Exit code | Cause | Fix |
|---|---|---|
| 78 | `ocx.lock` is missing | Run `ocx lock` and commit the file. |
| 65 | `ocx.lock` is stale against `ocx.toml` | Run `ocx lock` and commit the file. |
| 75, 69, 79 | A network failure or a package that is not found | Check the network, mirror and proxy settings, then rerun the container command. |
| 74 | A file ownership problem | Check the owner of `ocx.toml`, `ocx.lock` and `.ocx` in the workspace. |
| 64 | An unknown group name | Fix the `pullGroups` option. |

When the container runs the restore as root and the project files belong to another user, the feature skips the pull and warns.
Run `ocx pull` as the project owner instead.

## Next steps {#next-steps}

- [Run ocx as root, a named user or a split user](non-root-and-custom-users.md) explains whose store receives the tools.
- [Pin or upgrade the ocx version](pin-or-upgrade-version.md) controls the ocx version itself.
