#!/usr/bin/env bash
# Interactive release manager for the Tight 5 FIGHT! deploys.
#
#     ./helper-tools/tight5-release-manager.sh
#
# It is a front end for the three deploy scripts, nothing more:
#
#   Deploy Games     GODOT=<binary> ./deployScriptPROD.sh <gameId> [go]
#   Deploy Website   ./deployScriptPRODWEB.sh [go]
#   Deploy Backend   ./deployScriptPRODBE.sh live [go]
#
# Every one of them asks Dry Run or LIVE Deploy before it does anything, and
# the cursor starts on Dry Run.
#
# ALL SETTINGS LIVE IN helper-tools/tight5-release-manager.conf — the Godot
# binary, the project path, and the three scripts with their arguments. There
# is no fallback and nothing is auto-created: if that file is missing the
# script stops and tells you what to put in it. Nothing is configured here.
#
# tight5fight_base_path in that file names the project it drives — every
# command runs from there — so this script does not have to live inside the
# checkout it deploys.
#
# The game list is read from games/*/ at startup — a new edition appears here
# the moment it has a game.json and a real deploy.json, no editing this file.
#
# Every screen navigates the same way: arrow keys (or j/k) move, ENTER selects,
# q backs out. Menus also take their number keys as shortcuts.
set -uo pipefail

# Where this script lives, used ONLY to find its settings file.
SCRIPT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONF_FILE="$SCRIPT_ROOT/helper-tools/tight5-release-manager.conf"

# ------------------------------------------------------------------ colors
if [[ -t 1 ]] && command -v tput >/dev/null && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
    BOLD=$(tput bold); DIM=$(tput dim); RESET=$(tput sgr0)
    GOLD=$(tput setaf 3); PINK=$(tput setaf 5); GREEN=$(tput setaf 2); RED=$(tput setaf 1)
else
    BOLD=""; DIM=""; RESET=""; GOLD=""; PINK=""; GREEN=""; RED=""
fi

cursor_hide() { printf '\e[?25l'; }
cursor_show() { printf '\e[?25h'; }
trap cursor_show EXIT INT TERM

# ------------------------------------------------------------------ config
# Flat "key: value" YAML. The file is never sourced or eval'd — it is data,
# read one key at a time, so a typo in it can never execute anything.

if [[ ! -f "$CONF_FILE" ]]; then
    cat >&2 <<MISSING
Settings file not found:

  $CONF_FILE

This script configures nothing itself — create that file with at least:

  tight5fight_base_path: /path/to/open-mic-night
  godot: /path/to/Godot_v4.4_binary
  deploy_script: deployScriptPROD.sh
  web_deploy_script: deployScriptPRODWEB.sh
  backend_deploy_script: deployScriptPRODBE.sh
MISSING
    exit 1
fi

