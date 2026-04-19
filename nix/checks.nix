# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT OR BSD-3-Clause
#
# `nix flake check` runs treefmt (via the module's own check) plus any
# additional checks defined here. hlint + hpc coverage threshold are added
# once the Haskell source tree has modules to lint / cover.
_: {
  perSystem = _: {
    checks = {
    };
  };
}
