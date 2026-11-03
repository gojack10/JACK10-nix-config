{ lib, stdenv, gnumake, makeWrapper, python3, uv }:

stdenv.mkDerivation {
  pname = "m5-max-dashboard";
  version = "1.0";
  src = lib.cleanSource ./.;
  nativeBuildInputs = [ gnumake makeWrapper ];

  buildPhase = ''
    runHook preBuild
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
    make -j$NIX_BUILD_CORES \
      CC=/Library/Developer/CommandLineTools/usr/bin/clang \
      SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 .build/m5-max-dashboard "$out/bin/m5-max-dashboard"
    app="$out/Applications/M5 Max Dashboard.app"
    mkdir -p "$app/Contents/MacOS" "$out/share/m5-max-dashboard"
    install -m755 .build/m5-max-dashboard-menu "$app/Contents/MacOS/m5-max-dashboard-menu"
    cp menubar/Info.plist "$app/Contents/Info.plist"
    cp -R web/. "$out/share/m5-max-dashboard/"
    install -m755 .build/libmetrics.dylib "$out/share/m5-max-dashboard/libmetrics.dylib"
    makeWrapper ${uv}/bin/uv "$out/bin/m5-max-dashboard-web" \
      --add-flags "run --offline --no-project --python ${python3}/bin/python3 $out/share/m5-max-dashboard/app.py"
    runHook postInstall
  '';

  postFixup = ''
    /usr/bin/codesign --force --sign - "$out/bin/m5-max-dashboard"
    /usr/bin/codesign --force --sign - "$out/share/m5-max-dashboard/libmetrics.dylib"
    /usr/bin/codesign --force --sign - "$out/Applications/M5 Max Dashboard.app"
  '';

  meta = {
    description = "Read-only M5 Max system pulse - web, menu bar and terminal";
    mainProgram = "m5-max-dashboard";
    platforms = [ "aarch64-darwin" ];
  };
}
