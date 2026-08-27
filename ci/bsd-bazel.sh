#!/bin/sh
# BSD の VM の中で走る。bazel 9 を用意してから、それで mozc を建てる。
#
# mozc 3.34 は bazel 9 でしか建たない。BSD のうち、それを package で配って
# いるのは FreeBSD だけ (ports の devel/bazel9) で、NetBSD の pkgsrc は
# 6.4.0 まで、OpenBSD と DragonFly には bazel が一本も無い。
#
# 無い側は、移植した木から建てて /usr/local/bin へ置く。置き場を分けるのは
# package が入っている箱と手順を揃えるためで、この下から先は
# 「bazel がある BSD」として同じ道を通る。
set -e

BAZEL_REPO=${BAZEL_REPO:-https://github.com/zakinko/bazel.git}
BAZEL_BRANCH=${BAZEL_BRANCH:-netbsd-ci}
MOZC_SRC=$(pwd)/src

# NetBSD の /tmp は 2GB の tmpfs で、bazel の output base も dist の展開も
# 入らない。空いている方を選ぶ。
WORK=${WORK:-/var/tmp/mozc-ci}
mkdir -p "$WORK"
TMPDIR="$WORK/tmp"
export TMPDIR
mkdir -p "$TMPDIR"

echo "=== 箱"
uname -a
df -h /tmp /var/tmp /usr/local 2>/dev/null | head -6

if command -v bazel >/dev/null 2>&1; then
	echo "=== bazel は入っている"
	BAZEL=$(command -v bazel)
else
	echo "=== bazel が無いので建てる"
	cd "$WORK"
	[ -d bazel ] || git clone --depth=1 -b "$BAZEL_BRANCH" "$BAZEL_REPO" bazel
	cd "$WORK/bazel"
	env SRCDIR="$WORK/bazel" \
	    WORK="$WORK/bazel-dist" \
	    WORK_FORCED=1 \
	    sh ci/bsd-bootstrap.sh
	# 一本の自己展開バイナリなので、置くだけでよい。
	mkdir -p /usr/local/bin
	cp "$WORK/bazel-dist/output/bazel" /usr/local/bin/bazel
	chmod 755 /usr/local/bin/bazel
	BAZEL=/usr/local/bin/bazel
fi

"$BAZEL" --version

echo "=== mozc を建てる"
cd "$MOZC_SRC"
# rules_python が配る interpreter は Linux と macOS と Windows の分だけなので、
# BSD には箱に入っている python を使わせる。
"$BAZEL" --output_user_root="$WORK/bazel-user-root" \
	build unix/emacs:mozc_emacs_helper \
	--config oss_linux \
	--compilation_mode opt \
	--jobs 2 \
	--action_env=PATH="$PATH" \
	--host_action_env=PATH="$PATH" \
	--extra_toolchains=@rules_python//python/runtime_env_toolchains:all \
	--verbose_failures

ls -l bazel-bin/unix/emacs/mozc_emacs_helper
