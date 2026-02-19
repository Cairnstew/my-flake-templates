# my-flake-templates

A personal collection of Nix flake templates for quickly bootstrapping new projects with reproducible development environments.

## Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled

To enable flakes, add the following to your Nix configuration:

```nix
# /etc/nixos/configuration.nix (NixOS)
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

Or for non-NixOS systems, add to `~/.config/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

## Usage

### Browse available templates

```bash
nix flake show github:Cairnstew/my-flake-templates
```

### Initialize a template in a new project

```bash
mkdir my-project && cd my-project
nix flake init -t github:Cairnstew/my-flake-templates#<template-name>
```

Or create a new project directory with `nix flake new`:

```bash
nix flake new -t github:Cairnstew/my-flake-templates#<template-name> my-project
```

### Enter the development shell

Once a template is initialized:

```bash
nix develop
```

Optionally, use [direnv](https://direnv.net/) with [nix-direnv](https://github.com/nix-community/nix-direnv) to automatically load the environment when you enter the directory:

```bash
echo "use flake" > .envrc
direnv allow
```

## Templates

| Template | Description |
|----------|-------------|
| *(run `nix flake show` to see available templates)* | |

## Notes

- Templates are intended as personal starting points and may be opinionated.
- After initializing a template, remember to `git add` the generated files — Nix flakes only track files known to Git.

## License

See individual template files for licensing details.