# conf_get <key> [default]
conf_get() {
    local key="$1" default="${2-}" val=""
    val=$(sed -n "s/^[[:space:]]*${key}[[:space:]]*:[[:space:]]*//p" "$CONF_FILE" | tail -1)
    val=$(printf '%s' "$val" | sed -e 's/[[:space:]]\+#.*$//' -e 's/[[:space:]]*$//')
    val=${val#\"}; val=${val%\"}
    val=${val#\'}; val=${val%\'}
    printf '%s' "${val:-$default}"
}

# conf_path <value> — an in-repo path from the settings file. Absolute if it
# exists as written; otherwise resolved against tight5fight_base_path, with a
# leading "/" or "./" ignored — so "deployScriptPROD.sh", "./deployScriptPROD.sh"
# and "/deployScriptPROD.sh" all name the same file at the top of the project.
conf_path() {
    local v="$1"
    [[ -z "$v" ]] && return
    if [[ "$v" == /* && -e "$v" ]]; then printf '%s' "$v"; return; fi
    v=${v#./}; v=${v#/}
    printf '%s/%s' "$BASE" "$v"
}

conf_die() { printf '%s\n' "$1" >&2; printf 'Fix it in %s\n' "$CONF_FILE" >&2; exit 1; }

# Everything below runs from the project the settings file points at.
BASE=$(conf_get tight5fight_base_path)
BASE=${BASE%/}
[[ -n "$BASE"      ]] || conf_die "tight5fight_base_path is not set."
[[ -d "$BASE"      ]] || conf_die "tight5fight_base_path is not a directory: $BASE"
[[ -d "$BASE/games" ]] || conf_die "tight5fight_base_path has no games/ folder, so it is not a Tight 5 checkout: $BASE"
cd "$BASE" || exit 1

GODOT_BIN=$(conf_get godot)

# The three deploy scripts, and the arguments that mean "dry run" and "for
# real" to each — they do NOT agree with each other, which is exactly why they
# are settings and not assumptions. The game script also takes the game id,
# which is prepended to these.
GAME_SCRIPT=$(conf_path "$(conf_get deploy_script deployScriptPROD.sh)")
GAME_ARGS_DRY=$(conf_get game_deploy_args_dry "")
GAME_ARGS_LIVE=$(conf_get game_deploy_args_live "go")

WEB_SCRIPT=$(conf_path "$(conf_get web_deploy_script deployScriptPRODWEB.sh)")
WEB_ARGS_DRY=$(conf_get web_deploy_args_dry "")
WEB_ARGS_LIVE=$(conf_get web_deploy_args_live "go")

BE_SCRIPT=$(conf_path "$(conf_get backend_deploy_script deployScriptPRODBE.sh)")
BE_ARGS_DRY=$(conf_get backend_deploy_args_dry "live")
BE_ARGS_LIVE=$(conf_get backend_deploy_args_live "live go")

godot_ok() { [[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || command -v "$GODOT_BIN" >/dev/null 2>&1; }

godot_status() {
    if [[ -z "$GODOT_BIN" ]]; then
        printf '%sgodot: not set in the conf%s' "$RED" "$RESET"
    elif godot_ok; then
        printf '%s%s%s' "$GREEN" "$GODOT_BIN" "$RESET"
    else
        printf '%s%s (not executable)%s' "$RED" "$GODOT_BIN" "$RESET"
    fi
}

# ------------------------------------------------------------- game list
# Every games/<id>/ that is a real, deployable edition: it needs a manifest
# and a destination, and _template (plus its CHANGE-ME destination) is not one.
GAMES=(); DESTS=()
load_games() {
    GAMES=(); DESTS=()
    local d id dest
    for d in games/*/; do
        id=${d#games/}; id=${id%/}
        [[ "$id" == _* ]] && continue
        [[ -f "games/$id/game.json" && -f "games/$id/deploy.json" ]] || continue
        dest=$(sed -n 's/.*"destination"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "games/$id/deploy.json")
        [[ "$dest" == *CHANGE-ME* ]] && continue
        GAMES+=("$id")
        DESTS+=("${dest##*/}")     # the public URL segment (tight5 -> jax)
    done
}

# --------------------------------------------------------------- key input
# One keypress -> a word. Arrow keys arrive as an escape sequence, so the
# escape is followed by a short non-blocking read for the rest of it.
# A closed stdin reports "eof": every menu treats that as quit, so the script
# can never spin forever redrawing on no input.
read_key() {
    local k rest
    IFS= read -rsn1 k 2>/dev/null || { echo eof; return 1; }
    case "$k" in
        $'\e')
            IFS= read -rsn2 -t 0.05 rest 2>/dev/null || rest=""
            case "$rest" in
                '[A') echo up ;;
                '[B') echo down ;;
                '[C') echo right ;;
                '[D') echo left ;;
                '')   echo esc ;;
                *)    echo other ;;
            esac ;;
        '')  echo enter ;;
        ' ') echo space ;;
        *)   echo "$k" ;;
    esac
}

pause() { printf '\n%sPress any key to continue…%s' "$DIM" "$RESET"; read_key >/dev/null; }

