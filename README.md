# Coder + Nix workspace image

Ubuntu 24.04 with a `coder` user (UID/GID 1000), passwordless sudo, single-user
Nix 2.34.1, flakes, dev shells, direnv, tmux, ripgrep (`rg`), and bubblewrap (`bwrap`).
Also includes Git, SSH client, curl, unzip, a compiler toolchain, and the usual
Linux tools used by Coder modules. Published for Linux amd64 and arm64 at:

```text
ghcr.io/cfi2017/coder-nix:latest
```

## Publishing

Push this repository to GitHub on `main`. The Actions workflow tests both
architectures before publishing with the built-in `GITHUB_TOKEN`; no registry
password secret is needed. Pull requests build and test without publishing.
Pushes to main publish `latest`, `main`, and a commit tag; `v1.2.3` tags publish
`1.2.3`, `1.2`, and a commit tag. Weekly and manual runs also rebuild the image.
Image names follow the repository name automatically (including forks).

**After the first successful publish, make the GHCR package public:** open the
package under your GitHub profile/organization → Package settings → Change
visibility → Public. New GHCR packages default to private even for public
repositories; the workflow does not change visibility. Organization policy must
allow public packages. Verify anonymous access with an unauthenticated pull.
The image is not available until the workflow has run.

## Coder template

