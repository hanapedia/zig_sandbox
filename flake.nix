{
  description = "Zig dev shell with tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          zig
          zls        # Zig language server
          llvm
          lldb
          clang      # useful for C interop
        ];

        shellHook = ''
          echo "🦎 Zig dev shell"
          zig version
        '';
      };
    };
}