banner() {
    clear
    printf '%s%s╔══════════════════════════════════════════════════╗%s\n' "$BOLD" "$PINK" "$RESET"
    printf '%s%s║        TIGHT 5 FIGHT!  ·  RELEASE MANAGER        ║%s\n' "$BOLD" "$PINK" "$RESET"
    printf '%s%s╚══════════════════════════════════════════════════╝%s\n' "$BOLD" "$PINK" "$RESET"
    printf '  %s%s%s\n\n' "$DIM" "$BASE" "$RESET"
}

# ------------------------------------------------------- dry run or live?
# Replaces the old DEPLOY GO checkbox. Sets MODE to dry|live|cancel. The
# cursor starts on Dry Run, so the harmless answer is the one ENTER gives.
MODE=""
ask_mode() {
    local cur=0 last=2
    local -a opts=("Dry Run" "LIVE Deploy" "Cancel")
    MODE=""
    cursor_hide
    while true; do
        # redraw just the question block, under whatever the caller printed
        printf '\n'
        local i
        for ((i = 0; i <= last; i++)); do
            local color="" ; [[ $i -eq 1 ]] && color="$RED"
            if (( cur == i )); then
                printf '  %s>%s %s%d)%s %s%s%s%s\n' "$GOLD" "$RESET" "$DIM" $((i + 1)) "$RESET" \
                       "$BOLD" "$color" "${opts[i]}" "$RESET"
            else
                printf '    %s%d)%s %s%s%s\n' "$DIM" $((i + 1)) "$RESET" "$color" "${opts[i]}" "$RESET"
            fi
        done
        case "$(read_key)" in
            up|k)   (( cur = cur > 0 ? cur - 1 : last )) ;;
            down|j) (( cur = cur < last ? cur + 1 : 0 )) ;;
            1) cur=0; MODE=dry;    break ;;
            2) cur=1; MODE=live;   break ;;
            3) cur=2; MODE=cancel; break ;;
            enter)
                case $cur in
                    0) MODE=dry ;; 1) MODE=live ;; 2) MODE=cancel ;;
                esac
                break ;;
            q|esc|eof) MODE=cancel; break ;;
        esac
        # step back over the three lines and the blank one, so the block
        # redraws in place instead of marching down the screen
        printf '\e[4A'
    done
    cursor_show
    printf '\n'
}

# ------------------------------------------------------------- runners
# run_one <label> <script> <args…> — one deploy, echoed before it runs.
# Returns the script's own exit status.
run_one() {
    local label="$1" script="$2"; shift 2
    printf '\n%s%s── %s ─────────────────────────────%s\n' "$BOLD" "$PINK" "$label" "$RESET"
    # GODOT is only meaningful to the game script; the other two ignore it.
    GODOT="$GODOT_BIN" "$script" "$@"
}

check_script() {   # <path> <what>
    if [[ ! -x "$1" ]]; then
        printf '\n  %s%s is not there or not executable:%s\n    %s\n' "$RED" "$2" "$RESET" "$1"
        printf '  %s(the deploy scripts are gitignored — they do not come with a fresh checkout)%s\n' "$DIM" "$RESET"
        pause; return 1
    fi
    return 0
}

