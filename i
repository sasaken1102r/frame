#!/bin/sh
# SPDX-License-Identifier: MIT — https://github.com/sasaken1102r/frame
# Installs, updates or removes sasaken1102r's Steam Frame apps from their latest GitHub releases.
# Run it on the headset as the normal user, for example in Konsole:
#
#   curl -fsSL https://frame.sasaken1102s.net | sh                         menu
#   curl -fsSL https://frame.sasaken1102s.net | sh -s -- install eye mic   no menu
#   curl -fsSL https://frame.sasaken1102s.net | sh -s -- uninstall perf
#   ... | sh -s -- --help
#
# For each app it downloads the release tar.gz and its SHA256SUMS from GitHub, checks the SHA-256,
# checks the archive (no absolute paths, "..", links or special files), extracts it into a temporary
# folder below the home folder and runs the release's own install.sh, whose output stays visible.
# No sudo; nothing is written outside the home folder (install.sh itself only writes there too).
# The same steps as frame-updater's frame-update.sh, which the apps use to update themselves, but
# standalone. POSIX sh; needs curl, tar, gzip and sha256sum (python3 checks the archive if present).
#
# The file only defines functions; the one command is the last line, so a download that breaks off
# halfway runs nothing. Questions are read from /dev/tty (stdin is the script itself); without a
# terminal, or with --yes, every question takes its default answer.
#
# Test overrides (environment): FRAME_INSTALLER_DRY_RUN=1 (do everything except running install.sh,
# print its command instead), FRAME_INSTALLER_GITHUB (default https://github.com),
# FRAME_INSTALLER_ALLOW_INSECURE=1 (allow http:// and any host).

# ---------------------------------------------------------------------------------------------
# The apps

all_apps='frameeyeosc frame-jp-keyboard frame-mic-tuner frame-perf-overlay frame-aux-shortcuts'

# Set the variables describing APP: repo, asset (with {version}), unit, has_purge.
load_app() { # app
    repo="sasaken1102r/$1"
    unit="$1.service"
    has_purge=0
    case $1 in
        frameeyeosc)
            asset='frameeyeosc-{version}-steamframe-aarch64.tar.gz'
            has_purge=1
            ;;
        frame-jp-keyboard) asset='frame-jp-keyboard-{version}.tar.gz' ;;
        frame-mic-tuner)
            asset='frame-mic-tuner-{version}.tar.gz'
            has_purge=1
            ;;
        frame-perf-overlay) asset='frame-perf-overlay-{version}.tar.gz' ;;
        frame-aux-shortcuts) asset='frame-aux-shortcuts-{version}.tar.gz' ;;
    esac
}

# Print the one-line description of APP.
app_desc() { # app
    case $1 in
        frameeyeosc) t '視線とまぶたを OSC で VRChat に送る' 'Sends eye gaze and eyelids to VRChat over OSC' ;;
        frame-jp-keyboard) t 'VR キーボードにフリック入力とかな漢字変換' 'Japanese flick input and kana-kanji conversion for the VR keyboard' ;;
        frame-mic-tuner) t 'マイクのエコー除去・ノイズ除去を切り替える' 'Switches the mic echo cancellation and noise suppression' ;;
        frame-perf-overlay) t 'フレームレート・温度などを視界の隅に出す' 'Shows frame rate, temperatures and more in a corner of the view' ;;
        frame-aux-shortcuts) t 'aux ボタンを、押し方ごとのショートカットにする' 'Shortcuts on the aux button, one for each way you press it' ;;
    esac
}

# Print the full name for a name, short name or menu number, or fail.
resolve_app() { # word
    case $1 in
        1 | frameeyeosc | eye | eyeosc) echo frameeyeosc ;;
        2 | frame-jp-keyboard | jp-keyboard | keyboard | kb | jp) echo frame-jp-keyboard ;;
        3 | frame-mic-tuner | mic-tuner | mic) echo frame-mic-tuner ;;
        4 | frame-perf-overlay | perf-overlay | perf) echo frame-perf-overlay ;;
        5 | frame-aux-shortcuts | aux-shortcuts | aux) echo frame-aux-shortcuts ;;
        *) return 1 ;;
    esac
}

# Print the menu number of APP.
app_number() { # app
    case $1 in
        frameeyeosc) echo 1 ;;
        frame-jp-keyboard) echo 2 ;;
        frame-mic-tuner) echo 3 ;;
        frame-perf-overlay) echo 4 ;;
        frame-aux-shortcuts) echo 5 ;;
    esac
}

# True if APP is installed (its user unit or its main file is there).
is_installed() { # app
    load_app "$1"
    [ -f "$unit_dir/$unit" ] && return 0
    case $1 in
        frame-jp-keyboard) [ -f "$HOME/.local/share/frame-jp-keyboard/bundle.js" ] ;;
        *) [ -f "$bin_dir/$1" ] ;;
    esac
}

# Print the installed version of APP, or nothing when it can't be told (frameeyeosc itself has no
# --version, so its panel's is used when the panel is installed).
installed_version() { # app
    case $1 in
        frameeyeosc) _v=$(binary_version "$bin_dir/frameeyeosc-panel" frameeyeosc-panel) ;;
        frame-jp-keyboard) _v=$(head -n 1 "$HOME/.local/share/frame-jp-keyboard/VERSION" 2>/dev/null) ;;
        *) _v=$(binary_version "$bin_dir/$1" "$1") ;;
    esac
    _v=${_v#[vV]}
    version_core "$_v" >/dev/null && printf '%s\n' "$_v"
}

