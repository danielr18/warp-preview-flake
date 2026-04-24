{
  description = "Warp Terminal (preview) packaged from .deb, aarch64 + x86_64";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # Single source of truth for the pinned preview build. Bump these three
      # fields (and regenerate hashes) to update.
      #
      # Release directory on releases.warp.dev uses an underscore before the
      # trailing counter ("preview_02"), while the filename keeps the dot
      # ("preview.02"). Until we add an auto-bump workflow, keep both forms
      # in lockstep when editing by hand.
      version = "0.2026.04.23.19.42.preview.02";
      versionPath = "0.2026.04.23.19.42.preview_02";
      hashes = {
        amd64 = "sha256-UhWkBYtflgzpqIhYVNyPe5ECjOH6wabx1fvNsVT4M+U=";
        arm64 = "sha256-TYM+8GdQ7AXP2FhzyGN6Ac1huRlxlo4F6mrAOxHTMcU=";
      };

      systemToDeb = {
        "x86_64-linux" = "amd64";
        "aarch64-linux" = "arm64";
      };

      systems = builtins.attrNames systemToDeb;

      forAll =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              config.allowUnfree = true;
            }
          ) system
        );
    in
    {
      packages = forAll (
        pkgs: system:
        let
          debArch = systemToDeb.${system};
          url = "https://releases.warp.dev/preview/v${versionPath}/warp-terminal-preview_${version}_${debArch}.deb";
        in
        {
          default = pkgs.stdenv.mkDerivation {
            pname = "warp-terminal-preview";
            inherit version;

            src = pkgs.fetchurl {
              inherit url;
              hash = hashes.${debArch};
              name = "warp-preview-${debArch}.deb";
            };

            nativeBuildInputs = [
              pkgs.autoPatchelfHook
              pkgs.dpkg
              pkgs.makeWrapper
              pkgs.file
            ];
            buildInputs = with pkgs; [
              stdenv.cc.cc
              zlib
              libGL
              curl
              alsa-lib
              xorg.libX11
              xorg.libXext
              xorg.libXcursor
              xorg.libXi
              xorg.libXrandr
              xorg.libxcb
              libxkbcommon
              wayland
              gtk3
              pango
              cairo
              fontconfig
              freetype
              libdrm
              libdecor
            ];

            # dpkg-deb's internal tar tries to apply the archive's `./` entry
            # metadata to the build-dir root. Under determinate-nixd's
            # external-builder (used when we cross-build aarch64-linux from
            # darwin) the build dir is a virtiofs mount that denies chmod
            # and utime on its own root, so the unpack aborts. Extracting
            # into a subdirectory sidesteps it: tar's metadata target is a
            # sibling directory we fully own, not the mount root.
            unpackPhase = ''
              runHook preUnpack
              mkdir extracted
              dpkg-deb --fsys-tarfile $src \
                | tar -x -C extracted --no-same-owner --no-same-permissions
              cd extracted
              runHook postUnpack
            '';

            installPhase = ''
              runHook preInstall

              mkdir -p $out/bin $out/share
              cp -r usr/share/* $out/share/
              cp -r opt/warpdotdev/warp-terminal-preview $out/libexec

              # winit's wayland backend dlopens libwayland-client at runtime;
              # nothing RPATHs it, so LD_LIBRARY_PATH has to point at wayland,
              # libxkbcommon, and libdecor for the wayland event loop to open
              # without panicking into the X11 crash-recovery fallback.
              makeWrapper $out/libexec/warp-preview $out/bin/warp \
                --prefix PATH : /run/wrappers/bin \
                --prefix XDG_DATA_DIRS : "$out/share" \
                --prefix LD_LIBRARY_PATH : ${
                  pkgs.lib.makeLibraryPath [
                    pkgs.libGL
                    pkgs.libxkbcommon
                    pkgs.wayland
                    pkgs.libdecor
                    pkgs.xorg.libX11
                    pkgs.xorg.libXcursor
                    pkgs.xorg.libXi
                    pkgs.xorg.libXrandr
                    pkgs.fontconfig
                    pkgs.freetype
                  ]
                }

              # The upstream .desktop file hardcodes an Exec path that won't
              # exist in the nix store; rewrite it to the wrapper we just built.
              if [ -d "$out/share/applications" ]; then
                for d in "$out/share/applications/"*.desktop; do
                  [ -f "$d" ] || continue
                  sed -i "s|^Exec=.*|Exec=$out/bin/warp|" "$d" || true
                  sed -i "s|^TryExec=.*|TryExec=$out/bin/warp|" "$d" || true
                done
              fi

              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "Warp Terminal (preview) packaged from vendor .deb";
              platforms = systems;
              license = licenses.unfree;
              mainProgram = "warp";
            };
          };
        }
      );

      apps = forAll (pkgs: system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/warp";
        };
      });

      checks = forAll (pkgs: system: {
        build = self.packages.${system}.default;
      });
    };
}
