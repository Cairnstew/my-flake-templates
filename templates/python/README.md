# uv2nix Python Project Template

A Nix flake template for Python projects using [uv2nix](https://github.com/pyproject-nix/uv2nix) — reproducible Python environments with uv's fast dependency resolution.

## Prerequisites

- [Nix](https://nixos.org/download) with flakes enabled
- Git (the flake must be inside a git repo)

## Quick Start

### 1. Bootstrap a new project

```bash
nix develop .#bootstrap
# scaffolds ./backend, then: cd backend && uv add <pkg>
exit
```

The bootstrap shell will:
- Run `uv init --app --package ./backend` if `./backend` doesn't exist yet
- Auto-stage `uv.lock` and `pyproject.toml` with `git add` on exit

### 2. Enter the dev shell

```bash
nix develop
```

## Shells & Commands

| Command | Description |
|---|---|
| `nix develop` | Full dev shell with editable virtualenv |
| `nix develop .#bootstrap` | Lightweight shell for initialising or adding packages |
| `nix build` | Build a production virtualenv |
| `nix run` | Scaffold a new uv app (same as bootstrap init step) |

## Adding Dependencies

Always use the bootstrap shell to add packages — the default dev shell intentionally disables uv syncing:

```bash
nix develop .#bootstrap
cd backend
uv add <pkg>
exit         # auto-stages uv.lock and pyproject.toml
nix develop  # rebuild dev shell with new deps
```

## Customising the Flake

### Python version

Change the `python` variable near the top of `flake.nix`:

```nix
python = pkgs.python312;  # change to e.g. pkgs.python313
```

Make sure your `uv.lock` was generated with the same version — if not, regenerate it:

```bash
nix develop .#bootstrap
cd backend && rm uv.lock && uv lock
exit
```

### Extra dev tools (JDK, etc.)

Uncomment and add to `devShells.default` in `flake.nix`:

```nix
packages = [
  virtualenv
  pkgs.uv
  pkgs.jdk17   # <-- add packages here
];

env = {
  # ...
  JAVA_HOME = "${pkgs.jdk17}";  # <-- add env vars here
};
```

### Package build overrides (`customOverlay`)

Some PyPI packages don't declare all their build dependencies. Add overrides in the `customOverlay` block:

```nix
customOverlay = self: super: {
  pyspark = super.pyspark.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
      self.setuptools
    ];
  });
};
```

### CUDA / PyTorch (`nvidiaOverlay`)

CUDA support is pre-configured but disabled by default. To enable:

1. Uncomment `cudaSupport = true;` in the `pkgs` config
2. Uncomment `# nvidiaOverlay` in `composeManyExtensions`
3. Add your torch/CUDA packages via `nix develop .#bootstrap`

## Project Structure

```
.
├── flake.nix
├── flake.lock
└── backend/           # uv workspace root
    ├── pyproject.toml
    ├── uv.lock
    └── src/
```

## How It Works

- `workspaceRoot = ./backend` — uv2nix reads the workspace from `./backend`
- The dev shell uses an **editable install** (`editableOverlay`) so source changes are reflected immediately without rebuilding
- `UV_NO_SYNC = "1"` and `UV_PYTHON_DOWNLOADS = "never"` prevent uv from managing the environment — Nix owns it
- `REPO_ROOT` is set via `git rev-parse` in the `shellHook` and used to resolve the editable install path at runtime

## Troubleshooting

**`uv.lock: No such file or directory`** — the lockfile hasn't been git-staged. Run:
```bash
git add backend/uv.lock backend/pyproject.toml
```

**Python version mismatch** — your `uv.lock` was generated with a different Python version than `python = pkgs.pythonXXX` in the flake. Regenerate the lockfile in `.#bootstrap` or align the versions.

**`Editable root was passed as a Nix store path`** — `editableOverlay` must use a string or env var, not a Nix path. It should be `root = "$REPO_ROOT/backend"`.