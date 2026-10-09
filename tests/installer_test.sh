#!/bin/sh
# インストーラー（i）のテスト。npm test（npm run deploy の前にも）で動く。
#   sh tests/installer_test.sh
# 1. 文法（sh -n、shellcheck があればそれも）
# 2. アプリの番号・呼び名・説明・asset がそろっているか（i の関数を読み込んで確かめる）
# 3. 偽のホームフォルダと偽の GitHub（tests/fake_github.py）で、メニューに番号を入れたり
#    install <呼び名> を付けたりして、そのアプリの install.sh が呼ばれるか
# 本物のホームフォルダ・サービス・GitHub には触らない（HOME は一時フォルダ、systemctl と uname は偽物）。
# Windows の Git Bash と、Frame（SteamOS）の上の両方で動く。
set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
I="$root/i"
pass=0
fail=0

ok() { pass=$((pass + 1)); }
ng() {
    fail=$((fail + 1))
    printf 'NG: %s\n' "$*"
}
# check 名前 コマンド...: コマンドが成功すれば合格
check() {
    _name=$1
    shift
    if "$@"; then ok; else ng "$_name"; fi
}

tmp=$(mktemp -d) || exit 1
server_pid=
# i にも cleanup があるので、読み込んでも上書きされない名前にする
test_cleanup() {
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null
    rm -rf "$tmp"
}
trap test_cleanup EXIT
trap 'exit 130' INT TERM

# ---------------------------------------------------------------------------------------------
# 1. 文法

check "sh -n i" sh -n "$I"
if command -v shellcheck >/dev/null 2>&1; then
    check "shellcheck i" shellcheck -s sh "$I"
else
    echo "（shellcheck が無いので飛ばす）"
fi

# ---------------------------------------------------------------------------------------------
# 2. 関数の中身。最後の行（main "$@"）を除いて読み込む

last=$(tail -n 1 "$I")
check "最後の行が main \"\$@\" だけ" [ "$last" = 'main "$@"' ]
sed '$d' "$I" >"$tmp/lib.sh"
# shellcheck disable=SC1091
. "$tmp/lib.sh"
setup_colors

n=0
for _a in $all_apps; do n=$((n + 1)); done
check "アプリが 1 つ以上ある" [ "$n" -ge 1 ]

# 番号は 1〜N の連番で、重複しない
seen=' '
for _a in $all_apps; do
    _k=$(app_number "$_a")
    case $_k in
        '' | *[!0-9]*) ng "$_a の番号が数でない（$_k）"; continue ;;
    esac
    case $seen in *" $_k "*) ng "番号 $_k が重複" ;; esac
    seen="$seen$_k "
    if [ "$_k" -ge 1 ] && [ "$_k" -le "$n" ]; then ok; else ng "$_a の番号 $_k が 1〜$n の外"; fi
done
k=1
while [ "$k" -le "$n" ]; do
    case $seen in *" $k "*) ok ;; *) ng "番号 $k のアプリが無い" ;; esac
    k=$((k + 1))
done

# 番号 → アプリ（pick_apps）、番号・正式名 → アプリ（resolve_app）、説明、asset
for _a in $all_apps; do
    _k=$(app_number "$_a")
    _p=$(pick_apps "$_k")
    check "pick_apps $_k → $_a" [ "$_p" = "$_a " ]
    check "resolve_app $_k → $_a" [ "$(resolve_app "$_k")" = "$_a" ]
    check "resolve_app $_a → $_a" [ "$(resolve_app "$_a")" = "$_a" ]
    lang=ja
    check "$_a の説明（日本語）" [ -n "$(app_desc "$_a")" ]
    lang=en
    check "$_a の説明（英語）" [ -n "$(app_desc "$_a")" ]
    asset=
    repo=
    load_app "$_a"
    case $asset in *'{version}'*) ok ;; *) ng "$_a の asset に {version} が無い（$asset）" ;; esac
    check "$_a の repo" [ "$repo" = "sasaken1102r/$_a" ]
done

# まとめて選ぶ（逆順に入れても一覧の順に出る）
all_nums=
k=$n
while [ "$k" -ge 1 ]; do
    all_nums="$all_nums $k"
    k=$((k - 1))
