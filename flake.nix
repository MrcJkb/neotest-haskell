{
  description = "A Neotest adapter for Haskell.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    packer-nvim = {
      url = "github:wbthomason/packer.nvim";
      flake = false;
    };

    plenary-nvim = {
      url = "github:nvim-lua/plenary.nvim";
      flake = false;
    };

    neotest = {
      url = "github:nvim-neotest/neotest";
      flake = false;
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    pre-commit-hooks,
    packer-nvim,
    plenary-nvim,
    neotest,
    ...
  }: let
    name = "neotest-haskell";

    supportedSystems = [
      "aarch64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
      "x86_64-linux"
    ];
    perSystem = nixpkgs.lib.genAttrs supportedSystems;
    pkgsFor = system: import nixpkgs {inherit system;};

    ci-overlay = import ./nix/ci-overlay.nix {inherit (inputs) packer-nvim plenary-nvim neotest;};
    nvim-plugin-overlay = import ./nix/nvim-plugin-overlay.nix {
      inherit name;
      self = ./.;
    };

    nvim-plugin-for = system: let
      pkgs = pkgsFor system;
    in
      pkgs.vimUtils.buildVimPluginFrom2Nix {
        inherit name;
        src = ./.;
      };

    pre-commit-check-for = system:
      pre-commit-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          alejandra.enable = true;
          stylua.enable = true;
        };
      };

    shellFor = system: let
      pkgs = pkgsFor system;
      pre-commit-check = pre-commit-check-for system;
    in
      pkgs.mkShell {
        name = "neotest-haskell devShell";
        inherit (pre-commit-check) shellHook;
        buildInputs = with pkgs; [
          zlib
          stylua
          alejandra
        ];
      };
  in {
    overlays = {
      inherit ci-overlay nvim-plugin-overlay;
      default = nvim-plugin-overlay;
    };

    devShells = perSystem (system: rec {
      default = devShell;
      devShell = shellFor system;
    });

    packages = perSystem (system: rec {
      default = nvim-plugin;
      nvim-plugin = nvim-plugin-for system;
    });

    checks = perSystem (system: let
      checkPkgs = import nixpkgs {
        inherit system;
        overlays = [ci-overlay];
      };
    in {
      formatting = pre-commit-check-for system;
      inherit (checkPkgs) ci;
    });
  };
}
