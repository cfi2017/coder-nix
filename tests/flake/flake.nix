{
  description = "Workspace image integration smoke test";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/1d060086d60cb76a40cf37109f979d88a5bd6396";
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
