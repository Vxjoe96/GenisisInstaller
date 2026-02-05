#!/usr/bin/env bash

##########

# MIT License

# Copyright (c) 2025 Phillip MacNaughton "Wisher"

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

##########

# For Assistance and Information, view (https://gitlab.com/Wisher/ProtonShim)

set -euo pipefail

cleanup() {
  echo
  echo "Received SIGINT (Ctrl+C), cleaning up and exiting..." >&2
  # Optionally clean up:
  [ -f "$TMP_WRAPPER" ] && rm -f "$TMP_WRAPPER"
  exit 130  # 128 + 2 (SIGINT) for clarity
}

trap cleanup SIGINT

# ==== PROGRAM VERSION ====
VERSION=2.7.0

# ==== Test Vars ====
FORCE_CHOICE="${FORCE_CHOICE:-}"

# ==== PROGRAM SETTINGS ====
CLI_STEAM_PATH=""
CLI_PROTON_VERSION=""
CONFIG_DIR="$HOME/.config/proton-shim"
CONFIG_FILE_STEAM="$CONFIG_DIR/config_steam"
STEAM_COMPAT_CLIENT_INSTALL_PATH=""
TMP_WRAPPER=""
APPID=""
POSITIONAL_ARGS=()
EXTRA_ARGS=()
PARSE_EXTRA=false
PROGRAM_PATH=""
PROGRAM_WORKDIR=""
PROTON_PATH=""
PROTON_DIR=""
SEARCH_MODE=false
DEBUG_MODE=false
SHOW_COMMAND=false
SHOW_LICENSE=false
AUTO_YES=false
NO_PROMPT=false
CREATE_DESKTOP_NAME=""
HAS_DESKTOP=false
DESKTOP_ICON=""
DESKTOP_OUTPUT="user"
WRAPPER_OUTPUT="local"
CREATE_WRAPPER_NAME=""
HAS_WRAPPER=false
DRY_RUN=false
USE_NAME=false
RESET_CONFIGS=false
FORK_EXECUTABLE=false
WINE_64=false
USE_ESYNC=false
USE_FSYNC=false
USE_PROTON_NO_ESYNC=false
USE_PROTON_NO_FSYNC=false

# ==== CLI ARGUMENTS ====
SHOW_HELP=false
LIST_MODE=""

# ==== DERIVED VALUES ====
STEAM_COMPAT_DATA_PATH=""

load_config() {
    if [[ -f "$CONFIG_FILE_STEAM" ]]; then
        source "$CONFIG_FILE_STEAM"
    fi
}

configure_proton() {
    readarray -t steam_libraries < <(find_steam_libraries)
    PROTON_DISPLAY_NAMES=()
    PROTON_FULL_PATHS=()
    declare -A SEEN_PROTONS=()

    for lib in "${steam_libraries[@]}"; do
        COMMON_PATH="$lib/common"
        if [ -d "$COMMON_PATH" ]; then
            while IFS= read -r -d '' dir; do
                dir_name="$(basename "$dir")"
                if [[ "$dir_name" =~ ^[Pp]roton.* && -x "$dir/proton" ]]; then
                    if [[ -z "${SEEN_PROTONS[$dir_name]+x}" ]]; then
                        PROTON_DISPLAY_NAMES+=("$dir_name")
                        PROTON_FULL_PATHS+=("$dir")
                        SEEN_PROTONS[$dir_name]=1
                    fi
                fi
            done < <(find "$COMMON_PATH" -maxdepth 1 -mindepth 1 -type d -print0 | sort -z)
        fi
    done

    if [ "${#PROTON_DISPLAY_NAMES[@]}" -eq 0 ]; then
        echo "No Proton versions found in any libraries"
    fi

    # Also check for installed Proton GE versions (or other proton variants that happen to be in these locations)
    GE_PATHS=(
        "$HOME/.steam/root/compatibilitytools.d"
        "$HOME/.local/share/Steam/compatibilitytools.d"
        "$STEAM_COMPAT_CLIENT_INSTALL_PATH/compatibilitytools.d"
        /usr/share/steam/compatibilitytools.d/
        /usr/share
        /opt
    )

    for ge_dir in "${GE_PATHS[@]}"; do
        if [ -d "$ge_dir" ]; then
            while IFS= read -r -d '' dir; do
                dir_name="$(basename "$dir")"
                if [[ "$dir_name" =~ ^[Pp]roton.* && -x "$dir/proton" ]]; then
                    if [[ -z "${SEEN_PROTONS[$dir_name]+x}" ]]; then
                        PROTON_DISPLAY_NAMES+=("$dir_name")
                        PROTON_FULL_PATHS+=("$dir")
                        SEEN_PROTONS[$dir_name]=1
                    fi
                fi
            done < <(find "$ge_dir" -maxdepth 1 -mindepth 1 -type d -print0 | sort -z)
        fi
    done

    if [ "${#PROTON_DISPLAY_NAMES[@]}" -eq 0 ]; then
        echo "No Proton versions found in any libraries or compatibility tool locations."
        echo "No Proton versions found anywhere, please install a proton version or log this as an issue"
        exit 1
    fi
    
        if [ "${#PROTON_DISPLAY_NAMES[@]}" -ne "${#PROTON_FULL_PATHS[@]}" ]; then
        echo "Critical error encountered, proton paths array length not equal to proton display names array length"
        echo "Please report this error"
        exit 1
    fi

    # Use CLI proton path otherwise use found ones earlier
    if [[ -n "$CLI_PROTON_VERSION" ]]; then
        PROTON_VERSION="$CLI_PROTON_VERSION"
        found=false
        for i in "${!PROTON_DISPLAY_NAMES[@]}"; do
            if [[ "${PROTON_DISPLAY_NAMES[$i]}" == "$PROTON_VERSION" ]]; then
                PROTON_PATH="${PROTON_FULL_PATHS[$i]}"
                found=true
                break
            fi
        done
        if ! $found; then
            echo "Error: Proton version '$PROTON_VERSION' specified via CLI was not found in detected Proton installation locations."
            exit 1
        fi
    elif [[ -z "$LIST_MODE" ]]; then
        if $NO_PROMPT; then
            echo "Error: --no-prompt specified, but no --proton version was provided."
            echo "Please provide a Proton version using --proton <VERSION>."
            exit 1
        fi

        echo "Available Proton versions:"
        for i in "${!PROTON_DISPLAY_NAMES[@]}"; do
            echo "  [$i] ${PROTON_DISPLAY_NAMES[$i]}"
        done

        if [[ -n "$FORCE_CHOICE" ]]; then
            choice="$FORCE_CHOICE"
        else
            read -rp "Select Proton version [0-$((${#PROTON_DISPLAY_NAMES[@]} - 1))]: " choice
            if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -ge "${#PROTON_DISPLAY_NAMES[@]}" ]; then
                echo "Invalid choice."
                exit 1
            fi
        fi
        PROTON_VERSION="${PROTON_DISPLAY_NAMES[$choice]}"
        PROTON_PATH="${PROTON_FULL_PATHS[$choice]}"
        echo "Using Proton Version: ${PROTON_VERSION} at path: ${PROTON_PATH}"
    fi

    # ==== RESOLVE AND VALIDATE PROTON PATH ====
    if [[ -z "$LIST_MODE" ]]; then

        # Validate proton is found and is executable
        if [[ -d "$PROTON_PATH" && -x "$PROTON_PATH/proton" ]]; then
            PROTON_DIR="$PROTON_PATH"
            PROTON_PATH="$PROTON_PATH/proton"
        else 
            echo "Error: Proton version '$PROTON_VERSION' not found or does not contain an executable 'proton' script."
            echo "Expected Directory: ${PROTON_PATH}"
            exit 1
        fi
    fi
}

