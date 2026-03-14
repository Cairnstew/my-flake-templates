{
  description = "Minecraft Forge Mod Development Template";

  inputs = {
    nixpkgs.url    = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ { self, nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      perSystem = { pkgs, ... }:
        let
          # ── Load user config ──────────────────────────────────────
          modConfig = import ./mod-config.nix { inherit pkgs; };

          # ── Auto-select JDK from MC version ───────────────────────
          javaPackage =
            if (builtins.compareVersions modConfig.minecraftVersion "1.17") < 0 then pkgs.jdk8
            else if (builtins.compareVersions modConfig.minecraftVersion "1.18") < 0 then pkgs.jdk16
            else if (builtins.compareVersions modConfig.minecraftVersion "1.20.5") < 0 then pkgs.jdk17
            else pkgs.jdk21;

          # ── gradle.properties — single source of truth ────────────
          modProps = {
            "org.gradle.jvmargs" = "-Xmx${modConfig.gradleMemory}";
            "org.gradle.daemon"  = "false";
            mod_id               = modConfig.modId;
            mod_name             = modConfig.modName;
            mod_version          = modConfig.modVersion;
            mod_group_id         = modConfig.modGroupId;
            mod_authors          = builtins.concatStringsSep ", " modConfig.authors;
            mod_description      = modConfig.modDescription;
            minecraft_version        = modConfig.minecraftVersion;
            minecraft_version_range  = modConfig.minecraftVersionRange;
            forge_version            = modConfig.forgeVersion;
            forge_version_range      = modConfig.forgeVersionRange;
            loader_version_range     = modConfig.loaderVersionRange;
            mapping_channel          = modConfig.mappings.channel;
            mapping_version          = modConfig.mappings.version;
          };

          # Rendered as a file (for sandbox builds)
          gradlePropertiesFile = pkgs.writeText "gradle.properties"
            (builtins.concatStringsSep "\n"
              (pkgs.lib.mapAttrsToList (k: v: "${k}=${v}") modProps));

          # Rendered as -Pkey=value flags (for nix run scripts)
          gradlePFlags = builtins.concatStringsSep " "
            (pkgs.lib.mapAttrsToList (k: v: "-P${k}=${pkgs.lib.escapeShellArg v}") modProps);

          # ── mods.toml — generated from modConfig ──────────────────
          modsToml =
            let
              opt = cond: line: if cond then line + "\n" else "";
              depBlock = dep:
                "\n[[dependencies.${modConfig.modId}]]\n" +
                "    modId        = \"${dep.modId}\"\n" +
                "    mandatory    = ${if dep.mandatory then "true" else "false"}\n" +
                "    versionRange = \"${dep.versionRange}\"\n" +
                "    ordering     = \"${if dep ? ordering then dep.ordering else "NONE"}\"\n" +
                "    side         = \"${if dep ? side then dep.side else "BOTH"}\"\n";
            in
              "modLoader     = \"javafml\"\n" +
              "loaderVersion = \"${modConfig.loaderVersionRange}\"\n" +
              "license       = \"${modConfig.modLicense}\"\n" +
              "\n" +
              "[[mods]]\n" +
              "    modId       = \"${modConfig.modId}\"\n" +
              "    version     = \"${modConfig.modVersion}\"\n" +
              "    displayName = \"${modConfig.modName}\"\n" +
              "    authors     = \"${builtins.concatStringsSep ", " modConfig.authors}\"\n" +
              "    description = '''\n" +
              "${modConfig.modDescription}\n" +
              "    '''\n" +
              opt (modConfig.homepage != "") "    displayURL  = \"${modConfig.homepage}\"" +
              opt (modConfig.logoFile  != "") "    logoFile    = \"${modConfig.logoFile}\"" +
              "\n[[dependencies.${modConfig.modId}]]\n" +
              "    modId        = \"forge\"\n" +
              "    mandatory    = true\n" +
              "    versionRange = \"${modConfig.forgeVersionRange}\"\n" +
              "    ordering     = \"NONE\"\n" +
              "    side         = \"BOTH\"\n" +
              "\n[[dependencies.${modConfig.modId}]]\n" +
              "    modId        = \"minecraft\"\n" +
              "    mandatory    = true\n" +
              "    versionRange = \"${modConfig.minecraftVersionRange}\"\n" +
              "    ordering     = \"NONE\"\n" +
              "    side         = \"BOTH\"\n" +
              builtins.concatStringsSep "" (map depBlock modConfig.dependencies);

          # ── pack.mcmeta — generated when pack_format is set ───────
          packMcmeta = pkgs.lib.optionalString (modConfig.pack_format != null)
            "{\n  \"pack\": {\n    \"description\": \"${modConfig.modName} resources\",\n    \"pack_format\": ${toString modConfig.pack_format}\n  }\n}\n";

          # ── Main class — generated once if missing ─────────────────
          mainClassPath =
            "src/main/java/${builtins.concatStringsSep "/" (pkgs.lib.splitString "." modConfig.modGroupId)}/${modConfig.mainClassName}.java";

          mainClassContent =
            let
              pkg = modConfig.modGroupId;
              cls = modConfig.mainClassName;
              mid = modConfig.modId;
            in
              "package ${pkg};\n\n" +
              "import net.minecraftforge.fml.common.Mod;\n" +
              "import net.minecraftforge.fml.event.lifecycle.FMLCommonSetupEvent;\n" +
              "import net.minecraftforge.fml.event.lifecycle.FMLClientSetupEvent;\n" +
              "import net.minecraftforge.fml.javafmlmod.FMLJavaModLoadingContext;\n" +
              "import org.apache.logging.log4j.LogManager;\n" +
              "import org.apache.logging.log4j.Logger;\n\n" +
              "@Mod(${cls}.MOD_ID)\n" +
              "public class ${cls} {\n\n" +
              "    public static final String MOD_ID = \"${mid}\";\n" +
              "    public static final Logger LOGGER = LogManager.getLogger(MOD_ID);\n\n" +
              "    public ${cls}() {\n" +
              "        var bus = FMLJavaModLoadingContext.get().getModEventBus();\n" +
              "        bus.addListener(this::commonSetup);\n" +
              "        bus.addListener(this::clientSetup);\n" +
              "    }\n\n" +
              "    private void commonSetup(final FMLCommonSetupEvent event) {\n" +
              "        LOGGER.info(\"{} common setup complete\", MOD_ID);\n" +
              "    }\n\n" +
              "    private void clientSetup(final FMLClientSetupEvent event) {\n" +
              "        LOGGER.info(\"{} client setup complete\", MOD_ID);\n" +
              "    }\n" +
              "}\n";

          # ── Gradle run script ─────────────────────────────────────
          # name: bin filename  tasks: space-separated gradle tasks
          makeGradleScript = name: tasks: extraArgs:
            pkgs.writeShellScriptBin "run-${name}" ''
              set -euo pipefail
              export JAVA_HOME="${javaPackage}"
              export PATH="${javaPackage}/bin:${pkgs.gradle}/bin:$PATH"

              find_root() {
                local d="$PWD"
                while [[ "$d" != "/" ]]; do
                  [[ -f "$d/flake.nix" ]] && echo "$d" && return
                  d="$(dirname "$d")"
                done
                echo "$PWD"
              }

              ROOT="''${FLAKE_ROOT:-$(find_root)}"
              echo "→ Project root: $ROOT"
              cd "$ROOT"

              mkdir -p src/main/resources/META-INF
              printf '%s' ${pkgs.lib.escapeShellArg modsToml} > src/main/resources/META-INF/mods.toml

              ${pkgs.lib.optionalString (modConfig.pack_format != null) ''
                printf '%s' ${pkgs.lib.escapeShellArg packMcmeta} > src/main/resources/pack.mcmeta
              ''}

              echo "→ Running: ${tasks}"
              gradle ${tasks} ${extraArgs} ${gradlePFlags} "$@"
            '';

        in
        {
          # ── Dev shell ─────────────────────────────────────────────
          devShells.default = pkgs.mkShell {
            name = "forge-mod-${modConfig.modId}";

            packages = [
              javaPackage
              pkgs.gradle
              pkgs.git
            ] ++ modConfig.extraPackages pkgs;

            env = {
              JAVA_HOME     = javaPackage;
              MOD_ID        = modConfig.modId;
              MOD_NAME      = modConfig.modName;
              MOD_VERSION   = modConfig.modVersion;
              MC_VERSION    = modConfig.minecraftVersion;
              FORGE_VERSION = modConfig.forgeVersion;
            };

            shellHook = ''
              # gradle.properties
              printf '%s\n' ${pkgs.lib.escapeShellArg
                (builtins.concatStringsSep "\n"
                  (pkgs.lib.mapAttrsToList (k: v: "${k}=${v}") modProps))
              } > "$PWD/gradle.properties"

              # mods.toml
              mkdir -p "$PWD/src/main/resources/META-INF"
              printf '%s' ${pkgs.lib.escapeShellArg modsToml} > "$PWD/src/main/resources/META-INF/mods.toml"

              # pack.mcmeta (only when preset defines pack_format)
              ${pkgs.lib.optionalString (modConfig.pack_format != null) ''
                printf '%s' ${pkgs.lib.escapeShellArg packMcmeta} > "$PWD/src/main/resources/pack.mcmeta"
              ''}

              # Main class (only if missing — never overwrites real code)
              if [ ! -f "$PWD/${mainClassPath}" ]; then
                mkdir -p "$(dirname "$PWD/${mainClassPath}")"
                printf '%s' ${pkgs.lib.escapeShellArg mainClassContent} > "$PWD/${mainClassPath}"
                echo "→ Generated ${mainClassPath}"
              fi

              echo ""
              echo "╔══════════════════════════════════════════════════╗"
              echo "║  ${modConfig.modName} — Dev Shell"
              echo "╠══════════════════════════════════════════════════╣"
              echo "║  MC ${modConfig.minecraftVersion}  │  Forge ${modConfig.forgeVersion}  │  Java $(java -version 2>&1 | awk -F'"' 'NR==1{print $2}')"
              echo "║  Mod ID: ${modConfig.modId}  │  Ver: ${modConfig.modVersion}"
              echo "╠══════════════════════════════════════════════════╣"
              echo "║  gradle build       – build jar"
              echo "║  gradle classes runClient  – launch client"
              echo "║  gradle classes runServer  – launch server"
              echo "║  gradle classes runData    – run datagen"
              echo "╚══════════════════════════════════════════════════╝"
              echo ""

              ${modConfig.shellHookExtra pkgs}
            '';
          };

          # ── Packages ──────────────────────────────────────────────
          packages = rec {
            mod = pkgs.stdenv.mkDerivation {
              pname   = modConfig.modId;
              version = modConfig.modVersion;
              src     = ./.;
              nativeBuildInputs = [ javaPackage pkgs.gradle pkgs.git ];
              preBuild = ''
                export HOME=$(mktemp -d)
                export JAVA_HOME="${javaPackage}"
                cp ${gradlePropertiesFile} gradle.properties
                chmod +w gradle.properties
                mkdir -p src/main/resources/META-INF
                printf '%s' ${pkgs.lib.escapeShellArg modsToml} > src/main/resources/META-INF/mods.toml
                ${pkgs.lib.optionalString (modConfig.pack_format != null) ''
                  printf '%s' ${pkgs.lib.escapeShellArg packMcmeta} > src/main/resources/pack.mcmeta
                ''}
              '';
              buildPhase   = "gradle build --no-daemon";
              installPhase = "mkdir -p $out/lib && cp build/libs/*.jar $out/lib/";
              meta = {
                description = modConfig.modDescription;
                homepage    = modConfig.homepage;
                license     = modConfig.license;
              };
            };
            default = mod;
          };

          # ── Apps ──────────────────────────────────────────────────
          apps = {
            build = {
              type    = "app";
              program = "${makeGradleScript "build" "build" "--no-daemon"}/bin/run-build";
            };
            client = {
              type    = "app";
              program = "${makeGradleScript "client" "classes runClient" "--no-daemon"}/bin/run-client";
            };
            server = {
              type    = "app";
              program = "${makeGradleScript "server" "classes runServer" "--no-daemon"}/bin/run-server";
            };
            genData = {
              type    = "app";
              program = "${makeGradleScript "genData" "classes runData" "--no-daemon"}/bin/run-genData";
            };
          };

          checks.build = pkgs.runCommand "check-flake" {} "echo ok > $out";
        };

      flake.templates = {
        default   = self.templates.forge-mod;
        forge-mod = {
          path        = ./.;
          description = "Minecraft Forge mod development template";
          welcomeText = ''
            # Minecraft Forge Mod Template
            1. Edit mod-config.nix
            2. nix develop
            3. gradle classes runClient
          '';
        };
      };
    };
}