# ------------------------------------------------------------ games screen
games_screen() {
    load_games
    if (( ${#GAMES[@]} == 0 )); then
        banner; printf '  %sNo deployable games found under games/.%s\n' "$RED" "$RESET"; pause; return
    fi

    local n=${#GAMES[@]}
    local -a checked
    local i
    for ((i = 0; i < n; i++)); do checked[i]=0; done
    local cur=0
    local last=$((n + 1))            # RUN=n, BACK=n+1

    cursor_hide
    while true; do
        banner
        printf '  %sGodot:%s %s\n\n' "$DIM" "$RESET" "$(godot_status)"
        printf '  %sSPACE%s toggles · %s↑/↓%s moves · %sENTER%s runs · %sa%s/%sn%s all/none · %sq%s back\n\n' \
               "$BOLD" "$RESET" "$BOLD" "$RESET" "$BOLD" "$RESET" "$BOLD" "$RESET" "$BOLD" "$RESET" "$BOLD" "$RESET"

        local mark pointer label
        for ((i = 0; i < n; i++)); do
            [[ ${checked[i]} -eq 1 ]] && mark="${GOLD}x${RESET}" || mark=" "
            [[ $cur -eq $i ]] && pointer="${GOLD}>${RESET}" || pointer=" "
            label=$(printf '%-12s' "${GAMES[i]}")
            [[ $cur -eq $i ]] && label="${BOLD}${label}${RESET}"
            printf '  %s [%s] %s %s→ %s%s\n' "$pointer" "$mark" "$label" "$DIM" "${DESTS[i]}" "$RESET"
        done

        printf '      %s──────────────────────────────────────────%s\n' "$DIM" "$RESET"
        [[ $cur -eq $n ]] && pointer="${GOLD}>${RESET}" || pointer=" "
        printf '  %s     %sRUN DEPLOY%s\n' "$pointer" "$BOLD" "$RESET"
        [[ $cur -eq $((n + 1)) ]] && pointer="${GOLD}>${RESET}" || pointer=" "
        printf '  %s     BACK\n' "$pointer"

        local picked=0
        for ((i = 0; i < n; i++)); do (( picked += checked[i] )); done
        printf '\n  %s%d selected%s\n' "$DIM" "$picked" "$RESET"

        case "$(read_key)" in
            up|k)    (( cur = cur > 0 ? cur - 1 : last )) ;;
            down|j)  (( cur = cur < last ? cur + 1 : 0 )) ;;
            space)   (( cur < n )) && checked[cur]=$(( 1 - checked[cur] )) ;;
            enter)
                if   (( cur < n ));  then checked[cur]=$(( 1 - checked[cur] ))
                elif (( cur == n )); then cursor_show; run_games checked[@]; cursor_hide
                else cursor_show; return
                fi ;;
            a)  for ((i = 0; i < n; i++)); do checked[i]=1; done ;;
            n)  for ((i = 0; i < n; i++)); do checked[i]=0; done ;;
            q|esc|eof) cursor_show; return ;;
        esac
    done
}

