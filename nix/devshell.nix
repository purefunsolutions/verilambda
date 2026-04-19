# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT OR BSD-3-Clause
_: {
  perSystem = {pkgs, ...}: let
    # GHC 9.10.3 matches nixpkgs 25.11's default haskellPackages and the GHC
    # alterade2-flake's Clash 1.8.4 builds against. Explicitly pinned so dev
    # shell doesn't drift if users bump nixpkgs later.
    ghc = pkgs.haskell.compiler.ghc9103;
    hsPkgs = pkgs.haskell.packages.ghc9103;
  in {
    devShells.default = pkgs.mkShell {
      name = "verilambda-dev";
      packages = [
        # Haskell toolchain
        ghc
        hsPkgs.cabal-install
        hsPkgs.haskell-language-server

        # Haskell formatters & linters
        hsPkgs.fourmolu
        hsPkgs.hlint
        hsPkgs.cabal-fmt

        # Native toolchain for C++ shim + Verilator
        pkgs.verilator
        pkgs.clang-tools # clang-format
        pkgs.gcc
        pkgs.gnumake
        pkgs.pkg-config

        # Shell linting (for treefmt + any helper scripts)
        pkgs.shellcheck
        pkgs.shfmt

        # Markdown formatter
        pkgs.mdformat
      ];
      shellHook = ''
        echo "verilambda dev shell — GHC ${ghc.version}, Verilator $(verilator --version | cut -d' ' -f2)"
        echo "  cabal build        — build the library"
        echo "  cabal test         — run tasty test-suite"
        echo "  nix fmt            — run all formatters"
        echo "  nix flake check    — treefmt + hlint + coverage + tests"
      '';
    };
  };
}
