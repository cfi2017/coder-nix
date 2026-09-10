# Coder + Nix workspace image

Ubuntu 24.04 with a `coder` user (UID/GID 1000), passwordless sudo, single-user
Nix 2.34.1, flakes, dev shells, tmux, ripgrep (`rg`), and bubblewrap (`bwrap`).
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
command inside a dev shell. It needs access to GitHub and the Nix binary cache.
The fixture pins nixpkgs to a commit. Base packages receive updates on rebuild;
Nix's architecture-specific tarballs are verified with pinned SHA-256 hashes.
When upgrading Nix, update both its version and those hashes in `Dockerfile`.