run_games() {
    local -a sel=("${!1}")
    local i
    local -a todo=()
    for ((i = 0; i < ${#GAMES[@]}; i++)); do
        [[ ${sel[i]} -eq 1 ]] && todo+=("${GAMES[i]}")
    done

    clear
    if (( ${#todo[@]} == 0 )); then
        printf '\n  %sNothing ticked — nothing to do.%s\n' "$GOLD" "$RESET"; pause; return
    fi
    check_script "$GAME_SCRIPT" "The game deploy script" || return
    if ! godot_ok; then
        printf '\n  %sGodot binary is not usable: %s%s\n' "$RED" "${GODOT_BIN:-<not set>}" "$RESET"
        printf '  %sSet "godot:" in %s%s\n' "$DIM" "$CONF_FILE" "$RESET"
        pause; return
    fi

    printf '\n  %sDeploying %d edition(s):%s %s\n' "$BOLD" "${#todo[@]}" "$RESET" "${todo[*]}"
    ask_mode
    [[ "$MODE" == "cancel" ]] && { printf '  %sCancelled.%s\n' "$GOLD" "$RESET"; pause; return; }

    local -a extra=()
    if [[ "$MODE" == "live" ]]; then read -r -a extra <<< "$GAME_ARGS_LIVE"
    else                             read -r -a extra <<< "$GAME_ARGS_DRY"; fi

    local -a failed=()
    for i in "${todo[@]}"; do
        run_one "$i ${MODE}" "$GAME_SCRIPT" "$i" ${extra+"${extra[@]}"}
        # Keep going if one edition fails — the rest are independent builds,
        # and the summary below is what you actually read afterwards.
        [[ $? -ne 0 ]] && failed+=("$i")
    done

    printf '\n%s%s── SUMMARY ─────────────────────────────────%s\n' "$BOLD" "$PINK" "$RESET"
    for i in "${todo[@]}"; do
        if [[ " ${failed[*]-} " == *" $i "* ]]; then
            printf '  %sFAILED%s  %s\n' "$RED" "$RESET" "$i"
        else
            printf '  %sok%s      %s%s\n' "$GREEN" "$RESET" "$i" "$([[ "$MODE" == live ]] && echo "" || echo " (dry run)")"
        fi
    done
    [[ "$MODE" == live && ${#failed[@]} -eq 0 ]] && \
        printf '\n  %sGames are out. The website and backend are separate menu items.%s\n' "$DIM" "$RESET"
    pause
}

# ------------------------------------------------- website / backend screens
# Both are one script with no per-item choices, so they are the same flow:
# show what will run, ask, run it.
run_simple() {
    local title="$1" script="$2" dry_args="$3" live_args="$4" after="${5:-}"
    clear
    check_script "$script" "The $title script" || return

    printf '\n  %s%s%s\n' "$BOLD" "$title" "$RESET"
    printf '  %s%s%s\n' "$DIM" "$script" "$RESET"
    ask_mode
    [[ "$MODE" == "cancel" ]] && { printf '  %sCancelled.%s\n' "$GOLD" "$RESET"; pause; return; }

    local -a args=()
    if [[ "$MODE" == "live" ]]; then read -r -a args <<< "$live_args"
    else                             read -r -a args <<< "$dry_args"; fi

    run_one "$title ${MODE}" "$script" ${args+"${args[@]}"}
    local rc=$?

    printf '\n%s%s── SUMMARY ─────────────────────────────────%s\n' "$BOLD" "$PINK" "$RESET"
    if (( rc == 0 )); then
        printf '  %sok%s      %s%s\n' "$GREEN" "$RESET" "$title" "$([[ "$MODE" == live ]] && echo "" || echo " (dry run)")"
        [[ "$MODE" == live && -n "$after" ]] && printf '\n  %s%s%s\n' "$DIM" "$after" "$RESET"
    else
        printf '  %sFAILED%s  %s (exit %d)\n' "$RED" "$RESET" "$title" "$rc"
    fi
    pause
}

# ------------------------------------------------------------------- main
MENU=("Deploy Games" "Deploy Website" "Deploy Backend" "Exit")

menu_activate() {
    case "$1" in
        0) cursor_show; games_screen; cursor_hide ;;
        1) cursor_show; run_simple "Deploy Website" "$WEB_SCRIPT" "$WEB_ARGS_DRY" "$WEB_ARGS_LIVE" \
               "Check https://games.imstandup.com/"; cursor_hide ;;
        2) cursor_show; run_simple "Deploy Backend" "$BE_SCRIPT" "$BE_ARGS_DRY" "$BE_ARGS_LIVE" \
               "Now on the VPS: pm2 restart tight5fight-lb"; cursor_hide ;;
        3) cursor_show; clear; exit 0 ;;
    esac
}

cur=0
last=$(( ${#MENU[@]} - 1 ))
cursor_hide
while true; do
    banner
    for ((i = 0; i <= last; i++)); do
        if (( cur == i )); then
            printf '  %s>%s %s%d)%s %s%s%s\n' "$GOLD" "$RESET" "$DIM" $((i + 1)) "$RESET" "$BOLD" "${MENU[i]}" "$RESET"
        else
            printf '    %s%d)%s %s\n' "$DIM" $((i + 1)) "$RESET" "${MENU[i]}"
        fi
    done
    printf '\n  %s↑/↓%s moves · %sENTER%s selects · or press %s1-%d%s\n' \
           "$BOLD" "$RESET" "$BOLD" "$RESET" "$BOLD" $((last + 1)) "$RESET"

    case "$(read_key)" in
        up|k)    (( cur = cur > 0 ? cur - 1 : last )) ;;
        down|j)  (( cur = cur < last ? cur + 1 : 0 )) ;;
        enter)   menu_activate "$cur" ;;
        1)       cur=0; menu_activate 0 ;;
        2)       cur=1; menu_activate 1 ;;
        3)       cur=2; menu_activate 2 ;;
        4)       cur=3; menu_activate 3 ;;
        q|esc|eof) cursor_show; clear; exit 0 ;;
    esac
done
