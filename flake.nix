{
  description = "A collection of flake templates for Python projects";
  
  outputs = { self, ... }:
    {
      templates = {
        jax-equinox-basics = {
          path = ./templates/jax-equinox-basics;
          description = "Template for a basic machine learning project with Jax (equinox)";
        };

        langchain-basics = {
          path = ./templates/langchain-basics;
          description = "Template for a basic langchain project";
        };

        cpp-starter-kit = {
          path = ./templates/cpp-starter-kit;
          description = "A nix based c++ development project skeleton with CMake";
        };

        forge-dev = {
          path = ./templates/forge-dev;
          description = "A Minecraft mod development environment with NeoForge / Forge";
        };

        nixos-config = {
          path = ./templates/nixos-config;
          description = "Template for creating a repo that hosts your NixOS configurations";
        };

        pnpm-webapp-starter = {
          path = ./templates/pnpm-webapp-starter;
          description = ''
            Template for creating repo of webapp development with pnpm.
          '';
        };

        pybind11-starter-kit = {
          path = ./templates/pybind11-starter-kit;
          description = ''
            Template for creating initial skeleton for a pybind11 project
          '';
        };

        maturin-basics = {
          path = ./templates/maturin-basics;
          description = ''
            Minimal starting project for nix-based maturin package development
          '';
        };

        python = {
          path = ./templates/python;
          description = ''
            Starting project for nix-based python project development
          '';
        };
        vm-deploy = {
          path = ./templates/vm-deploy;
          description = ''
            Template for building and deploying a NixOS image to GCP or AWS.
          '';
        };
    };
  };
}