Import `templates/docker/` as a Coder template, or adapt the
[official Docker template](https://github.com/coder/coder/tree/main/examples/templates/docker)
to use this image. The included example uses the same agent bootstrap and
code-server/JetBrains modules as that template. Set `workspace_image` if using
a fork or a pinned image digest. The provisioner needs access to the Docker
host; the container needs network access to your Coder deployment.

The image runs as `coder` and permits Coder to replace its entrypoint with
`coder_agent.main.init_script`. Nix is available in noninteractive processes,
terminals, and login shells without a startup daemon or sourcing home files.
Ubuntu's glibc and FHS paths support downloaded module binaries. Individual
modules and IDE releases still need to support your chosen architecture;
end-to-end IDE installation requires a running Coder deployment.

The example persists `/home/coder` and the **whole `/nix` directory** in separate,
per-workspace Docker named volumes. Docker seeds new volumes from the image.
Do not share a writable Nix volume among workspace owners. Nix profiles in home
refer to store paths, so home and Nix storage should be backed up together.
Volumes survive stop/start; deleting the workspace deletes its managed volumes.

An existing `/nix` volume hides the new image's store on image upgrades. Pin the
image while using that volume. To upgrade Nix/image versions, back up projects
and configuration, then recreate the workspace with fresh volumes and reinstall
profiles/rebuild flakes. Simply attaching an old store to a new image can hide
the `/opt/nix` target and break Nix. Kubernetes PVCs and bind mounts do not seed
empty directories like Docker named volumes: populate `/nix` from the matching
image and set ownership to 1000:1000 before starting the agent. A home-only mount
works, but Nix outputs are lost on container replacement.

Inside the workspace:

```sh
nix flake init
nix build
nix develop
# Or enter an ad hoc shell:
nix shell nixpkgs#hello
```

## Isolation and bubblewrap

Nix uses a local store owned by `coder`, with flakes enabled and build sandboxing
disabled so ordinary unprivileged workspace containers can build without a
Nix daemon, systemd, or extra capabilities. Use one trusted owner per workspace;
Nix builds here can access that owner's workspace files and network.

Bubblewrap is installed, but running its sandboxes depends on the host allowing
unprivileged user namespaces and on its seccomp/AppArmor policy. Ubuntu hosts
may restrict these. Test your intended use on the deployment host, for example:

```sh
bwrap --ro-bind / / --dev /dev --proc /proc --unshare-pid /bin/true
```

If this fails with a namespace/permission error, an administrator needs to
configure an appropriate host/runtime policy. The template does not enable
privileged mode or disable host security profiles. CI checks the bwrap binary;
it does not assert that every deployment host supports bubblewrap sandboxes.

## Local validation

```sh
docker build -t coder-nix:test .
bash tests/smoke.sh coder-nix:test
```

The smoke test hides the image's home directory, overrides the entrypoint like
Coder, checks tools and login shells, builds a real flake derivation, and runs a
command inside a dev shell. It also checks Bash hooks and direnv approval, then
launches a test process through direnv inside an already-running tmux server. It needs access to GitHub and the Nix binary cache.
The fixture pins nixpkgs to a commit. Base packages receive updates on rebuild;
Nix's architecture-specific tarballs are verified with pinned SHA-256 hashes.
When upgrading Nix, update both its version and those hashes in `Dockerfile`.

## direnv and Home Manager

The image includes direnv and installs its interactive Bash hook in
`/etc/bash.bashrc`, outside the mounted home. It works in both login and
non-login Bash shells; no copying or replacing your dotfiles is required.
`~/.local/bin` is also on PATH for user-installed tools such as Codex and its
code-mode host.

For a flake-backed project, create `.envrc` in the project directory:

```sh
use flake
# For a named devShell instead: use flake .#my-shell
```

Review the file, then run `direnv allow .` once from that directory. Repeat
approval after editing `.envrc`. Ignore `.direnv/` in the project's Git config.
Direnv finds `.envrc` in the current directory or a parent; without one it runs
commands with the ordinary environment. Base direnv supports `use flake`
directly; flakes need a `devShells.<system>.default` (or the selected shell).

For your preferred Home Manager setup, import
[`home-manager/workspace.nix`](home-manager/workspace.nix) into your existing
standalone Home Manager configuration for `coder`. Set that configuration's
`home.username = "coder"`, `home.homeDirectory = "/home/coder"`, and retain its
chosen `home.stateVersion`. The module enables nix-direnv caching, Bash/Zsh
hooks, and a small Zsh setup inspired by
[cfi2017/nixos-config](https://github.com/cfi2017/nixos-config): bira, Git helpers,
autosuggestions, syntax highlighting, and directory shortcuts. Use a Home
Manager release matching your nixpkgs release. Activate with your usual
`home-manager switch --flake ...`; back up conflicting existing dotfiles before
letting Home Manager manage them. Start `zsh` to use that shell. Bash remains
the image's default for Coder startup compatibility.

The optional module is not activated at image build time: it manages the actual
persistent home. Its nix-direnv profile roots and cache require the same `/nix`
persistence as other Nix profiles.

## Launch Codex in the project's direnv environment

Replace the `command` in your existing `coder_app.codex` with:

```hcl
command = <<-EOT
  #!/bin/bash
  set -euo pipefail
  exec tmux new-session -A -s codex -c /home/coder/project \
    "bash -lc 'exec direnv exec /home/coder/project codex --yolo'"
EOT
```

`-c` sets the pane's working directory. The login Bash loads the tool PATH;
**inside that pane**, `direnv exec` evaluates the approved project environment
and then starts Codex with its exported variables and tools. The interactive
prompt hook alone cannot handle this noninteractive launch. Wrapping tmux
itself with direnv would also leave new panes dependent on an existing tmux
server's environment.

In your module's `base_config_toml`, explicitly inherit that environment for
Codex subprocesses. Place this new table after the top-level `model_provider`
and before the existing provider table:

```toml
model_provider = "ai_gateway"

[shell_environment_policy]
inherit = "all"

[model_providers.ai_gateway]
# Keep your existing provider settings here.
```

See the [official Codex configuration reference](https://developers.openai.com/codex/config-reference/)
for `shell_environment_policy.inherit`. Other configured environment filters
can still remove individual variables. Your existing `workdir`, gateway
configuration, and `post_install_script` can remain as supplied. This wrapper
applies to this custom app; other launch paths need their own direnv wrapper.

Before first launch, open a workspace terminal, `cd /home/coder/project`, review
`.envrc`, and run `direnv allow .`. Verify with:

```sh
direnv exec /home/coder/project bash -c 'command -v codex; command -v your-project-tool'
```

Replace `your-project-tool` with a package provided by your dev shell. If an old
`codex` tmux session exists, exit Codex in that session and reopen the app so it
creates a new process. `-A` attaches to an existing process without refreshing
its environment. Similarly, restart after changing the dev shell or `.envrc`.
Use distinct tmux session names for different projects.

Direnv passes exported environment variables, not interactive shell aliases or
functions. This selects the environment at Codex launch; it does not
automatically reevaluate direnv every time Codex changes directories, and a
child login shell can alter inherited PATH. For repositories with nested or
changing environments, add this instruction to the project's `AGENTS.md`:

```text
Run project build, test, and development commands through
`direnv exec /home/coder/project <command> ...` so each command loads the
project's current approved environment. For a subproject with its own .envrc,
use that subproject's directory instead. Do not automatically approve .envrc.
```

For example: `direnv exec /home/coder/project bash -c 'npm test'`. For shell
pipelines, put the entire pipeline inside that `bash -c` command so all parts
use the project environment.
