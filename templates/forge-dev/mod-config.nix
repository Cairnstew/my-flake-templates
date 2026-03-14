# ══════════════════════════════════════════════════════════════════
#  mod-config.nix  —  Everything lives here. Edit freely.
#  The flake reads this and generates gradle.properties, mods.toml,
#  pack.mcmeta, and your main class automatically.
# ══════════════════════════════════════════════════════════════════
{ pkgs }:

let
  # ── Version presets ───────────────────────────────────────────
  # Switch MC/Forge/Java/pack_format in one line.
  presets = {
    mc1_20_4 = {
      minecraftVersion      = "1.20.4";
      minecraftVersionRange = "[1.20.4,1.21)";
      forgeVersion          = "49.0.30";
      forgeVersionRange     = "[49,)";
      loaderVersionRange    = "[47,)";
      mappings              = { channel = "official"; version = "1.20.4"; };
      pack_format           = 26;
    };
    mc1_20_1 = {
      minecraftVersion      = "1.20.1";
      minecraftVersionRange = "[1.20,1.21)";
      forgeVersion          = "47.2.20";
      forgeVersionRange     = "[47,)";
      loaderVersionRange    = "[47,)";
      mappings              = { channel = "official"; version = "1.20.1"; };
      pack_format           = 15;
    };
    mc1_19_2 = {
      minecraftVersion      = "1.19.2";
      minecraftVersionRange = "[1.19,1.20)";
      forgeVersion          = "43.3.5";
      forgeVersionRange     = "[43,)";
      loaderVersionRange    = "[40,)";
      mappings              = { channel = "official"; version = "1.19.2"; };
      pack_format           = 9;
    };
    mc1_18_2 = {
      minecraftVersion      = "1.18.2";
      minecraftVersionRange = "[1.18.2,1.19)";
      forgeVersion          = "40.2.21";
      forgeVersionRange     = "[40,)";
      loaderVersionRange    = "[38,)";
      mappings              = { channel = "official"; version = "1.18.2"; };
      pack_format           = 8;
    };
    mc1_16_5 = {
      minecraftVersion      = "1.16.5";
      minecraftVersionRange = "[1.16.5,1.17)";
      forgeVersion          = "36.2.39";
      forgeVersionRange     = "[36,)";
      loaderVersionRange    = "[36,)";
      mappings              = { channel = "snapshot"; version = "20210309-1.16.5"; };
      pack_format           = null;  # pack.mcmeta didn't exist in 1.16
    };
  };

  # ── Active preset — change this one line to switch versions ───
  preset = presets.mc1_20_1;

in preset // {

  # ── Identity ──────────────────────────────────────────────────
  modId          = "examplemod";
  modName        = "Example Mod";
  modVersion     = "1.0.0";
  modGroupId     = "com.example.examplemod";   # also used as Java package
  mainClassName  = "ExampleMod";               # must match your @Mod class
  modDescription = "A dynamically configured Minecraft Forge mod.";
  homepage       = "https://github.com/example/examplemod";
  logoFile       = "";           # e.g. "logo.png" placed in src/main/resources/
  authors        = [ "YourName" ];
  modLicense     = "MIT";        # string written into mods.toml
  license        = pkgs.lib.licenses.mit;  # Nix license attr for package meta

  # ── Gradle JVM heap ───────────────────────────────────────────
  gradleMemory = "2G";           # increase to "4G" if decompilation OOMs

  # ── Mod dependencies ──────────────────────────────────────────
  # Each entry becomes a [[dependencies.modid]] block in mods.toml.
  # forge and minecraft are always added automatically.
  dependencies = [
    # {
    #   modId        = "jei";
    #   mandatory    = false;
    #   versionRange = "[*,)";
    #   # ordering and side are optional — default to NONE / BOTH
    # }
  ];

  # ── Extra Nix packages in the dev shell ───────────────────────
  extraPackages = pkgs: with pkgs; [
    mesa
    libGL
    libGLU
    xorg.libX11
    xorg.libXext
    xorg.libXrandr
    xorg.libXi
    xorg.libXcursor
    xorg.libXinerama
  ];

  # ── Shell hook extras ─────────────────────────────────────────
  # Receives pkgs so you can reference store paths safely.
  shellHookExtra = pkgs: ''
    export DISPLAY=''${DISPLAY:-:0}
    export WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-wayland-0}
    export LD_LIBRARY_PATH="${pkgs.mesa}/lib:${pkgs.libGL}/lib:${pkgs.xorg.libX11}/lib:$LD_LIBRARY_PATH"
    export LIBGL_ALWAYS_INDIRECT=0
    export MESA_GL_VERSION_OVERRIDE=4.6
  '';
}