# Print the version a binary reports with --version ("<name> <version>"), or nothing.
binary_version() { # binary name
    [ -x "$1" ] || return 0
    if command -v timeout >/dev/null 2>&1; then
        _out=$(timeout 5 "$1" --version </dev/null 2>/dev/null | head -n 1)
    else
        _out=$("$1" --version </dev/null 2>/dev/null | head -n 1)
    fi
    case $_out in "$2 "*) printf '%s\n' "${_out#"$2 "}" ;; esac
}

# True if the app's install-args file has the line OPTION.
args_file_has() { # app option
    [ -f "$config_home/$1/install-args" ] && grep -qx -- "$2" "$config_home/$1/install-args"
}

# ---------------------------------------------------------------------------------------------
# Output and questions

# Print the Japanese or the English text, without a newline.
t() { # ja en
    if [ "$lang" = ja ]; then printf '%s' "$1"; else printf '%s' "$2"; fi
}

# Print a line in the current language.
say() { # ja en
    t "$1" "$2"
    echo
}

# Print a heading.
heading() { # text
    printf '\n%s== %s ==%s\n' "$c_bold" "$1" "$c_off"
}

warn() { # ja en
    printf '%s%s%s\n' "$c_yellow" "$(t "$1" "$2")" "$c_off" >&2
}

# Print an error and stop.
die() { # ja en
    printf '%s%s%s\n' "$c_red" "$(t "$1" "$2")" "$c_off" >&2
    exit 1
}

# Read one line from the terminal into $reply. Fails at end of input.
read_tty() { # prompt
    printf '%s' "$1"
    IFS= read -r reply </dev/tty || return 1
    reply=$(printf '%s' "$reply" | tr -d '\r')
}

# Ask a yes/no question; DEFAULT (y or n) is the answer on Enter, and without questions (--yes or
# no terminal). True for yes.
ask_yn() { # question default
    if [ "$2" = y ]; then
        _hint=$(t '（y: はい / n: いいえ。Enter だけなら はい）' '(y = yes / n = no, Enter = yes)')
    else
        _hint=$(t '（y: はい / n: いいえ。Enter だけなら いいえ）' '(y = yes / n = no, Enter = no)')
    fi
    if [ "$interactive" != 1 ]; then
        printf '%s %s %s\n' "$1" "$_hint" "$2"
        [ "$2" = y ]
        return
    fi
    while :; do
        read_tty "$1 $_hint " || { echo; [ "$2" = y ]; return; }
        case $reply in
            '') [ "$2" = y ]; return ;;
            [Yy] | [Yy][Ee][Ss]) return 0 ;;
            [Nn] | [Nn][Oo]) return 1 ;;
        esac
    done
}

setup_colors() {
    c_bold= c_red= c_green= c_yellow= c_dim= c_off=
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
        _esc=$(printf '\033')
        c_bold="$_esc[1m" c_red="$_esc[31m" c_green="$_esc[32m" c_yellow="$_esc[33m"
        c_dim="$_esc[2m" c_off="$_esc[0m"
    fi
}

# Pick the language: --lang, else a Japanese locale (the first set of LC_ALL, LC_MESSAGES, LANG),
# else Steam's language setting (the first "language" in ~/.steam/registry.vdf, read the same way
# as frame-perf-overlay does), else English.
detect_lang() {
    for _var in "${LC_ALL:-}" "${LC_MESSAGES:-}" "${LANG:-}"; do
        [ -n "$_var" ] || continue
        case $_var in ja*) echo ja; return ;; esac
        break
    done
    _steam=$(sed -n 's/.*"language"[[:space:]]*"\([^"]*\)".*/\1/p' "$HOME/.steam/registry.vdf" 2>/dev/null | head -n 1)
    case $_steam in japanese) echo ja ;; *) echo en ;; esac
}

usage() {
    if [ "$lang" = ja ]; then
        cat <<'EOF'
ささけん＠の Steam Frame アプリ（インストールのしかた）

  curl -fsSL https://frame.sasaken1102s.net | sh
      メニューから選んでインストール・更新・アンインストール
  ... | sh -s -- install <アプリ>...     インストール・更新（all で全部）
  ... | sh -s -- uninstall <アプリ>...   アンインストール（削除）

アプリ: frameeyeosc (eye)、frame-jp-keyboard (keyboard)、
        frame-mic-tuner (mic)、frame-perf-overlay (perf)、
        frame-aux-shortcuts (aux)、all
  --yes, -y      質問にはすべて既定の答えで進む
  --lang ja|en   表示の言語
  --help, -h     これを出す
sudo は使わず、ホームフォルダの中にだけインストールします。
EOF
    else
        cat <<'EOF'
Steam Frame apps by sasaken@ (installer)

  curl -fsSL https://frame.sasaken1102s.net | sh
      pick apps from a menu to install, update or uninstall
  ... | sh -s -- install <app>...     install or update (all for every app)
  ... | sh -s -- uninstall <app>...   uninstall

Apps: frameeyeosc (eye), frame-jp-keyboard (keyboard),
      frame-mic-tuner (mic), frame-perf-overlay (perf),
      frame-aux-shortcuts (aux), all
  --yes, -y      take the default answer for every question
  --lang ja|en   language of the messages
  --help, -h     show this
No sudo; everything goes into your home folder.
EOF
    fi
}

