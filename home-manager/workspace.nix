# Optional import in a standalone Home Manager configuration for user "coder".
# Inspired by cfi2017/nixos-config/modules/shared/utils/{direnv,zsh}.nix.
{ ... }:
{
  home.sessionPath = [ "$HOME/.local/bin" ];

  programs.bash.enable = true;
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    autocd = true;
    oh-my-zsh = {
      enable = true;
      theme = "bira";
      plugins = [ "git" ];
    };
    shellAliases = {
      ".." = "cd ..";
      "..." = "cd ../..";
      cls = "clear";
    };
  };
}
