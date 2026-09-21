#!/bin/sh
# 建てた mozc_server と mozc_emacs_helper を実際に動かす。helper の protocol を
# 直に叩いて「にほんご」を変換させ、候補に 日本語 が出るところまで見る。
#
# 建っただけでは IPC の腕は踏めない。client が unix socket で server に繋ぎ、
# peer の資格情報を確かめ、server の path を照合する — この PR が触るのは
# 全部そこで、変換が返って初めて通ったと言える。
#
# root では測れない。base/run_level.cc が geteuid() == 0 を拒み、その応答は
# server が無いときと一字一句同じ ((error . session-error)) なので、一般 user を
# 作って叩く。
#
# 使い方: bsd-smoke.sh <bazel-bin>
set -eu
BIN=$1
OS=$(uname -s)

# helper は /usr/lib/mozc/mozc_server を起動する (base/system_util.cc の
# kMozcServerDir の既定)。そこへ置く。
mkdir -p /usr/lib/mozc
cp "$BIN/server/mozc_server" /usr/lib/mozc/mozc_server
cp "$BIN/unix/emacs/mozc_emacs_helper" /usr/local/bin/mozc_emacs_helper
chmod 755 /usr/lib/mozc/mozc_server /usr/local/bin/mozc_emacs_helper

U=mozcsmoke
case "$OS" in
FreeBSD|GhostBSD|HardenedBSD|MidnightBSD|DragonFly) pw useradd "$U" -m -s /bin/sh 2>/dev/null || true ;;
Linux)
	# Alpine の busybox は useradd を持たない。adduser -D で password 無し。
	if command -v useradd >/dev/null 2>&1; then useradd -m -s /bin/sh "$U" 2>/dev/null || true
	else adduser -D -s /bin/sh "$U" 2>/dev/null || true; fi ;;
*) useradd -m -s /bin/sh "$U" 2>/dev/null || true ;;
esac
id "$U"

# n i h o n g o を一打ずつ、最後に space で変換。(EVENT_ID SendKey SESSION_ID KEY)
# の KEY は ASCII code か key symbol。入出力は user の home に置く。
H=$(eval echo "~$U")
# mozc は profile を ~/.config/mozc に作るが、その mkdir は親を作らない。
# 作りたての user の home には ~/.config が無く、
#   Failed to create directory: .../.config/mozc: mkdir failed
# から .session.ipc が読めず session-error になる (FreeBSD / NetBSD / OpenBSD
# の三つとも)。実際の利用者の home には desktop が作った ~/.config が在る。
mkdir -p "$H/.config"; chown "$U" "$H/.config"
IN=$H/smoke-in; OUT=$H/smoke-out; ERR=$H/smoke-err
{
	echo '(1 CreateSession)'
	n=2
	for k in 110 105 104 111 110 103 111 32; do
		echo "($n SendKey 1 $k)"; n=$((n+1))
	done
	echo "($n DeleteSession 1)"
} > "$IN"
chown "$U" "$IN"
rm -f "$OUT" "$ERR"
su -l "$U" -c "/usr/local/bin/mozc_emacs_helper < $IN > $OUT 2> $ERR" || true
echo "=== helper の応答 ($(wc -l < "$OUT" | tr -d ' ') 行)"
cut -c1-300 "$OUT"
echo "=== stderr"; head -20 "$ERR"
if grep -q '日本語' "$OUT"; then
	echo "RESULT mozc-smoke $OS OK: にほんご を変換して 日本語 が候補に出た"
else
	echo "RESULT mozc-smoke $OS NG: 日本語 が出ない"
	if grep -q 'session-error' "$OUT"; then
		echo '  (session-error: server に繋げていない。IPC か run_level)'
	fi
	exit 1
fi