find_steam_path() {
    if [[ -n "$CLI_STEAM_PATH" ]]; then
        if [[ -d "$CLI_STEAM_PATH/steamapps" && -f "$CLI_STEAM_PATH/steamapps/libraryfolders.vdf" ]]; then
            STEAM_COMPAT_CLIENT_INSTALL_PATH="$CLI_STEAM_PATH"
        else
            echo "Error: '$CLI_STEAM_PATH' is not a valid Steam installation (missing steamapps/libraryfolders.vdf)."
            exit 1
        fi
    elif [[ -n "$STEAM_COMPAT_CLIENT_INSTALL_PATH" && -d "$STEAM_COMPAT_CLIENT_INSTALL_PATH/steamapps" && -f "$STEAM_COMPAT_CLIENT_INSTALL_PATH/steamapps/libraryfolders.vdf" ]]; then
        echo "Using cached Steam path: $STEAM_COMPAT_CLIENT_INSTALL_PATH"
    else
        POTENTIAL_STEAM_PATHS=(
            # Native installs
            "$HOME/.steam/steam"
            "$HOME/.local/share/Steam"
            "$HOME/.steam/root"

            # Steam Flatpak install
            "$HOME/.var/app/com.valvesoftware.Steam/.steam/steam"
            "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"

            # Steam Deck (game mode user)
            "$HOME/.steam"
            "/run/media/mmcblk0p1"
            "/run/media/mmcblk0p1/SteamLibrary"
            "/run/media/mmcblk0p1/steamapps"

            # System-wide installs
            "/usr/local/share/Steam"
            "/usr/lib/steam"
            "/opt/steam"
        )

        for path in "${POTENTIAL_STEAM_PATHS[@]}"; do
            if [[ -d "$path/steamapps" && -f "$path/steamapps/libraryfolders.vdf" ]]; then
                STEAM_COMPAT_CLIENT_INSTALL_PATH="$path"
                break
            fi
        done

        if [[ -z "$STEAM_COMPAT_CLIENT_INSTALL_PATH" ]]; then
            echo "Steam installation not found in common directories."

                if $NO_PROMPT; then
                    echo "Error: --no-prompt specified, but Steam install path could not be auto-detected."
                    echo "Please provide a valid path using --steam-path <PATH>."
                    exit 1
                fi

            if [[ -n "$FORCE_CHOICE" ]]; then
                CUSTOM_STEAM_PATH="$FORCE_CHOICE"
            else
                read -rp "Please enter your Steam install path: " CUSTOM_STEAM_PATH
                if [[ ! -d "$CUSTOM_STEAM_PATH/steamapps" || ! -f "$CUSTOM_STEAM_PATH/steamapps/libraryfolders.vdf" ]]; then
                    echo "Error: '$CUSTOM_STEAM_PATH' does not contain a valid Steam installation."
                    exit 1
                fi
            fi
            STEAM_COMPAT_CLIENT_INSTALL_PATH="$CUSTOM_STEAM_PATH"
        fi
    fi
}

# Get all Steam library steamapps paths
find_steam_libraries() {
    local vdf="$STEAM_COMPAT_CLIENT_INSTALL_PATH/steamapps/libraryfolders.vdf"
    local libs=("$STEAM_COMPAT_CLIENT_INSTALL_PATH/steamapps")

    if [[ -f "$vdf" ]]; then
        while IFS= read -r libpath; do
            libs+=("$libpath/steamapps")
        done < <(grep -Po '"path"\s*"\K[^"]+' "$vdf")
    fi

    printf "%s\n" "${libs[@]}"
}

# Collect all installed AppIDs and game names into KEY::VALUE format
# Output: one per line, "appid::game name"
get_installed_games() {
    readarray -t libraries < <(find_steam_libraries)
    declare -A seen_appids=()

    for lib in "${libraries[@]}"; do
        local compat_dir="$lib/compatdata"
        if [[ -d "$compat_dir" ]]; then
            while IFS= read -r -d '' compat_path; do
                local appid="$(basename "$compat_path")"

                # Skip if already seen
                if [[ -n "${seen_appids[$appid]+x}" ]]; then
                    continue
                fi

                local game_name="Unknown"
                local acf_file="$lib/appmanifest_${appid}.acf"

                if [[ -f "$acf_file" ]]; then
                    game_name=$(grep -Po '"name"\s+"\K[^"]+' "$acf_file")
                fi

                echo "$appid::$game_name"
                seen_appids["$appid"]=1
            done < <(find "$compat_dir" -mindepth 1 -maxdepth 1 -type d -print0)
        fi
    done
}

