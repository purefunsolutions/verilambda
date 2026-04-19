# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT OR BSD-3-Clause
#
# One formatter runner for everything. `nix fmt` applies all formatters,
# `nix flake check` verifies the tree is clean.
{inputs, ...}: {
  imports = with inputs; [
    flake-root.flakeModule
    treefmt-nix.flakeModule
  ];
  perSystem = {
    config,
    pkgs,
    ...
  }: {
    treefmt.config = {
      package = pkgs.treefmt;
      inherit (config.flake-root) projectRootFile;

      programs = {
        # Nix
        alejandra.enable = true;
        deadnix.enable = true;
        statix.enable = true;

        # Haskell
        fourmolu.enable = true;
        cabal-fmt.enable = true;

        # C / C++
        clang-format.enable = true;

        # Shell
        shellcheck.enable = true;
        shfmt.enable = true;

        # Markdown
        mdformat.enable = true;
      };
    };

    formatter = config.treefmt.build.wrapper;
  };
}