# ---------------------------------------------------------------------------------------------
# Versions (as in frame-update.sh)

# Print the numeric x.y.z core of a version ("v0.4.0-rc1" -> "0.4.0"), or fail if there is none.
version_core() {
    _vc=${1#[vV]}
    _vc=${_vc%%[-+]*}
    case $_vc in
        '' | *[!0-9.]* | .* | *. | *..* | *.*.*.* | *[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*) return 1 ;;
    esac
    printf '%s\n' "$_vc"
}

# Compare two version cores; print -1, 0 or 1. Missing parts count as 0.
vercmp() {
    _va=$1
    _vb=$2
    for _i in 1 2 3; do
        _x=${_va%%.*}
        _y=${_vb%%.*}
        case $_va in *.*) _va=${_va#*.} ;; *) _va= ;; esac
        case $_vb in *.*) _vb=${_vb#*.} ;; *) _vb= ;; esac
        [ -n "$_x" ] || _x=0
        [ -n "$_y" ] || _y=0
        if [ "$_x" -gt "$_y" ]; then echo 1; return; fi
        if [ "$_x" -lt "$_y" ]; then echo -1; return; fi
    done
    echo 0
}

# ---------------------------------------------------------------------------------------------
# Downloads (as in frame-update.sh). On failure these set err and return 1.

# True if the URL may be fetched: https to GitHub only (unless FRAME_INSTALLER_ALLOW_INSECURE=1).
url_allowed() {
    if [ "$insecure" = 1 ]; then
        case $1 in http://* | https://*) return 0 ;; *) return 1 ;; esac
    fi
    case $1 in https://*) ;; *) return 1 ;; esac
    _host=${1#https://}
    _host=${_host%%/*}
    _host=${_host%%\?*}
    _host=${_host%%#*}
    case $_host in
        *[!a-z0-9.-]*) return 1 ;;
        github.com | *.githubusercontent.com) return 0 ;;
    esac
    return 1
}

# curl with the options every request uses; prints what -w asks for.
fetch() { # url output max-seconds write-out [extra curl options...]
    _furl=$1
    _fout=$2
    _fmax=$3
    _fw=$4
    shift 4
    if [ "$insecure" = 1 ]; then
        curl --silent --show-error --fail --connect-timeout 15 --max-time "$_fmax" \
            --max-filesize 268435456 -o "$_fout" -w "$_fw" "$@" "$_furl"
    else
        curl --silent --show-error --fail --connect-timeout 15 --max-time "$_fmax" \
            --proto =https --proto-redir =https \
            --max-filesize 268435456 -o "$_fout" -w "$_fw" "$@" "$_furl"
    fi
}

# Find the latest release of $repo from where github.com/<repo>/releases/latest redirects to (no
# API, so no hourly limit). Sets tag and version.
latest_release() {
    _url="$github/$repo/releases/latest"
    if ! url_allowed "$_url"; then
        err="$(t "つながない URL" "refusing to contact"): $_url"
        return 1
    fi
    _res=$(fetch "$_url" /dev/null 30 '%{http_code} %{redirect_url}' 2>"$work/curl.err")
    _rc=$?
    _code=${_res%% *}
    _loc=${_res#* }
    if [ "$_rc" -ne 0 ] || [ -z "$_code" ]; then
        case $_code in
            404) err=$(t "リリースが見つかりません（$repo）" "no release found in $repo") ;;
            *) err="$(t "GitHub につながりません" "cannot reach GitHub"): $(head -n 1 "$work/curl.err" 2>/dev/null)" ;;
        esac
        return 1
    fi
    case $_code in
        301 | 302 | 303 | 307 | 308) ;;
        *) err=$(t "リリースが見つかりません（HTTP $_code）" "no release found (HTTP $_code)"); return 1 ;;
    esac
    case $_loc in
        "$github/$repo/releases/tag/"?*) tag=${_loc#"$github/$repo/releases/tag/"} ;;
        *)
            err="$(t "リリースが見つかりません" "no release found"): $_loc"
            return 1
            ;;
    esac
    case $tag in
        *[!A-Za-z0-9._-]*)
            err="$(t "リリースの名前がおかしい" "odd release tag"): $tag"
            return 1
            ;;
    esac
    if ! version_core "$tag" >/dev/null; then
        err="$(t "リリースの名前が版になっていない" "the release tag is not a version"): $tag"
        return 1
    fi
    version=${tag#[vV]}
}

# Download URL to FILE, following redirects to GitHub's download hosts only.
download() { # url file max-seconds
    if ! url_allowed "$1"; then
        err="$(t "ダウンロードしない URL" "refusing to download"): $1"
        return 1
    fi
    _res=$(fetch "$1" "$2" "$3" '%{http_code} %{url_effective}' --location --max-redirs 5 2>"$work/curl.err")
    _rc=$?
    _code=${_res%% *}
    _eff=${_res#* }
    if [ "$_rc" -ne 0 ]; then
        err="$(t "ダウンロードできません" "download failed") (HTTP ${_code:-000}): ${1##*/}"
        return 1
    fi
    if ! url_allowed "$_eff"; then
        err="$(t "GitHub の外に転送された" "redirected outside GitHub"): $_eff"
        return 1
    fi
}

# Check FILE against its entry (named NAME) in SUMS.
verify_sha256() { # file name sums
    _expected=$(awk -v n="$2" '$2 == n || $2 == "*" n { print tolower($1); exit }' "$3")
    case $_expected in
        '' | *[!0-9a-f]*)
            err=$(t "SHA256SUMS に $2 が載っていない" "SHA256SUMS has no entry for $2")
            return 1
            ;;
    esac
    if [ "${#_expected}" -ne 64 ]; then
        err=$(t "SHA256SUMS の $2 の行が壊れている" "SHA256SUMS has a malformed entry for $2")
        return 1
    fi
    _actual=$(sha256sum "$1" | cut -c1-64)
    if [ "$_actual" != "$_expected" ]; then
        err=$(t "SHA-256 が合わない（ダウンロードが壊れているかも）" "SHA-256 mismatch (broken download?)")
        return 1
    fi
}

# Check that the archive only holds plain files and folders below the extraction folder. Python
# reads the raw entries (some tar programs quietly rewrite "/" and ".." when listing); without
# python3, GNU tar's listing is checked instead.
check_archive() { # archive
    if command -v python3 >/dev/null 2>&1; then
        _why=$(python3 - "$1" 2>/dev/null <<'EOF'
import sys
import tarfile

try:
    with tarfile.open(sys.argv[1], "r:gz") as tar:
        members = tar.getmembers()
except Exception as error:
    print(f"cannot read it ({error})")
    sys.exit(1)
if not members:
    print("it is empty")
    sys.exit(1)
for member in members:
    name = member.name
    if name.startswith("/") or ".." in name.split("/") or "\\" in name or any(ord(c) < 32 for c in name):
        print(f"unsafe path {name!r}")
        sys.exit(1)
    if not (member.isfile() or member.isdir()):
        print(f"link or special file {name!r}")
        sys.exit(1)
EOF
)
        _rc=$?
    else
        _rc=0
        _why=
        if ! tar -tzf "$1" >"$work/list" 2>/dev/null || ! tar -tvzf "$1" >"$work/vlist" 2>/dev/null; then
            _rc=1
            _why='cannot read it'
        elif [ ! -s "$work/list" ]; then
            _rc=1
            _why='it is empty'
        elif grep -q -e '^/' -e '^\.\.$' -e '^\.\./' -e '/\.\./' -e '/\.\.$' -e '\\' "$work/list"; then
            _rc=1
            _why='unsafe path'
        elif cut -c1 "$work/vlist" | grep -q '[^-d]'; then
            _rc=1
            _why='link or special file'
        fi
    fi
    if [ "$_rc" -ne 0 ]; then
        err="$(t "アーカイブの中身が危ない" "unsafe archive"): ${_why:-?}"
        return 1
    fi
}

# Download, check and extract the latest release of $app into DIR. Sets installer_dir (the folder
# with install.sh). Needs tag and version (latest_release).
fetch_release() { # dir
    _name=$(printf '%s' "$asset" | sed "s/{version}/$version/")
    _base="$github/$repo/releases/download/$tag"
    mkdir -p "$1/files" || { err=$(t "作業フォルダを作れない" "cannot create the work folder"); return 1; }
    say "  $_name をダウンロード中..." "  downloading $_name..."
    download "$_base/$_name" "$1/$_name" 600 || return 1
    download "$_base/SHA256SUMS" "$1/SHA256SUMS" 60 || {
        err=$(t "SHA256SUMS が取れない（照合できないのでインストールしません）" "no SHA256SUMS (can't verify, not installing)")
        return 1
    }
    verify_sha256 "$1/$_name" "$_name" "$1/SHA256SUMS" || return 1
    say "  SHA-256 OK" "  SHA-256 OK"
    check_archive "$1/$_name" || return 1
    if ! tar -xzf "$1/$_name" -C "$1/files" 2>"$work/tar.err"; then
        err="$(t "展開できない" "cannot extract"): $(head -n 1 "$work/tar.err")"
        return 1
    fi
    # install.sh at the top, or inside the only folder there
    installer_dir=
    if [ -f "$1/files/install.sh" ]; then
        installer_dir="$1/files"
    else
        _count=0
        for _entry in "$1/files"/*; do
            [ -e "$_entry" ] || continue
            _count=$((_count + 1))
            _top=$_entry
        done
        if [ "$_count" -eq 1 ] && [ -f "$_top/install.sh" ]; then
            installer_dir=$_top
        fi
    fi
    if [ -z "$installer_dir" ]; then
        err=$(t "リリースに install.sh が入っていない" "no install.sh in the release")
        return 1
    fi
}

# Run the extracted install.sh with the given options; its output goes straight to the terminal.
run_install_sh() { # options...
    if [ "$dry_run" = 1 ]; then
        say "  [dry run] 実行しない: (cd $installer_dir && ./install.sh $*)" \
            "  [dry run] not running: (cd $installer_dir && ./install.sh $*)"
        return 0
    fi
    printf '%s  install.sh%s%s\n' "$c_dim" "${*:+ $*}" "$c_off"
    [ -x "$installer_dir/install.sh" ] || chmod u+x "$installer_dir/install.sh"
    (cd "$installer_dir" && ./install.sh "$@") </dev/null
}

# ---------------------------------------------------------------------------------------------
# Results and notes, collected as lines and printed at the end

add_result() { # app ok|fail|skip text
    case $2 in
        ok) _mark="${c_green}OK${c_off}"; [ "$dry_run" != 1 ] || _mark="$_mark [dry run]" ;;
        fail) _mark="${c_red}$(t '失敗' 'FAILED')${c_off}"; failed=1 ;;
        skip) _mark="${c_yellow}$(t 'スキップ' 'skipped')${c_off}" ;;
    esac
    results="$results$(printf '  %-20s %s %s' "$1" "$_mark" "$3")$nl"
}

add_note() { # text
    notes="$notes  - $1$nl"
}

print_results() {
    [ -n "$results" ] || return 0
    heading "$(t '結果' 'Result')"
    printf '%s' "$results"
    if [ -n "$notes" ]; then
        echo
        printf '%s' "$notes"
    fi
}

# ---------------------------------------------------------------------------------------------
# Install

# Work out install.sh's options for APP, asking where the user has a choice. Sets plan_<n> (the
# options), ver_<n>/tag_<n> (the release to install) and had_<n> (1 if it is installed already),
# with <n> the menu number; or records a failure or skip and returns 1.
plan_install() { # app
    _app=$1
    _n=$(app_number "$_app")
    load_app "$_app"
    printf '\n%s%s%s\n' "$c_bold" "$_app" "$c_off"
    if ! latest_release; then
        add_result "$_app" fail "$err"
        return 1
    fi
    _inst=
    if is_installed "$_app"; then
        _inst=$(installed_version "$_app")
        # Never go back to an older version without asking (a build newer than the release)
        if [ -n "$_inst" ] && [ "$(vercmp "$(version_core "$_inst")" "$(version_core "$version")")" = 1 ]; then
            if ! ask_yn "$(t "  インストール済みの $_inst のほうが最新リリース $version より新しい。$version に戻す？" \
                "  The installed $_inst is newer than the latest release $version. Go back to $version?")" n; then
                add_result "$_app" skip "$(t "$_inst のまま" "kept $_inst")"
                return 1
            fi
        fi
        say "  インストール済み: ${_inst:-?} → 最新: $version（更新）" "  installed: ${_inst:-?} -> latest: $version (update)"
    else
        say "  最新: $version（新しくインストール）" "  latest: $version (new install)"
    fi
    _opts=
    load_app "$_app"
    case $_app in
        frameeyeosc)
            if [ -x "$bin_dir/frameeyeosc-panel" ]; then
                # Without --with-panel an installed panel would stay at its old version
                _opts=--with-panel
                say "  パネル: インストール済みなので一緒に更新" "  panel: installed, updated too"
            else
                _def=y
                if [ -f "$config_home/frameeyeosc/install-args" ] && ! args_file_has frameeyeosc --with-panel; then
                    _def=n
                fi
                if ask_yn "$(t '  ダッシュボードのパネルもインストールする？（被ったまま設定を変えられる）' \
                    '  Also install the dashboard panel? (change settings in VR)')" "$_def"; then
                    _opts=--with-panel
                fi
            fi
            ;;
        frame-mic-tuner)
            if systemctl --user is-enabled --quiet "$unit" 2>/dev/null; then
                # install.sh only ever turns autostart on; keep it on and in install-args
                _opts=--autostart
                say "  SteamVR と一緒に起動: オン（そのまま）" "  start with SteamVR: on (kept)"
            elif ask_yn "$(t '  SteamVR と一緒に起動する？（あとでパネルでも変えられる）' \
                '  Start it together with SteamVR? (can be changed in the panel)')" n; then
                _opts=--autostart
            fi
            ;;
        frame-perf-overlay)
            # Default: as it is now (the dashboard's switch may have changed it), else install-args
            _def=y
            if [ -f "$unit_dir/$unit" ]; then
                systemctl --user is-enabled --quiet "$unit" 2>/dev/null || _def=n
            elif args_file_has frame-perf-overlay --no-autostart; then
                _def=n
            fi
            if ! ask_yn "$(t '  SteamVR と一緒に起動する？' '  Start it together with SteamVR?')" "$_def"; then
                _opts=--no-autostart
            fi
            ;;
        frame-aux-shortcuts)
            # As for frame-perf-overlay: as it is now (the panel's switch may have changed it), else install-args
            _def=y
            if [ -f "$unit_dir/$unit" ]; then
                systemctl --user is-enabled --quiet "$unit" 2>/dev/null || _def=n
            elif args_file_has frame-aux-shortcuts --no-autostart; then
                _def=n
            fi
            if ! ask_yn "$(t '  SteamVR と一緒に起動する？' '  Start it together with SteamVR?')" "$_def"; then
                _opts=--no-autostart
            fi
            ;;
    esac
    eval "plan_$_n=\$_opts; ver_$_n=\$version; tag_$_n=\$tag"
    eval "had_$_n=0"
    is_installed "$_app" && eval "had_$_n=1"
    return 0
}

# Install APP as planned by plan_install.
do_install() { # app
    _app=$1
    _n=$(app_number "$_app")
    load_app "$_app"
    eval "_opts=\$plan_$_n; version=\$ver_$_n; tag=\$tag_$_n; _had=\$had_$_n"
    heading "$_app $version"
    if ! fetch_release "$work/$_app"; then
        add_result "$_app" fail "$err"
        return
    fi
    # shellcheck disable=SC2086 # the options are single words
    if run_install_sh $_opts; then
        if [ "$_had" = 1 ]; then
            add_result "$_app" ok "$(t "更新しました $version" "updated to $version")"
        else
            add_result "$_app" ok "$(t "インストールしました $version" "installed $version")"
        fi
        if [ "$_had" = 0 ]; then
            case $_app in
                frameeyeosc) add_note "$(t 'frameeyeosc: PC 側で Steam Link の OSC 送信をオフにしてね（SteamVR の設定 → Steam Link → OSC）' \
                    "frameeyeosc: turn off Steam Link's OSC output on your PC (SteamVR settings > Steam Link > OSC)")" ;;
                frame-mic-tuner) add_note "$(t 'frame-mic-tuner: 遊んでいないときにヘッドセットを 1 回再起動してね（切り替えの仕組みが有効になる）' \
                    'frame-mic-tuner: restart the headset once while not playing (turns the switching on)')" ;;
            esac
        fi
    else
        add_result "$_app" fail "$(t "install.sh が失敗（上の出力を見てね）" "install.sh failed (see its output above)")"
    fi
    rm -rf "${work:?}/$_app"
}

# Plan every app of the list (asking all questions first), then install them one after another.
install_apps() { # apps...
    _todo=
    for _a in "$@"; do
        plan_install "$_a" && _todo="$_todo $_a"
    done
    for _a in $_todo; do
        do_install "$_a"
    done
}

# ---------------------------------------------------------------------------------------------
# Uninstall

# Remove the apps: each with the install.sh of its latest release and --uninstall.
uninstall_apps() { # apps...
    _todo=
    for _a in "$@"; do
        if is_installed "$_a"; then
            _todo="$_todo $_a"
        else
            add_result "$_a" skip "$(t '未インストール' 'not installed')"
        fi
    done
    [ -n "$_todo" ] || return 0
    if [ "$interactive" = 1 ] && ! ask_yn "$(t "アンインストールします:$_todo。よろしいですか？" "Uninstall:$_todo. OK?")" n; then
        say "やめました。" "Cancelled."
        return 0
    fi
    for _a in $_todo; do
        _n=$(app_number "$_a")
        load_app "$_a"
        eval "purge_$_n=0"
        if [ "$has_purge" = 1 ]; then
            case $_a in
                frameeyeosc) _q=$(t "  $_a: 設定と学習したまぶたの値も消す？" "  $_a: also delete the settings and learned eyelid values?") ;;
                *) _q=$(t "  $_a: 設定と保存した切り替えの値も消す？" "  $_a: also delete the settings and saved switch values?") ;;
            esac
            ask_yn "$_q" n && eval "purge_$_n=1"
        fi
    done
    for _a in $_todo; do
        _n=$(app_number "$_a")
        load_app "$_a"
        heading "$(t "$_a をアンインストール" "Uninstalling $_a")"
        if ! latest_release || ! fetch_release "$work/$_a"; then
            add_result "$_a" fail "$err"
            continue
        fi
        eval "_purge=\$purge_$_n"
        if [ "$_purge" = 1 ]; then
            run_install_sh --uninstall --purge
        else
            run_install_sh --uninstall
        fi
        if [ $? -ne 0 ]; then
            add_result "$_a" fail "$(t "install.sh が失敗（上の出力を見てね）" "install.sh failed (see its output above)")"
        else
            add_result "$_a" ok "$(t 'アンインストールしました' 'uninstalled')"
            case $_a in
                frame-jp-keyboard) add_note "$(t 'frame-jp-keyboard: Steam を再起動（かヘッドセットを再起動）すると、純正キーボードに完全に戻る' \
                    'frame-jp-keyboard: restart Steam (or the headset) to fully get the stock keyboard back')" ;;
                frame-mic-tuner) add_note "$(t 'frame-mic-tuner: 遊んでいないときにヘッドセットを再起動すると、元のマイクの動きに戻る' \
                    "frame-mic-tuner: restart the headset while not playing to get Valve's original mic behaviour back")" ;;
                frame-perf-overlay) add_note "$(t "frame-perf-overlay: 設定は $config_home/frame-perf-overlay に残してある（要らなければ消してOK）" \
                    "frame-perf-overlay: its settings stay in $config_home/frame-perf-overlay (delete it if you like)")" ;;
                frame-aux-shortcuts) add_note "$(t "frame-aux-shortcuts: 設定は $config_home/frame-aux-shortcuts に残してある（要らなければ消してOK）" \
                    "frame-aux-shortcuts: its settings stay in $config_home/frame-aux-shortcuts (delete it if you like)")" ;;
            esac
        fi
        rm -rf "${work:?}/$_a"
    done
}

# ---------------------------------------------------------------------------------------------
# Menu

# Print "installed <version>" or "not installed" for APP.
status_text() { # app
    if is_installed "$1"; then
        _v=$(installed_version "$1")
        printf '%s%s%s' "$c_green" "$(t "インストール済み${_v:+ $_v}" "installed${_v:+ $_v}")" "$c_off"
    else
        printf '%s%s%s' "$c_dim" "$(t '未インストール' 'not installed')" "$c_off"
    fi
}

menu() {
    printf '\n%s%s%s\n' "$c_bold" "$(t 'ささけん＠の Steam Frame アプリ' "Steam Frame apps by sasaken@")" "$c_off"
    for _a in $all_apps; do
        printf '\n  %s) %-20s [%s]\n' "$(app_number "$_a")" "$_a" "$(status_text "$_a")"
        printf '     %s\n' "$(app_desc "$_a")"
    done
    echo
    say "やりたいことを入力して Enter を押してね" "Type what you want to do and press Enter"
    say "  インストール・更新   アプリの番号（例: 1　複数なら 1 3）" \
        "  Install / update   the app's number (e.g. 1, or 1 3 for several)"
    say "  全部インストール     a" "  Install all        a"
    say "  アンインストール     u" "  Uninstall          u"
    say "  終了                 q" "  Quit               q"
    say "（インストール済みのアプリを選ぶと、最新版に更新します）" "(Picking an installed app updates it to the latest version)"
    while :; do
        read_tty '> ' || { echo; return 0; }
        _words=$(printf '%s' "$reply" | tr ',' ' ')
        case $_words in
            *[!\ ]*) ;;
            *) continue ;;
        esac
        set -f
        # shellcheck disable=SC2086 # split the answer into words
        set -- $_words
        set +f
        case $1 in
            [Qq]) return 0 ;;
            # shellcheck disable=SC2086
            [Aa]) install_apps $all_apps; return ;;
            [Uu]) uninstall_menu; return ;;
        esac
        if _picked=$(pick_apps "$@"); then
            install_apps $_picked
            return
        fi
        say "1〜4 の番号か、a / u / q を入力してね" "Type numbers 1-4, or a / u / q"
    done
}

# Print the apps for the menu numbers given (each once, in menu order), or fail.
pick_apps() { # words...
    _p=
    for _w in "$@"; do
        case $_w in [1-4]) ;; *) return 1 ;; esac
        _p="$_p $_w"
    done
    for _a in $all_apps; do
        case " $_p " in *" $(app_number "$_a") "*) printf '%s ' "$_a" ;; esac
    done
}

uninstall_menu() {
    _inst=
    for _a in $all_apps; do
        is_installed "$_a" && _inst="$_inst $_a"
    done
    if [ -z "$_inst" ]; then
        say "インストール済みのアプリはありません。" "No app is installed."
        return 0
    fi
    echo
    say "アンインストール（削除）するアプリの番号を入力して Enter" "Type the number of the app to uninstall and press Enter"
    say "（複数なら 1 3 のようにスペースで区切る。やめるなら q）" "(several: separate with spaces, like 1 3; q to cancel)"
    for _a in $_inst; do
        printf '  %s) %-20s [%s]\n' "$(app_number "$_a")" "$_a" "$(status_text "$_a")"
    done
    while :; do
        read_tty '> ' || { echo; return 0; }
        _words=$(printf '%s' "$reply" | tr ',' ' ')
        case $_words in
            *[!\ ]*) ;;
            *) continue ;;
        esac
        set -f
        # shellcheck disable=SC2086 # split the answer into words
        set -- $_words
        set +f
        case $1 in [Qq]) return 0 ;; esac
        if _picked=$(pick_apps "$@"); then
            _ok=1
            for _a in $_picked; do
                case " $_inst " in *" $_a "*) ;; *) _ok=0 ;; esac
            done
            if [ "$_ok" = 1 ]; then
                uninstall_apps $_picked
                return
            fi
        fi
        say "上の番号か、q を入力してね" "Type numbers from the list, or q"
    done
}

# ---------------------------------------------------------------------------------------------
# Start

# The Frame's Desktop Mode (steamos-nested-desktop) runs a nested Plasma with XDG_RUNTIME_DIR moved to
# .../nested_plasma and its own D-Bus, so `systemctl --user` there cannot reach the user's systemd
# ("Failed to connect to user scope bus"). Point both back at the real session for us and install.sh.
use_real_user_session() {
    _real="/run/user/$(id -u)"
    [ -S "${XDG_RUNTIME_DIR:-}/systemd/private" ] && return 0
    [ -S "$_real/systemd/private" ] || return 0
    XDG_RUNTIME_DIR=$_real
    export XDG_RUNTIME_DIR
    if [ -S "$_real/bus" ]; then
        DBUS_SESSION_BUS_ADDRESS="unix:path=$_real/bus"
        export DBUS_SESSION_BUS_ADDRESS
    fi
}

# Stop on the wrong machine or user, and check the tools.
preflight() {
    if [ "$(id -u)" = 0 ]; then
        die "root では動かしません。ふつうのユーザー（steamos）で、sudo なしで実行してね。" \
            "Don't run this as root. Run it as your normal user (steamos), without sudo."
    fi
    _arch=$(uname -m)
    if [ "$_arch" != aarch64 ]; then
        die "これは Steam Frame（aarch64）用です。このマシンは $_arch なので止めます。" \
            "This is for the Steam Frame (aarch64), but this machine is $_arch. Stopping."
    fi
    if [ -z "${HOME:-}" ] || [ "$HOME" = / ] || [ ! -d "$HOME" ]; then
        die "ホームフォルダ（HOME）が見つかりません。" "Cannot find the home folder (HOME)."
    fi
    _os=$(sed -n 's/^ID=//p' /etc/os-release 2>/dev/null | tr -d '"')
    if [ "$_os" != steamos ]; then
        warn "SteamOS ではないようです（ID=${_os:-?}）。アプリは Steam Frame の SteamOS 用です。" \
            "This does not look like SteamOS (ID=${_os:-?}). The apps are made for the Steam Frame's SteamOS."
        ask_yn "$(t '続ける？' 'Continue anyway?')" n || exit 1
    fi
    _missing=
    for _tool in curl tar gzip sha256sum mktemp awk sed; do
        command -v "$_tool" >/dev/null 2>&1 || _missing="$_missing $_tool"
    done
    if [ -n "$_missing" ]; then
        die "必要なコマンドがありません:$_missing" "Missing commands:$_missing"
    fi
}

# Remove the temporary folder, however the script ends.
cleanup() {
    case $work in
        "$cache_base"/run.?*) rm -rf "$work" ;;
    esac
    rmdir "$cache_base" 2>/dev/null
}

main() {
    nl='
'
    lang=
    cmd=
    apps=
    yes=0
    help=0
    results=
    notes=
    failed=0
    work=
    github=${FRAME_INSTALLER_GITHUB:-https://github.com}
    github=${github%/}
    insecure=${FRAME_INSTALLER_ALLOW_INSECURE:-0}
    dry_run=${FRAME_INSTALLER_DRY_RUN:-0}
    config_home=${XDG_CONFIG_HOME:-$HOME/.config}
    unit_dir="$config_home/systemd/user"
    bin_dir="$HOME/.local/bin"
    cache_base="${XDG_CACHE_HOME:-$HOME/.cache}/frame-installer"

    _bad=
    while [ $# -gt 0 ]; do
        case $1 in
            -h | --help) help=1 ;;
            -y | --yes) yes=1 ;;
            --lang) lang=${2:-}; [ $# -ge 2 ] && shift ;;
            --lang=*) lang=${1#--lang=} ;;
            install | uninstall)
                if [ -z "$cmd" ]; then cmd=$1; else _bad="$_bad $1"; fi
                ;;
            all) apps=$all_apps ;;
            *)
                if _full=$(resolve_app "$1"); then
                    case " $apps " in *" $_full "*) ;; *) apps="$apps $_full" ;; esac
                else
                    _bad="$_bad $1"
                fi
                ;;
        esac
        shift
    done
    case $lang in
        '') lang=$(detect_lang) ;;
        ja | en) ;;
        *) lang=en; _bad="$_bad --lang" ;;
    esac
    setup_colors
    if [ "$help" = 1 ]; then
        usage
        exit 0
    fi
    if [ -n "$_bad" ]; then
        say "わからない引数:$_bad" "Unknown argument:$_bad" >&2
        usage >&2
        exit 2
    fi
    if [ -n "$cmd" ] && [ -z "$apps" ]; then
        say "$cmd するアプリを指定してね（all で全部）" "Name the app(s) to $cmd (or all)" >&2
        usage >&2
        exit 2
    fi
    if [ -z "$cmd" ] && [ -n "$apps" ]; then
        say "install か uninstall を付けてね" "Add install or uninstall" >&2
        usage >&2
        exit 2
    fi

    # Questions need a terminal; `| sh` leaves stdin to the script, so they are read from /dev/tty
    has_tty=0
    (: </dev/tty) 2>/dev/null && has_tty=1
    interactive=0
    [ "$has_tty" = 1 ] && [ "$yes" != 1 ] && interactive=1
    if [ -z "$cmd" ] && [ "$has_tty" != 1 ]; then
        say "ターミナルが無いのでメニューを出せません。例: ... | sh -s -- install all --yes" \
            "No terminal for the menu. For example: ... | sh -s -- install all --yes" >&2
        exit 2
    fi

    preflight
    use_real_user_session
    mkdir -p "$cache_base" || die "$cache_base を作れません" "Cannot create $cache_base"
    trap cleanup EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    work=$(mktemp -d "$cache_base/run.XXXXXX") || die "一時フォルダを作れません" "Cannot create a temporary folder"
    [ "$dry_run" != 1 ] || warn "ドライラン: install.sh は実行しません" "Dry run: install.sh is not run"

    case $cmd in
        '') menu ;;
        # shellcheck disable=SC2086 # app names are single words
        install) install_apps $apps ;;
        # shellcheck disable=SC2086
        uninstall) uninstall_apps $apps ;;
    esac
    print_results
    exit "$failed"
}

main "$@"