list_installed_prefix_programs() {
    echo "Searching for installed Windows shortcuts inside Proton prefix for AppID [$APPID]..."

    if [[ -z "$APPID" ]]; then
        echo "Error: Please specify the AppID before using --search installed."
        exit 1
    fi

    local PREFIX_PATH="$STEAM_COMPAT_DATA_PATH/pfx/drive_c"
    local START_MENU_PATHS=(
        "$PREFIX_PATH/ProgramData/Microsoft/Windows/Start Menu/Programs"
        "$PREFIX_PATH/Users/steamuser/Start Menu/Programs"
    )

    found_any=false

    for path in "${START_MENU_PATHS[@]}"; do
        if [ -d "$path" ]; then
            while IFS= read -r -d '' lnkfile; do
                echo "$lnkfile"
                found_any=true
            done < <(find "$path" -type f -iname '*.lnk' -print0)
        fi
    done

    if ! $found_any; then
        echo "No .lnk shortcuts found in the Proton prefix for this AppID."
    else
        echo
        echo "You can launch any of these using:"
        echo "$0 --executable \"<PATH TO .lnk>\" $APPID"
    fi
}

# APPID_INPUT=""
PARSING_OPTIONS=true

# APPID/appName last, options first
while [[ $# -gt 0 ]]; do
    if $PARSE_EXTRA; then
        EXTRA_ARGS+=("$1")
        shift
        continue
    fi

    if $PARSING_OPTIONS; then
        case "$1" in
            --executable|-e)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    PROGRAM_PATH="$2"
                    shift 2
                else
                    echo "Error: '--executable' requires an executable path input."
                    exit 1
                fi
                ;;
            --proton|-p)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    CLI_PROTON_VERSION="$2"
                    shift 2
                else
                    echo "Error: '--proton' requires a proton folder name"
                    exit 1
                fi
                ;;
            --steam-path|-s)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    CLI_STEAM_PATH="$2"
                    shift 2
                else
                    echo "Error: '--steam-path' requires a path to a steam installation"
                    exit 1
                fi
                ;;
            --list|-l)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    LIST_MODE="$2"
                    shift 2
                else
                    echo "Error: '--list' requires a sub-option: 'proton', 'games', or 'appids'"
                    exit 1
                fi
                ;;
            --search)
                SEARCH_MODE=true
                shift
                ;;
            --debug|-d)
                DEBUG_MODE=true
                shift
                ;;
            --show-command)
                SHOW_COMMAND=true
                shift
                ;;
            --help|-h)
                SHOW_HELP=true
                shift
                ;;
            --license)
                SHOW_LICENSE=true
                shift
                ;;
            --yes|-y)
                AUTO_YES=true
                shift
                ;;
            --no-prompt)
                NO_PROMPT=true
                shift
                ;;
            --version|-v)
                echo "proton-shim version $VERSION"
                exit 0
                ;;
            --create-desktop)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    HAS_DESKTOP=true
                    CREATE_DESKTOP_NAME="$2"
                    shift 2
                else
                    echo "Error: '--create-desktop' requires a name argument."
                    exit 1
                fi
                ;;
            --icon)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    DESKTOP_ICON="$2"
                    shift 2
                else
                    echo "Error: '--icon' requires a icon path."
                    exit 1
                fi
                ;;
            --name)
                USE_NAME=true
                shift
                ;;
            --desktop-output)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    DESKTOP_OUTPUT="$2"  # values: "local" or "user"
                    shift 2
                else
                    echo "Error: '--desktop-output' requires a sub-option: 'local', or 'user'"
                    exit 1
                fi
                ;;
            --create-wrapper)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    HAS_WRAPPER=true
                    CREATE_WRAPPER_NAME="$2"
                    shift 2
                else
                    echo "Error: '--create-wrapper' requires a name argument."
                    exit 1
                fi
                ;;
            --wrapper-output)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    WRAPPER_OUTPUT="$2"  # values: "local" or "global"
                    shift 2
                else
                    echo "Error: '--wrapper-output' requires a sub-option: 'local', or 'global'"
                    exit 1
                fi
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --clear)
                RESET_CONFIGS=true
                shift
                ;;
            --fork)
                FORK_EXECUTABLE=true
                shift
                ;;
            --fork64)
                FORK_EXECUTABLE=true
                WINE_64=true
                shift
                ;;
            --use-esync)
                USE_ESYNC=true
                shift
                ;;
            --use-fsync)
                USE_FSYNC=true
                shift
                ;;
            --use-proton-no-esync)
                USE_PROTON_NO_ESYNC=true
                shift
                ;;
            --use-proton-no-fsync)
                USE_PROTON_NO_FSYNC=true
                shift
                ;;
            --)
                PARSE_EXTRA=true
                shift
                ;;
            *)
                POSITIONAL_ARGS+=("$1")
                shift
                ;;
        esac
    else
        # Should never reach here; handled by PARSE_EXTRA block
        echo "Internal parsing error: unhandled state after '--'"
        exit 1
    fi
done

if $RESET_CONFIGS; then
    echo "clearing persistent config files"
    if [[ -f "$CONFIG_FILE_STEAM" ]]; then
        rm -f "$CONFIG_FILE_STEAM"
    fi

    echo "finished clearing config files, exiting..."
    exit 0
fi

load_config

# ==== PREPARE APPID ====
# Join and trim the positional input into one string
RAW_NAME="$(printf '%s ' "${POSITIONAL_ARGS[@]}" | sed 's/[[:space:]]*$//')"

# If the result is empty or only whitespace, treat as wildcard
if [[ -z "${RAW_NAME//[[:space:]]/}" ]]; then
    APPID=""
elif [[ "$RAW_NAME" =~ ^[0-9]+$ ]]; then
    APPID="$RAW_NAME"
else
    # APPID="$(resolve_game_name "$RAW_NAME")" || exit 1
    APPID="$RAW_NAME"
fi


if $SHOW_HELP; then
    echo "Usage: $0 [OPTIONS] [APPID|name] [-- EXECUTABLE_ARGS...]

Launch Windows executables using Proton, targeting a specific Steam AppID.

