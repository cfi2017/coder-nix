{
  description = "Workspace image integration smoke test";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/0bb8272318b4ca41bf0edc6224df3e3e3046b70d";
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      eachSystem = nixpkgs.lib.genAttrs systems;
    in {
      packages = eachSystem (system:
        let pkgs = import nixpkgs { inherit system; }; in {
          default = pkgs.runCommand "workspace-smoke" {} ''
            echo flakes-work > "$out"
          '';
        });
      devShells = eachSystem (system:
        let pkgs = import nixpkgs { inherit system; }; in {
          default = pkgs.mkShell {
            packages = [ pkgs.hello ];
            shellHook = ''export WORKSPACE_DEV_SHELL=ready'';
          };
        });
    };
}
