# Shell environment for create-cluster.py
# Provides azure-cli with the aks-preview extension (19.0.0b5+) baked in.
# nixpkgs only ships aks-preview 18.x which lacks --enable-gateway-api;
# this overrides it with the 19.0.0b5 wheel from the Azure CDN.
let
  pkgs = import <nixpkgs> {};

  aks-preview = pkgs.azure-cli.extensions.aks-preview.overrideAttrs (_: {
    version = "19.0.0b5";
    src = pkgs.fetchurl {
      url = "https://azcliprod.blob.core.windows.net/cli-extensions/aks_preview-19.0.0b5-py2.py3-none-any.whl";
      hash = "sha256-ztbdKTZsuRwX2vilNWkYJ7eMo2bmfjOHATI9I8GfsJE=";
    };
  });

  azure-cli = pkgs.azure-cli.withExtensions [ aks-preview ];
in
pkgs.mkShell {
  packages = [
    azure-cli
    pkgs.python3
    pkgs.python312Packages.pyyaml
    pkgs.kubectl
  ];
}
