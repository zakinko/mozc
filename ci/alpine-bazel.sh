#!/bin/sh
# Alpine (musl) で mozc を建てる。bazel は musl 向けの binary が配られていない
# ので、9.3.0rc2 の dist に musl の当て物 (unix_jni.h の stat64、singlejar の
# off64_t。bazelbuild/bazel へ出す物と同じ) を当てて先に建てる。
#
# 使い方: alpine-bazel.sh   (mozc の checkout の根で)
#
# musl は fts(3) を libc に持たない (musl-fts が別 package で、-lfts で繋ぐ)。
# base/file/recursive.cc が fts.h を要るので、それを入れて繋ぐ。
set -eu
MOZC_SRC=$PWD/src
CI_DIR=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-/var/tmp/alpine-bazel}
BAZEL_VER=${BAZEL_VER:-9.3.0rc2}
export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk}
"$JAVA_HOME/bin/javac" -version

if [ ! -x "$WORK/dist/output/bazel" ]; then
	echo "=== bazel $BAZEL_VER を musl の当て物で建てる"
	rm -rf "$WORK"; mkdir -p "$WORK/dist"
	curl -fsSL -o "$WORK/dist.zip" "https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VER}/bazel-${BAZEL_VER}-dist.zip"
	( cd "$WORK/dist" && unzip -q ../dist.zip && patch -p1 -f -i "$CI_DIR/bazel-alpine-9.3.0.patch" </dev/null )
	( cd "$WORK/dist" && env EXTRA_BAZEL_ARGS="--java_runtime_version=local_jdk --tool_java_runtime_version=local_jdk" \
		bash ./compile.sh > compile.log 2>&1 ) || true
	[ -x "$WORK/dist/output/bazel" ] || { echo "bazel が建たない"; tail -40 "$WORK/dist/compile.log"; exit 1; }
fi
BAZEL=$WORK/dist/output/bazel
"$BAZEL" version | grep 'Build label'

echo "=== mozc を建てる"
cd "$MOZC_SRC"
"$BAZEL" --output_user_root="$WORK/user-root" \
	build unix/emacs:mozc_emacs_helper server:mozc_server \
	--config oss_linux \
	--compilation_mode opt \
	--jobs 2 \
	--java_runtime_version=local_jdk --tool_java_runtime_version=local_jdk \
	--action_env=PATH="$PATH" --host_action_env=PATH="$PATH" \
	--extra_toolchains=@rules_python//python/runtime_env_toolchains:all \
	--linkopt=-lfts --host_linkopt=-lfts \
	--verbose_failures
ls -l bazel-bin/unix/emacs/mozc_emacs_helper bazel-bin/server/mozc_server
sh "$CI_DIR/bsd-smoke.sh" "$(cd bazel-bin && pwd)"
