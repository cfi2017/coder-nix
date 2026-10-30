# Separate pin: REA 6.8 requires Node >=22.23.4 and Ghidra >=12.1.
let
  pkgs = import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/e62746b0b472753ef019baceab6f1e2e52014980.tar.gz";
    sha256 = "010xm16sbwwh5jlhj3p79avsiy8qx85bk2kjyg4kgb46spvmy7dk";
  }) {};
in pkgs.buildEnv {
  name = "rea-tools";
  paths = with pkgs; [
    nodejs_22 ghidra jdk21 jadx apktool binwalk wireshark-cli mitmproxy
    frida-tools radare2 gdb strace ltrace patchelf file binutils p7zip
    wabt android-tools
    (python3.withPackages (p: [ p.pwntools p.pefile p.capstone p.pyelftools ]))
  ];
}
