#!/bin/zsh
set -u

RESOURCE_DIR=${0:A:h}
START_DIR=${1:-$HOME}
CWD_FILE=$(/usr/bin/mktemp -t nvim-wezterm-workspace)
ORIGINAL_YAZI_CONFIG_HOME=${YAZI_CONFIG_HOME-}
PICKER_CONFIG=""

function cleanup {
   /bin/rm -f "$CWD_FILE"
   if [[ -n "$PICKER_CONFIG" && "${PICKER_CONFIG:t}" == nvim-wezterm-yazi.* ]]; then
      /bin/rm -rf "$PICKER_CONFIG"
   fi
}

trap cleanup EXIT INT TERM

if [[ -x /opt/homebrew/bin/yazi ]]; then
   YAZI_BIN=/opt/homebrew/bin/yazi
elif [[ -x /usr/local/bin/yazi ]]; then
   YAZI_BIN=/usr/local/bin/yazi
else
   print -u2 "Yazi non è installato."
   exit 1
fi

PICKER_CONFIG=$("$RESOURCE_DIR/prepare-yazi-config.zsh") || exit 1
export YAZI_CONFIG_HOME="$PICKER_CONFIG"
"$YAZI_BIN" "$START_DIR" --cwd-file "$CWD_FILE"

if [[ -n "$ORIGINAL_YAZI_CONFIG_HOME" ]]; then
   export YAZI_CONFIG_HOME="$ORIGINAL_YAZI_CONFIG_HOME"
else
   unset YAZI_CONFIG_HOME
fi

if [[ ! -s "$CWD_FILE" ]]; then
   exit 0
fi

IFS= read -r -d '' WORKSPACE < "$CWD_FILE" || true
cleanup
trap - EXIT INT TERM

if [[ -z "$WORKSPACE" || ! -d "$WORKSPACE" ]]; then
   exit 0
fi

cd "$WORKSPACE" || exit 1

if [[ -z "${NEOVIM_APP_SERVER_ADDRESS:-}" ]]; then
   print -u2 "Il canale della sessione Neovim non è disponibile."
   exit 1
fi

if [[ -x /opt/homebrew/bin/nvim ]]; then
   exec /opt/homebrew/bin/nvim --listen "$NEOVIM_APP_SERVER_ADDRESS" "$WORKSPACE"
elif [[ -x /usr/local/bin/nvim ]]; then
   exec /usr/local/bin/nvim --listen "$NEOVIM_APP_SERVER_ADDRESS" "$WORKSPACE"
else
   exec nvim --listen "$NEOVIM_APP_SERVER_ADDRESS" "$WORKSPACE"
fi
