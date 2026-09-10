# Login shells reset PATH on Ubuntu; keep Nix available after that reset.
export PATH="$HOME/.nix-profile/bin:$HOME/.local/state/nix/profile/bin:/opt/nix/bin:$PATH"
export NIX_REMOTE=local
export NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