done
# shellcheck disable=SC2086
_p=$(pick_apps $all_nums)
check "pick_apps 1〜$n をまとめて" [ "$_p" = "$(printf '%s ' $all_apps)" ]
# 範囲の外と文字は断る
for _w in 0 "$((n + 1))" x 1x; do
    if pick_apps "$_w" >/dev/null; then ng "pick_apps $_w を断らない"; else ok; fi
done
if pick_apps 1 "$((n + 1))" >/dev/null; then ng "pick_apps 1 $((n + 1)) を断らない"; else ok; fi

# 使い方（--help）の文に全アプリと呼び名が出て、呼び名はそのアプリになる
aliases=
for lang in ja en; do
    _u=$(usage)
    for _a in $all_apps; do
        case $_u in *"$_a ("*")"*) ok ;; *) ng "使い方（$lang）に $_a（呼び名）が無い" ;; esac
    done
done
for _a in $all_apps; do
    _al=$(printf '%s\n' "$_u" | tr ',、' '\n\n' | sed -n "s/.*$_a (\([a-z0-9-]*\)).*/\1/p" | head -n 1)
    if [ -n "$_al" ] && [ "$(resolve_app "$_al")" = "$_a" ]; then
        ok
        aliases="$aliases $_a:$_al"
    else
        ng "$_a の呼び名（${_al:-無し}）が resolve_app で $_a にならない"
    fi
done

# 番号の範囲の決め打ちが残っていない（アプリを足したときの直し忘れを止める）
if grep -n -e '\[1-[0-9]\]' -e '1〜[0-9]' -e 'numbers 1-[0-9]' "$I" >"$tmp/fixed"; then
    ng "番号の範囲の決め打ちが残っている:"
    cat "$tmp/fixed"
else
    ok
fi

# ---------------------------------------------------------------------------------------------
# 3. 偽の GitHub と偽のホームフォルダで通しで動かす

py=
for _c in python3 python; do
    if "$_c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 6) else 1)' >/dev/null 2>&1; then
        py=$_c
        break
    fi
done
if [ -z "$py" ]; then
    ng "python3 が無いので通しのテストができない"
    printf '\n合格 %d / 不合格 %d\n' "$pass" "$fail"
    exit 1
fi

# Windows のネイティブの python に渡すパス
native_path() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

tag=v9.9.9
rel="$tmp/releases"
log="$tmp/install.log"
for _a in $all_apps; do
    load_app "$_a"
    _name=$(printf '%s' "$asset" | sed "s/{version}/${tag#v}/")
    mkdir -p "$tmp/stage/$_a/$_a" "$rel/$_a"
    # 引数を記録するだけの install.sh
    printf '#!/bin/sh\nprintf "%%s %%s\\n" %s "$*" >>"$FAKE_LOG"\n' "$_a" >"$tmp/stage/$_a/$_a/install.sh"
    chmod +x "$tmp/stage/$_a/$_a/install.sh"
    (cd "$tmp/stage/$_a" && tar -czf "$rel/$_a/$_name" "$_a") || ng "$_a の偽のリリースを作れない"
    (cd "$rel/$_a" && sha256sum "$_name" >SHA256SUMS)
done

"$py" "$(native_path "$here/fake_github.py")" "$(native_path "$rel")" "$(native_path "$tmp/port")" "$tag" \
    >"$tmp/server.log" 2>&1 </dev/null &
server_pid=$!
_w=0
while [ ! -s "$tmp/port" ] && [ "$_w" -lt 100 ]; do
    sleep 0.1
    _w=$((_w + 1))
done
port=$(cat "$tmp/port" 2>/dev/null)
if [ -z "$port" ]; then
    ng "偽の GitHub が起動しない"
    printf '\n合格 %d / 不合格 %d\n' "$pass" "$fail"
    exit 1
fi

# 偽の uname（aarch64 と答える）と systemctl（何も有効でない）
mkdir -p "$tmp/bin"
real_uname=$(command -v uname)
printf '#!/bin/sh\n[ "${1:-}" = -m ] && { echo aarch64; exit 0; }\nexec "%s" "$@"\n' "$real_uname" >"$tmp/bin/uname"
printf '#!/bin/sh\nexit 1\n' >"$tmp/bin/systemctl"
chmod +x "$tmp/bin/uname" "$tmp/bin/systemctl"

