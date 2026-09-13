#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_DIR="$PROJECT_DIR/outputs"
APP_DIR="$OUTPUT_DIR/Neovim.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
WEZTERM_HELPER_APP="$HELPERS_DIR/NeovimWezTermHelper.app"
WEZTERM_HELPER_MACOS="$WEZTERM_HELPER_APP/Contents/MacOS"
WEZTERM_HELPER_RESOURCES="$WEZTERM_HELPER_APP/Contents/Resources"
MODULE_CACHE_DIR="$BUILD_DIR/ModuleCache"
WEZTERM_GUI_BINARY=${NEOVIM_WEZTERM_GUI:-}
WEZTERM_RESOURCES_DIR=${NEOVIM_WEZTERM_RESOURCES:-/Applications/WezTerm.app/Contents/Resources}

if [[ -z "$WEZTERM_GUI_BINARY" || ! -x "$WEZTERM_GUI_BINARY" ]]; then
   echo "Imposta NEOVIM_WEZTERM_GUI sul binario wezterm-gui del branch tab-config-overrides del fork 03kev/wezterm." >&2
   exit 1
fi
if ! /usr/bin/grep -aFq "WEZTERM_MACOS_ACTIVATION_POLICY" "$WEZTERM_GUI_BINARY"; then
   echo "Il binario wezterm-gui non contiene l'override macOS richiesto dal launcher." >&2
   exit 1
fi
if [[ ! -d "$WEZTERM_RESOURCES_DIR" ]]; then
   echo "Le risorse di WezTerm non sono disponibili in $WEZTERM_RESOURCES_DIR." >&2
   exit 1
fi

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR" "$MODULE_CACHE_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$WEZTERM_HELPER_MACOS" "$WEZTERM_HELPER_RESOURCES"

export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"
export SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR"

xcrun swiftc -O -whole-module-optimization -target arm64-apple-macosx12.0 \
   "$SCRIPT_DIR/main.swift" -o "$BUILD_DIR/NvimWezTerm-arm64"
xcrun swiftc -O -whole-module-optimization -target x86_64-apple-macosx12.0 \
   "$SCRIPT_DIR/main.swift" -o "$BUILD_DIR/NvimWezTerm-x86_64"
/usr/bin/lipo -create \
   "$BUILD_DIR/NvimWezTerm-arm64" \
   "$BUILD_DIR/NvimWezTerm-x86_64" \
   -output "$MACOS_DIR/NvimWezTerm"

/bin/cp "$SCRIPT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
/bin/cp "$SCRIPT_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
/bin/cp "$SCRIPT_DIR/workspace-picker.zsh" "$RESOURCES_DIR/workspace-picker.zsh"
/bin/chmod +x "$RESOURCES_DIR/workspace-picker.zsh"
/bin/cp "$SCRIPT_DIR/prepare-yazi-config.zsh" "$RESOURCES_DIR/prepare-yazi-config.zsh"
/bin/chmod +x "$RESOURCES_DIR/prepare-yazi-config.zsh"
/bin/cp -R "$SCRIPT_DIR/YaziPicker" "$RESOURCES_DIR/YaziPicker"
/bin/cp "$SCRIPT_DIR/WezTermHelper-Info.plist" "$WEZTERM_HELPER_APP/Contents/Info.plist"
/bin/cp "$WEZTERM_GUI_BINARY" "$WEZTERM_HELPER_MACOS/wezterm-gui"
/bin/chmod +x "$WEZTERM_HELPER_MACOS/wezterm-gui"
/bin/cp -R "$WEZTERM_RESOURCES_DIR/." "$WEZTERM_HELPER_RESOURCES/"
/bin/cp "$SCRIPT_DIR/WezTerm-LICENSE.md" "$WEZTERM_HELPER_RESOURCES/WezTerm-LICENSE.md"
/usr/bin/codesign --force --sign - "$WEZTERM_HELPER_APP"
/usr/bin/codesign --force --deep --sign - "$APP_DIR"

/bin/rm -f "$OUTPUT_DIR/Neovim.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
   "$APP_DIR" "$OUTPUT_DIR/Neovim.zip"

echo "$APP_DIR"
