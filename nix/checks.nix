# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT OR BSD-3-Clause
#
# `nix flake check` runs treefmt (via the module's own check) plus any
# additional checks defined here. hlint + hpc coverage threshold are added
# once the Haskell source tree has modules to lint / cover.
_: {
  perSystem = {pkgs, ...}: {
    checks = {
      # REUSE Specification 3.3 compliance — every source file either
      # carries inline SPDX tags or is covered by REUSE.toml, and every
      # license mentioned has its full text in LICENSES/. Run on every
      # `nix flake check` so the repo never drifts out of compliance.
      reuse-lint =
        pkgs.runCommand "reuse-lint" {
          nativeBuildInputs = [pkgs.reuse];
        } ''
          cp -r ${../.}/. ./work
          chmod -R +w ./work
          cd work
          reuse lint
          touch $out
        '';
    };
  };
}