# SteamOS でなければ、i は「続ける？」と聞くので、答えの最初に y を足す
os_id=$(sed -n 's/^ID=//p' /etc/os-release 2>/dev/null | tr -d '"')
first_answer=
[ "$os_id" = steamos ] || first_answer=y

run_no=0
# run_i 答え（改行区切り）-- i の引数...: 新しい偽のホームで i を動かす。出力は $out、記録は $log
run_i() {
    _answers=$1
    shift
    run_no=$((run_no + 1))
    _home="$tmp/home$run_no"
    mkdir -p "$_home"
    : >"$log"
    {
        [ -n "$first_answer" ] && printf '%s\n' "$first_answer"
        printf '%s\n' "$_answers"
        _e=0
        while [ "$_e" -lt 20 ]; do echo; _e=$((_e + 1)); done
    } >"$tmp/answers$run_no"
    out="$tmp/out$run_no"
    HOME=$_home XDG_CONFIG_HOME="$_home/.config" XDG_CACHE_HOME="$_home/.cache" \
        PATH="$tmp/bin:$PATH" FAKE_LOG=$log \
        FRAME_INSTALLER_GITHUB="http://127.0.0.1:$port" FRAME_INSTALLER_ALLOW_INSECURE=1 \
        FRAME_INSTALLER_TEST_TTY="$tmp/answers$run_no" \
        sh "$I" --lang ja "$@" >"$out" 2>&1 </dev/null
    run_rc=$?
}

# 呼ばれた install.sh のアプリ（記録の 1 列目）を、一覧の順に空白区切りで
called() {
    for _a in $all_apps; do
        grep -q "^$_a " "$log" && printf '%s ' "$_a"
    done
}

show_out() {
    echo "--- 出力 ---"
    sed 's/\x1b\[[0-9;]*m//g' "$out" | tail -n 25
    echo "---"
}

# メニューで番号を 1 つずつ
for _a in $all_apps; do
    _k=$(app_number "$_a")
    run_i "$_k" || :
    if [ "$(called)" = "$_a " ] && [ "$run_rc" -eq 0 ]; then ok; else ng "メニューで $_k → $_a の install.sh（呼ばれた: $(called)、終了 $run_rc）"; show_out; fi
done

# メニューで複数（最初と最後）
_first=${all_apps%% *}
_last=${all_apps##* }
run_i "1 $n" || :
if [ "$(called)" = "$_first $_last " ]; then ok; else ng "メニューで 1 $n（呼ばれた: $(called)）"; show_out; fi

# メニューで a（全部）
run_i a || :
if [ "$(called)" = "$(printf '%s ' $all_apps)" ]; then ok; else ng "メニューで a（呼ばれた: $(called)）"; show_out; fi

# 範囲の外の番号には案内が出て、もう一度聞く
run_i "0
$((n + 1))
x
$n" || :
_hint=$(grep -c "1〜$n の番号" "$out")
if [ "$_hint" -ge 3 ]; then ok; else ng "範囲の外の番号で「1〜$n の番号」の案内が 3 回出ない（$_hint 回）"; show_out; fi
if [ "$(called)" = "$_last " ]; then ok; else ng "範囲の外のあとの $n で $_last（呼ばれた: $(called)）"; show_out; fi

# install <呼び名>（SteamOS では --yes も）
for _pair in $aliases; do
    _a=${_pair%%:*}
    _al=${_pair#*:}
    run_i "" install "$_al" || :
    if [ "$(called)" = "$_a " ] && [ "$run_rc" -eq 0 ]; then ok; else ng "install $_al → $_a（呼ばれた: $(called)、終了 $run_rc）"; show_out; fi
    if [ "$os_id" = steamos ]; then
        run_i "" install "$_al" --yes || :
        if [ "$(called)" = "$_a " ] && [ "$run_rc" -eq 0 ]; then ok; else ng "install $_al --yes → $_a（呼ばれた: $(called)）"; show_out; fi
    fi
done
[ "$os_id" = steamos ] || echo "（SteamOS ではないので --yes の通しは飛ばした。i は SteamOS 以外だと「続ける？」に既定の「いいえ」で止まるため）"

printf '\n合格 %d / 不合格 %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
