terraform {
  required_providers {
    coder  = { source = "coder/coder", version = "~> 2.0" }
    docker = { source = "kreuzwerker/docker", version = "~> 3.0" }
  }
}

provider "coder" {}
provider "docker" {}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

variable "workspace_image" {
  type        = string
  default     = "ghcr.io/cfi2017/coder-nix:latest"
  description = "Workspace image; pin a digest for reproducible deployments."
}

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
    set -eu
    if command -v rea-setup-agents >/dev/null 2>&1; then
      rea-setup-agents
    fi
    if [ ! -f "$HOME/.init_done" ]; then
      cp -rn /etc/skel/. "$HOME/"
      touch "$HOME/.init_done"
    fi
  EOT
  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }
}

module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  order    = 1
}

module "jetbrains" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/jetbrains/coder"
  version    = "~> 1.1"
  agent_id   = coder_agent.main.id
  agent_name = "main"
  folder     = "/home/coder"
}

resource "docker_image" "workspace" {
  name         = var.workspace_image
  keep_locally = true
}

resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle { ignore_changes = all }
}

# Docker populates a fresh named volume from the image, retaining ownership.
# Persist the entire store AND database; never mount only /nix/store.
resource "docker_volume" "nix" {
  name = "coder-${data.coder_workspace.me.id}-nix"
  lifecycle { ignore_changes = all }
}

resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.workspace.image_id
  name     = "coder-${data.coder_workspace.me.id}"
  hostname = data.coder_workspace.me.name
  user     = "1000:1000"
  entrypoint = [
    "sh", "-c",
    replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")
  ]
  env = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home.name
  }
  volumes {
    container_path = "/nix"
    volume_name    = docker_volume.nix.name
  }
}