Positional Arguments:
  APPID                          Steam Application ID to use for compatdata.
                                 Alternatively, provide part of the application name.
                                 Matches are case-insensitive and each word is matched 
                                 separately (e.g. \"warh dark\" could match Wahammer 40,000: Darktide).
                                 --name forces the APPID to be looked up by game name.

Executable Options:
  --executable, -e <PATH>        Path to the executable to run.
                                 If not set, you'll be prompted to pick one from the current directory.
  --proton, -p <FOLDER>          Proton version folder name (e.g. 'Proton 9.0 (Beta)')
  --steam-path, -s <PATH>        Override the Steam installation path
  --list, -l <proton|games>      Lists available Proton versions or detected Steam AppIDs with existing compatdata and exit.
  --search                       List installed Windows shortcuts (.lnk) inside the Proton prefix for the specified APPID, then exit.

Desktop Integration:
  --create-desktop <NAME>        Generate a .desktop shortcut with the given name
  --desktop-output <local|user>  Where to place the .desktop file (default: user):
                                   'local' = current directory
                                   'user'  = ~/.local/bin/ (visible in your start menu)
  --icon <PATH>                  Icon to use in the .desktop file (e.g. PNG or .svg path, or just 'steam')
                                 Defaults to steam if not specified

Wrapper Generation:
  --create-wrapper <NAME>        Generate a launchable wrapper .sh script with the given name
  --wrapper-output <local|global>  Where to place the .desktop file (default: local):
                                   'local' = current directory
                                   'global'  = /usr/local/bin (executable anywhere in terminal, calls sudo automatically)

Behavior Flags:
  --fork                         Run the program in the same wineserver as the game (needed for memory access tools).
  --fork64                       Run the program under wine64, in the same wineserver as the game
  --use-esync                    Adds WINEESYNC=1 for forks, enabling esync if the environment supports it.
  --use-fsync                    Adds WINEFSYNC=1 for forks, enabling fsync if the environment supports it.
  --use-proton-no-esync          Adds PROTON_NO_ESYNC=1 for Proton, disabling esync.
  --use-proton-no-fsync          Adds PROTON_NO_FSYNC=1 for Proton, disabling fsync.
  --debug, -d                    Enables PROTON_LOG and PROTON_DUMP_DEBUG_COMMANDS for troubleshooting
  --show-command                 Print the final Proton command before execution
  --dry-run                      Skips execution. Still creates .desktop files if requested.
  --yes, -y                      Automatically confirm Y/N prompts
  --no-prompt                    Disable all interactive prompts (implies --yes)
  --name                         Force the positional argument to be treated as a name for lookup, even if numeric.
  --clear                       Clears cached persistent config files and exits.


General Info:
  --help, -h                     Show this help message and exit
  --version, -v                  Print the proton-shim version and exit
  --license                      Print the MIT License and exit

Additional Arguments:
  --                             Everything after '--' is passed directly as additional arguments
                                 to the launched executable under Proton.

Persistence files are located at:
  $CONFIG_DIR

Example:
  $0 --executable tool.exe --proton \"Proton 9.0\" 1017180 -- arg1 \"arg with spaces\"

Notes:
- Use --fork/--fork64 to run memory scanners/debug tools that require access to the game's process memory.
- Use --use-esync/--use-fsync only if your current Proton/game session is running with esync/fsync enabled.
- When not using --fork, --use-proton-no-esync/--use-proton-no-fsync disable esync/fsync when running under Proton if needed for compatibility."
    exit 0
fi

if $SHOW_LICENSE; then
    cat <<EOF
MIT License

Copyright (c) 2025 Phillip MacNaughton "Wisher"

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
    exit 0
fi

# ==== LIST COMMAND ====
if [[ -n "$LIST_MODE" ]]; then
    find_steam_path
    case "$LIST_MODE" in
        proton)
            configure_proton
            echo "Detected Proton versions:"
            for i in "${!PROTON_DISPLAY_NAMES[@]}"; do
                echo "  [$i] ${PROTON_DISPLAY_NAMES[$i]}"
            done
            exit 0
            ;;
        games|appids)
            echo "Detected compatdata prefixes (AppIDs):"
            FOUND=0

            while IFS= read -r entry; do
                IFS="::" read -r appid name <<< "$entry"
                name="${entry#*::}"
                printf "[%s]%*s[%s]\n" "$appid" $((8 + 10 - ${#appid})) "" "$name"
                FOUND=1
            done < <(get_installed_games)

            if [[ $FOUND -eq 0 ]]; then
                echo "No compatdata folders found."
            fi
            exit 0
            ;;
        *)
            echo "Unknown --list option: $LIST_MODE"
            echo "Use '--list proton', '--list games', or '--list appids'"
            exit 1
            ;;
    esac
    exit 0
fi

# ==== Validate Desktop-File Name ====
if $HAS_DESKTOP; then
    if [[ -z "${CREATE_DESKTOP_NAME// /}" ]]; then
        echo "Error: No desktop file name provided while --create-desktop was specified. Exiting..."
        exit 1
    fi
fi

# ==== Validate Wrapper-File Name ====
if $HAS_WRAPPER; then
    if [[ -z "${CREATE_WRAPPER_NAME// /}" ]]; then
        echo "Error: No wrapper file name provided while --create-wrapper was specified. Exiting..."
        exit 1
    fi
fi

# ==== Validate APPID ====
find_steam_path  # Ensure $STEAM_COMPAT_CLIENT_INSTALL_PATH is set
INPUT="$APPID"

MATCHING_GAMES=()

# Get list of installed games: lines of format "appid::name"
while IFS= read -r entry; do
    appid="${entry%%::*}"
    name="${entry#*::}"

    if ! [[ "$appid" =~ ^[0-9]+$ ]]; then
        continue
    fi

    # If input is numeric, try exact AppID match
    if [[ "$INPUT" =~ ^[0-9]+$ && "$appid" == "$INPUT" ]]; then
        MATCHING_GAMES=("$appid::$name")
        break
    fi

    # Otherwise, check for fuzzy name match
    SEARCH_WORDS=()

    # Lowercase and normalize input
    read -ra SEARCH_WORDS <<< "$(tr '[:upper:]' '[:lower:]' <<< "$INPUT")"

    # Lowercase game name for comparison
    NAME_LOWER=$(tr '[:upper:]' '[:lower:]' <<< "$name")

    MATCH=true
    for word in "${SEARCH_WORDS[@]}"; do
        if [[ "$NAME_LOWER" != *"$word"* ]]; then
            MATCH=false
            break
        fi
    done

    if $MATCH; then
        MATCHING_GAMES+=("$appid::$name")
    fi
done < <(get_installed_games)

# === Handle matching result ===
if [[ "${#MATCHING_GAMES[@]}" -eq 0 ]]; then
    echo "No matching AppID or game name found: $INPUT"
    exit 1
elif [[ "${#MATCHING_GAMES[@]}" -eq 1 ]]; then
    appid="${MATCHING_GAMES[0]%%::*}"
    name="${MATCHING_GAMES[0]#*::}"
    echo "Match found: [$appid]::[$name]"

    # Check if input was numeric, matches the appid, and --name was not used
    if [[ "$INPUT" =~ ^[0-9]+$ && "$appid" == "$INPUT" && "$USE_NAME" != true ]]; then
        APPID="$appid"
        echo "Auto-accepting numeric AppID [$APPID] without prompt."
    elif $AUTO_YES || $NO_PROMPT; then
        APPID="$appid"
    else
        if [[ -n "$FORCE_CHOICE" ]]; then
            appid="$FORCE_CHOICE"
        else
            read -rp "Use this AppID? [Y/n] " confirm
            if [[ "$confirm" =~ ^[Nn]$ ]]; then
                echo "Aborted."
                exit 1
            fi
        fi

        APPID="$appid"
    fi

    echo "Using AppID [$APPID] for '$name'"
else
    echo "Multiple matches found for '$INPUT':"

    # If input is numeric and USE_NAME is false, auto-select the match with exact AppID if found
    if ! $USE_NAME && [[ "$INPUT" =~ ^[0-9]+$ ]]; then
        for match in "${MATCHING_GAMES[@]}"; do
            match_appid="${match%%::*}"
            match_name="${match#*::}"
            if [[ "$match_appid" == "$INPUT" ]]; then
                APPID="$match_appid"
                echo "Auto-selected AppID [$APPID] for '$match_name' due to exact AppID match."
                return 0
            fi
        done
    fi

    # Otherwise, proceed with user prompt as normal
    if $NO_PROMPT; then
        echo "Error: Multiple matches and --no-prompt set. Try AppID to be more specific."
        exit 1
    fi

    for i in "${!MATCHING_GAMES[@]}"; do
        appid="${MATCHING_GAMES[$i]%%::*}"
        name="${MATCHING_GAMES[$i]#*::}"
        printf "  [%d] [%s]::[%s]\n" "$i" "$appid" "$name"
    done

    if [[ -n "$FORCE_CHOICE" ]]; then
        choice="$FORCE_CHOICE"
    else
        read -rp "Select a game [0-$((${#MATCHING_GAMES[@]}-1))]: " choice
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 0 || choice >= ${#MATCHING_GAMES[@]} )); then
            echo "Invalid choice."
            exit 1
        fi
    fi

    IFS="::" read -r appid name <<< "${MATCHING_GAMES[$choice]}"
    APPID="$appid"
    echo "Using AppID [$APPID] for '$name'"
fi

if ! [[ "$APPID" =~ ^[0-9]+$ ]]; then
    echo "Error: Failed to resolve a valid numeric AppID."
    exit 1
fi

if [[ -z "$APPID" ]]; then
    echo "Error: Missing required APPID (Steam Application ID)."
    echo "Usage: $0 [APPID] [OPTIONS]"
    echo "       Or use --help, --license, or --list <proton|games> for other actions."
    exit 1
fi

# ==== DETECT/RESOLVE STEAM INSTALL PATH ====
find_steam_path

mkdir -p "$CONFIG_DIR"
echo "STEAM_COMPAT_CLIENT_INSTALL_PATH=\"$STEAM_COMPAT_CLIENT_INSTALL_PATH\"" > "$CONFIG_FILE_STEAM"

# ==== CHECK PROGRAM FILE ====
if ! $SEARCH_MODE; then

    # If no PROGRAM_PATH provided, prompt user to choose from executables in the current directory
    if [[ -z "$PROGRAM_PATH" ]]; then
        # Find valid PE32, .bat, .cmd, .ps1, or .msi files in the current directory
        mapfile -t EXECUTABLE_FILES < <(
            find . -maxdepth 1 -type f | while read -r file; do
                mime=$(LC_ALL=C file -b "$file")
                ext="${file##*.}"
                ext="${ext,,}"  # Lowercase the extension

                if echo "$mime" | grep -qE 'PE32(\+)? executable|MS Windows'; then
                    echo "$file"
                elif [[ "$ext" == "bat" || "$ext" == "cmd" || "$ext" == "ps1" || "$ext" == "msi" ]]; then
                    echo "$file"
                fi
            done | sort
        )

        if [[ ${#EXECUTABLE_FILES[@]} -eq 0 ]]; then
            echo "No executable scripts or files found in the current directory. Use --executable <PATH> to specify a file."
            exit 1
        elif [[ ${#EXECUTABLE_FILES[@]} -eq 1 ]]; then
            PROGRAM_PATH="${EXECUTABLE_FILES[0]}"
            echo "Using detected file: $PROGRAM_PATH"
        else
            if $NO_PROMPT; then
                echo "Error: Multiple executable candidates found and --no-prompt is set. Use --executable to specify one."
                exit 1
            else
                echo "Select a file to run:"
                for i in "${!EXECUTABLE_FILES[@]}"; do
                    printf "  [%d] %s\n" "$i" "${EXECUTABLE_FILES[$i]}"
                done

                if [[ -n "$FORCE_CHOICE" ]]; then
                    executable_choice="$FORCE_CHOICE"
                else
                    read -rp "Choice [0-$((${#EXECUTABLE_FILES[@]} - 1))]: " executable_choice
                    if [[ ! "$executable_choice" =~ ^[0-9]+$ ]] || (( executable_choice < 0 || executable_choice >= ${#EXECUTABLE_FILES[@]} )); then
                        echo "Invalid selection."
                        exit 1
                    fi
                fi

                PROGRAM_PATH="${EXECUTABLE_FILES[$executable_choice]}"
                echo "Using selected file: $PROGRAM_PATH"
            fi
        fi
    fi

    # ==== VALIDATE EXECUTABLE ====
    if [[ ! -f "$PROGRAM_PATH" ]]; then
        echo "Error: File not found at: $PROGRAM_PATH"
        exit 1
    fi

    FILE_TYPE=$(LC_ALL=C file -b "$PROGRAM_PATH")

    # Extract file extension
    EXTENSION="${PROGRAM_PATH##*.}"
    EXTENSION_LOWER=$(echo "$EXTENSION" | tr 'A-Z' 'a-z')

    if ! grep -qE "PE32(\+)? executable|MS Windows" <<< "$FILE_TYPE" && \
    [[ "$EXTENSION_LOWER" != "bat" && \
        "$EXTENSION_LOWER" != "cmd" && \
        "$EXTENSION_LOWER" != "ps1" && \
        "$EXTENSION_LOWER" != "msi" ]]; then
        echo "Error: '$PROGRAM_PATH' is not a recognized Windows executable or script."
        echo "This tool only supports Windows executables (.exe, .bat, .cmd, .ps1, .msi, etc.) for Proton launching."
        exit 1
    fi

    if [[ ! -x "$PROGRAM_PATH" ]]; then
        if $AUTO_YES || $NO_PROMPT; then
            echo "Warning: '$PROGRAM_PATH' is not marked as executable. Automatically attempting to fix due to --yes flag."
            chmod +x "$PROGRAM_PATH" || {
                echo "Failed to chmod the file."
                exit 1
            }
        else
            echo "Warning: '$PROGRAM_PATH' is not marked as executable. Attempt to fix? [Y/n]"
            if [[ -n "$FORCE_CHOICE" ]]; then
                answer="$FORCE_CHOICE"
            else
                read -r answer
            fi
            
            if [[ "$answer" =~ ^[Yy]$ || -z "$answer" ]]; then
                chmod +x "$PROGRAM_PATH" || {
                    echo "Failed to chmod the file."
                    exit 1
                }
            else
                echo "Aborting."
                exit 1
            fi
        fi
    fi

    if [[ "$PROGRAM_PATH" != /* ]]; then
    PROGRAM_PATH="$PWD/$PROGRAM_PATH"
    fi

fi

# ==== SELECT PROTON VERSION ====
if ! $SEARCH_MODE; then
    configure_proton
fi

# ==== FUNCTION TO FIND App ====
find_steam_compat_path() {
    local appid="$1"
    local vdf_path="$2/steamapps/libraryfolders.vdf"
    local libraries=()

    # Include default library first
    libraries+=("$2/steamapps")

    if [ ! -f "$vdf_path" ]; then
        echo "Error: Cannot find $vdf_path"
        return 1
    fi

    # Extract additional library paths
    while IFS= read -r libpath; do
        libraries+=("$libpath/steamapps")
    done < <(grep -Po '"path"\s*"\K[^"]+' "$vdf_path")

    # Check each for compatdata/<APPID>
    for lib in "${libraries[@]}"; do
        local compat_path="$lib/compatdata/$appid"
        if [ -d "$compat_path" ]; then
            echo "$compat_path"
            return 0
        fi
    done

    echo "Error: compatdata for AppID $appid not found in any Steam library." >&2
    return 1
}

# ==== DERIVED PATHS ====
STEAM_COMPAT_DATA_PATH="$(find_steam_compat_path "$APPID" "$STEAM_COMPAT_CLIENT_INSTALL_PATH")" || exit 1
WINEPREFIX="$STEAM_COMPAT_DATA_PATH/pfx"
PROTON_WINE=""
if $FORK_EXECUTABLE; then
    # Determine Proton wine binary
    if $WINE_64; then
        PROTON_WINE="$PROTON_DIR/files/bin/wine64"
    else
        PROTON_WINE="$PROTON_DIR/files/bin/wine"
    fi
fi
WORKDIR_WIN=""
PROGRAM_PATH_WIN=""


# ==== SEARCH COMMAND ====
if $SEARCH_MODE; then
    list_installed_prefix_programs
    exit 0
fi

# ==== LAUNCH ====
export STEAM_COMPAT_CLIENT_INSTALL_PATH
export STEAM_COMPAT_DATA_PATH

if $DEBUG_MODE; then
    export PROTON_LOG=1
    export PROTON_DUMP_DEBUG_COMMANDS=1
else
    export PROTON_LOG=0
    export PROTON_DUMP_DEBUG_COMMANDS=0
fi

parse_lnk_file_bash() {
    local lnk_file="$1"

    # Ensure .lnk is inside a compatdata prefix for reliable path translation
    if ! [[ "$lnk_file" =~ steamapps/compatdata/[0-9]+/pfx/drive_c/.* ]]; then
        echo "Error: .lnk file is not inside a Proton compatdata prefix. Cannot safely translate paths."
        echo "Please place or create your .lnk inside the Proton prefix if you wish to use it with proton-shim."
        exit 1
    fi

    # Extract readable Windows paths from binary
    # This will dump potential readable strings from the binary that match C:\... and pick the first as target
    local extracted_paths
    extracted_paths=$(strings -el "$lnk_file" | sort | uniq)

    local target_path=""
    local work_dir=""
    local exe_candidate=""

    while IFS= read -r line; do
        line="${line%\"}"
        line="${line#\"}"

        if [[ -z "$exe_candidate" && "$line" =~ \.exe$ ]]; then
            exe_candidate="$line"
        fi
        if [[ -z "$work_dir" && "$line" =~ [a-zA-Z] && "$line" =~ ^\"?C:\\ ]]; then
            work_dir="$line"
        fi
    done <<< "$extracted_paths"

    if [[ -z "$target_path" ]]; then
        if [[ -n "$exe_candidate" && -n "$work_dir" ]]; then
            target_path="${work_dir}\\${exe_candidate}"
            echo "Fallback: Composing target_path as $target_path"
        else
            echo "Error: Could not determine target executable from $lnk_file"
            exit 1
        fi
    fi

    if [[ -z "$work_dir" ]]; then
        # Fallback: use directory of the target_path
        work_dir="${target_path%\\*}"
    fi

    echo "Detected target: $target_path"
    echo "Detected working directory: $work_dir"

    # Convert Windows paths to Proton prefix paths
    target_path_unix="$WINEPREFIX/drive_c/${target_path#C:\\}"
    target_path_unix="${target_path_unix//\\//}"

    work_dir_unix="$WINEPREFIX/drive_c/${work_dir#C:\\}"
    work_dir_unix="${work_dir_unix//\\//}"

    PROGRAM_PATH="$target_path_unix"
    PROGRAM_WORKDIR="$work_dir_unix"
}

if [[ "$PROGRAM_PATH" == *.lnk ]]; then
    parse_lnk_file_bash "$PROGRAM_PATH"
    WORKDIR_WIN="Z:$(echo "$PROGRAM_WORKDIR" | sed 's|/|\\|g')"
    # PROGRAM_PATH_WIN="Z:$(echo "$PROGRAM_PATH" | sed 's|/|\\|g')"
fi

# ==== DETECT SCRIPT TYPE AND WRAP IF NEEDED ====
ESCAPED_PROGRAM_PATH="$(printf '%q' "$(readlink -f "$PROGRAM_PATH")")"

EXTRA_ARGS_STRING=""
if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    for arg in "${EXTRA_ARGS[@]}"; do
        EXTRA_ARGS_STRING+=" $(printf '%q' "$arg")"
    done
    # Trim leading space
    EXTRA_ARGS_STRING="${EXTRA_ARGS_STRING# }"
fi

CMD_LINE=""
SYNC_ENV=""

if $FORK_EXECUTABLE; then

    $USE_ESYNC && SYNC_ENV="$SYNC_ENV WINEESYNC=1"
    $USE_FSYNC && SYNC_ENV="$SYNC_ENV WINEFSYNC=1"
    
    # if workdir_win not set yet, ie not a lnk file
    if [[ -z "$WORKDIR_WIN" ]]; then
        WORKDIR_WIN="Z:$(dirname "$PROGRAM_PATH" | sed 's|/|\\|g')"
    fi

    WINDOWS_PATH_BASENAME="$(basename "$PROGRAM_PATH")"

    # if programpath_win not set yet, ie not a lnk file
    # if [[ -z "$PROGRAM_PATH_WIN" ]]; then
        # WINDOWS_PATH="Z:$(echo "$PROGRAM_PATH" | sed 's|/|\\|g')"
        case "$EXTENSION_LOWER" in
            bat|cmd)
                PROGRAM_PATH_WIN="cmd.exe /c \"$WINDOWS_PATH_BASENAME\""
                ;;
            ps1)
                PROGRAM_PATH_WIN="powershell.exe -File -ExecutionPolicy Bypass \"$WINDOWS_PATH_BASENAME\""
                ;;
            msi)
                PROGRAM_PATH_WIN="msiexec /i \"$WINDOWS_PATH_BASENAME\""
                ;;
            *)
                PROGRAM_PATH_WIN="$WINDOWS_PATH_BASENAME"
                ;;
        esac
    # fi

    CMD_LINE="$SYNC_ENV WINEPREFIX=\"$WINEPREFIX\" \"$PROTON_WINE\" start /d \"$WORKDIR_WIN\" \"$PROGRAM_PATH_WIN\" $EXTRA_ARGS_STRING"
else

    $USE_PROTON_NO_ESYNC && SYNC_ENV="$SYNC_ENV PROTON_NO_ESYNC=1"
    $USE_PROTON_NO_FSYNC && SYNC_ENV="$SYNC_ENV PROTON_NO_FSYNC=1"
    case "$EXTENSION_LOWER" in
        bat|cmd)
            CMD_LINE="$SYNC_ENV \"$PROTON_PATH\" run cmd.exe /c \"$(basename "$PROGRAM_PATH $EXTRA_ARGS_STRING")\""
            ;;
        ps1)
            CMD_LINE="$SYNC_ENV \"$PROTON_PATH\" run powershell.exe -File -ExecutionPolicy Bypass \"$(basename "$PROGRAM_PATH $EXTRA_ARGS_STRING")\""
            ;;
        msi)
            CMD_LINE="$SYNC_ENV \"$PROTON_PATH\" run msiexec /i \"$(basename "$PROGRAM_PATH $EXTRA_ARGS_STRING")\""
            ;;
        *)
            CMD_LINE="$SYNC_ENV \"$PROTON_PATH\" run $ESCAPED_PROGRAM_PATH $EXTRA_ARGS_STRING"
            ;;
    esac
fi

NEEDS_CD=false
case "$EXTENSION_LOWER" in
    bat|cmd|ps1)
        NEEDS_CD=true
        ;;
esac

if $NEEDS_CD; then
    EXEC_LINE="cd \"$(dirname "$PROGRAM_PATH")\" && $CMD_LINE"
else
    EXEC_LINE="$CMD_LINE"
fi

DESKTOP_EXEC_LINE="env STEAM_COMPAT_DATA_PATH=\"${STEAM_COMPAT_DATA_PATH}\" STEAM_COMPAT_CLIENT_INSTALL_PATH=\"${STEAM_COMPAT_CLIENT_INSTALL_PATH}\" bash -c '${EXEC_LINE}'"

if $SHOW_COMMAND; then
    echo "Final Proton command:"
    echo "$EXEC_LINE"
fi

# ==== CREATE DESKTOP FILE ====
if [[ -n "$CREATE_DESKTOP_NAME" ]]; then
    DESKTOP_NAME="$CREATE_DESKTOP_NAME"
    DESKTOP_NAME_FIXED="${DESKTOP_NAME// /_}"

    # Determine target directory
    if [[ "$DESKTOP_OUTPUT" == "local" ]]; then
        DESKTOP_FILE="$PWD/${DESKTOP_NAME_FIXED}.desktop"
        DESKTOP_FILE_SCRIPT="$PWD/${DESKTOP_NAME_FIXED}.sh"
    elif [[ "$DESKTOP_OUTPUT" == "user" ]]; then
        DESKTOP_FILE="$HOME/.local/share/applications/${DESKTOP_NAME_FIXED}.desktop"
        DESKTOP_FILE_SCRIPT="$HOME/.local/share/proton-shim/desktop-wrappers/${DESKTOP_NAME_FIXED}.sh"
    else
        echo "Invalid --desktop-output argument, must be either 'local' or 'user'"
        exit 1
    fi

    # Use icon if provided, or fallback
    ICON_PATH="${DESKTOP_ICON:-steam}"

    if [[ "$ICON_PATH" != "steam" && -n "$ICON_PATH" ]]; then
        if [ -f "$ICON_PATH" ]; then
            ICON_PATH="$(readlink -f "$ICON_PATH")"
        else
            echo "Warning: Icon '$ICON_PATH' not found, falling back to 'steam' icon."
            ICON_PATH="steam"
        fi
    fi
    
    if [[ -f "$DESKTOP_FILE" ]]; then
        if ! $AUTO_YES && ! $NO_PROMPT; then
            if [[ -n "$FORCE_CHOICE" ]]; then
                confirm="$FORCE_CHOICE"
            else
                read -rp "Desktop file already exists at '$DESKTOP_FILE'. Overwrite? [y/N]: " confirm
            fi
            
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "Aborted desktop file creation."
                exit 0
            fi
        fi
        echo "Overwriting existing desktop file at '$DESKTOP_FILE'..."
    fi

    mkdir -p "$(dirname "$DESKTOP_FILE")" || {
        echo "Error: Failed to create directory for $DESKTOP_FILE"
        exit 1
    }

    if [[ "$DESKTOP_OUTPUT" == "user" ]]; then
        mkdir -p "$HOME/.local/share/proton-shim/desktop-wrappers" || {
            echo "Error: Failed to create script directory for desktop wrappers."
            exit 1
        }
    fi

        # Create the .desktop file
    if ! cat > "$DESKTOP_FILE_SCRIPT" <<EOF
#!/bin/bash
exec $DESKTOP_EXEC_LINE
EOF
then
    echo "Error: Failed to write .sh file at $DESKTOP_FILE_SCRIPT"
    exit 1
fi

if ! chmod +x "$DESKTOP_FILE_SCRIPT" 2>/dev/null; then
    if command -v sudo >/dev/null 2>&1; then
        echo "Retrying chmod with sudo..."
        if ! sudo chmod +x "$DESKTOP_FILE_SCRIPT"; then
            echo "Warning: sudo chmod failed; skipping marking as executable."
        fi
    else
        echo "Warning: Failed to mark $DESKTOP_FILE_SCRIPT as executable and 'sudo' is unavailable."
        echo "You may need to 'chmod +x \"$DESKTOP_FILE_SCRIPT\"' manually."
    fi
fi

    # Create the .desktop file
    if ! cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=$DESKTOP_NAME
Comment=Launch $DESKTOP_NAME with ProtonShim
Exec="$DESKTOP_FILE_SCRIPT"
Icon=$ICON_PATH
Terminal=false
Type=Application
Categories=Game;
StartupNotify=true
EOF
then
    echo "Error: Failed to write .desktop file at $DESKTOP_FILE"
    exit 1
fi

    if [ ! -s "$DESKTOP_FILE" ]; then
        echo "Error: .desktop file at '$DESKTOP_FILE' is empty after generation."
        exit 1
    fi  

    chmod +x "$DESKTOP_FILE"
    echo "Desktop shortcut created at: \"$DESKTOP_FILE\""
fi

# ==== CREATE WRAPPER SCRIPT ====
if [[ -n "$CREATE_WRAPPER_NAME" ]]; then
    WRAPPER_NAME="${CREATE_WRAPPER_NAME// /_}"
    if [[ "$WRAPPER_OUTPUT" == "local" ]]; then
        WRAPPER_FILE="$(pwd)/${WRAPPER_NAME}.sh"
    elif [[ "$WRAPPER_OUTPUT" == "global" ]]; then
        WRAPPER_FILE="/usr/local/bin/${WRAPPER_NAME}"
        mkdir -p "$HOME/.local/bin"
    else
        echo "Invalid --wrapper-output argument, must be either 'local' or 'global'"
        exit 1
    fi

    if [[ -f "$WRAPPER_FILE" ]]; then
        if ! $AUTO_YES && ! $NO_PROMPT; then
            if [[ -n "$FORCE_CHOICE" ]]; then
                confirm="$FORCE_CHOICE"
            else
                read -rp "Wrapper script already exists at '$WRAPPER_FILE'. Overwrite? [y/N]: " confirm
            fi
            
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "Aborted wrapper creation."
                exit 0
            fi
            echo "Overwriting existing wrapper script at '$WRAPPER_FILE'..."
        else
            echo "Overwriting existing wrapper script at '$WRAPPER_FILE'..."
        fi
    fi

    mkdir -p "$(dirname "$WRAPPER_FILE")" || {
        echo "Error: Failed to create directory for $WRAPPER_FILE"
        exit 1
    }

    # Create the wrapper script
    TMP_WRAPPER="$(mktemp)"
    if ! cat > "$TMP_WRAPPER" <<EOF
#!/bin/bash
export STEAM_COMPAT_DATA_PATH="${STEAM_COMPAT_DATA_PATH}"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH}"
${EXEC_LINE}
EOF
then
    echo "Error: Failed to write wrapper script at $TMP_WRAPPER"
    exit 1
fi

    # Move with appropriate permissions
    if [[ "$WRAPPER_OUTPUT" == "global" ]]; then
        sudo mv "$TMP_WRAPPER" "$WRAPPER_FILE"
        sudo chmod +x "$WRAPPER_FILE"
    else
        mv "$TMP_WRAPPER" "$WRAPPER_FILE"
        chmod u+x "$WRAPPER_FILE"
    fi

    if [ ! -s "$WRAPPER_FILE" ]; then
        echo "Error: wrapper script at '$WRAPPER_FILE' is empty after generation."
        exit 1
    fi  

    echo "Wrapper script created at: \"$WRAPPER_FILE\""
    if [[ "$WRAPPER_OUTPUT" == "global" ]]; then
        echo "can be called globally with: $WRAPPER_NAME"
        if ! echo "$PATH" | grep -q "/usr/local/bin"; then
            echo "Note: /usr/local/bin is not in your PATH. Add it to call '$WRAPPER_NAME' globally."
        fi
    else 
        echo "can be called with: $WRAPPER_FILE"
    fi
fi

# Exit cleanly if dry run
if $DRY_RUN; then
    exit 0
fi

# Execute command
eval "$EXEC_LINE"