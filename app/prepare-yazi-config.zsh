#!/bin/zsh
set -euo pipefail

RESOURCE_DIR=${0:A:h}
PERSONAL_CONFIG=${YAZI_CONFIG_HOME:-$HOME/.config/yazi}

# Older launcher versions passed the bundled picker config down to Neovim.
# In that case, recover the user's real Yazi configuration directory.
if [[ "$PERSONAL_CONFIG" == "$RESOURCE_DIR/YaziPicker" || ! -d "$PERSONAL_CONFIG" ]]; then
   PERSONAL_CONFIG="$HOME/.config/yazi"
fi

TEMP_ROOT=${TMPDIR:-/tmp/}
RUNTIME_CONFIG=$(/usr/bin/mktemp -d "${TEMP_ROOT%/}/nvim-wezterm-yazi.XXXXXX")

for ENTRY in "$PERSONAL_CONFIG"/*(DN); do
   NAME=${ENTRY:t}
   if [[ "$NAME" != "keymap.toml" ]]; then
      /bin/ln -s "$ENTRY" "$RUNTIME_CONFIG/$NAME"
   fi
done

/bin/cp "$RESOURCE_DIR/YaziPicker/keymap.toml" "$RUNTIME_CONFIG/keymap.toml"
print -r -- "$RUNTIME_CONFIG"
