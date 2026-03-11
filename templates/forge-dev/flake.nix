{
  description = "Minecraft mod dev environment (NeoForge / Forge)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # ── Java version ──────────────────────────────────────────────
        # MC 1.20.x / 1.21.x require Java 21
        # MC 1.18.x – 1.19.x require Java 17
        # MC 1.16.x – 1.17.x require Java 16/17
        jdk = pkgs.jdk21;

      in {
        devShells.default = pkgs.mkShell {
          name = "mc-mod-dev";

          packages = [
            jdk

            # Gradle (or let the Gradle wrapper ./gradlew handle it — both work)
            pkgs.gradle

            # Nice to have in the shell
            pkgs.git
            pkgs.curl
            pkgs.jq          # handy for poking at JSON data packs
            pkgs.unzip       # unpacking mod jars for inspection
          ];

          # Point Gradle/JVM toolchains at the Nix JDK
          JAVA_HOME = "${jdk}";

          # Gradle's daemon and caches — keeps them out of your home dir
          GRADLE_USER_HOME = ".gradle-nix";

          # NeoForge's run tasks open a window; tell them where X/Wayland is
          # (only needed when running the game client from `./gradlew runClient`)
          DISPLAY = ":0";

          shellHook = ''
            echo "☕  Java: $(java -version 2>&1 | head -1)"
            echo "🐘  Gradle: $(gradle --version 2>/dev/null | grep Gradle || echo 'using wrapper')"
            echo ""
            echo "Useful tasks:"
            echo "  ./gradlew build          → compile & package the mod"
            echo "  ./gradlew runClient      → launch game client for testing"
            echo "  ./gradlew runServer      → launch headless test server"
            echo "  ./gradlew runData        → regenerate data packs"
          '';
        };
      }
    );
}