# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT OR BSD-3-Clause
_: {
  perSystem = {pkgs, ...}: {
    # Packages are added here as the Haskell library and shim-gen CLI come
    # online. Wired via haskellPackages.callCabal2nix once the .cabal file
    # exists.
    packages = {
      default = pkgs.hello;
    };
  };
}
