#!/bin/sh -e

# Android 'iptables' with 'xt_cgroup' support.
# Works on kernel built with 'CONFIG_NETFILTER_XT_MATCH_CGROUP'

# Android disables 'xt_cgroup' extension: https://android.googlesource.com/platform/external/iptables/+/refs/tags/android-15.0.0_r1/extensions/Android.bp#48
# Android specific changes: https://android.googlesource.com/platform/external/iptables/+/2bf769bb24c2ecf2ffac37773c1656cc15b654dd

# 'nftables' support requires 'libmnl' and 'libnftnl'
# 'connlabel' support requires 'libnetfilter_conntrack' and 'libnfnetlink'

# "quota2" module is not part of mainline iptables, but Android only.

[ "$ANDROID_NDK" ]

BIN="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
AR="$BIN/llvm-ar"
STRIP="$BIN/llvm-strip"

# O_PATH is defined in /usr/include/asm-generic/fcntl.h
sed -i 's/\bO_PATH\b/_O_PATH/g' extensions/libxt_cgroup.c

IPTABLES_DEFAULTS="-D_LARGEFILE_SOURCE=1 -D_LARGE_FILES -D_FILE_OFFSET_BITS=64 -D_REENTRANT -DENABLE_IPV4 -Wall -Werror -Wno-pointer-arith -Wno-sign-compare -Wno-unused-parameter -I$(pwd)/include"

LIBXT_DEFAULTS="$IPTABLES_DEFAULTS -I.. -DNO_SHARED_LIBS=1 -DXTABLES_INTERNAL -Wno-format -Wno-missing-field-initializers -Wno-tautological-pointer-compare"

cd extensions

# libext4.a
LIBIPT_SRC="libipt_*.c"
./gen_init '4' $LIBIPT_SRC > initext4.c
for f in $LIBIPT_SRC; do ./filter_init $f >_$f; done
LIBIPT_SRC="_libipt_*.c initext4.c"

# libext.a
LIBXT_SRC=$(echo libxt_*.c | sed 's| libxt_connlabel.c | |')
./gen_init '' $LIBXT_SRC >initext.c
for f in $LIBXT_SRC; do ./filter_init $f >_$f; done
LIBXT_SRC="_libxt_*.c initext.c"

unset f
cd ..

set -x

build() {
	CC="$BIN/${1}29-clang -Wextra"
	OUT_DIR="out/$2"

	# libxtables.a
	cd libxtables
	$CC -c -fPIC $IPTABLES_DEFAULTS -I../iptables -I.. -DNO_SHARED_LIBS=1 -DXTABLES_INTERNAL -DXTABLES_LIBDIR='"xtables_libdir_not_used"' -Wno-missing-field-initializers xtables.c xtoptions.c
	$AR rcs libxtables.a xtables.o xtoptions.o

	# libext4.a
	cd ../extensions
	$CC -c -fPIC $LIBXT_DEFAULTS $LIBIPT_SRC
	$AR rcs libext4.a $(echo $LIBIPT_SRC | sed 's|\.c\b|.o|g')

	# libext.a
	$CC -c -fPIC $LIBXT_DEFAULTS $LIBXT_SRC
	$AR rcs libext.a $(echo $LIBXT_SRC | sed 's|\.c\b|.o|g')

	# libip4tc.a
	cd ../libiptc
	$CC -c -fPIC $IPTABLES_DEFAULTS -Wno-pointer-sign libip4tc.c
	$AR rcs libip4tc.a libip4tc.o

	# iptables
	cd ../iptables
	mkdir -p ../$OUT_DIR
	$CC -pie $IPTABLES_DEFAULTS -Wno-missing-field-initializers -Wno-parentheses-equality -DNO_SHARED_LIBS=1 -DALL_INCLUSIVE -DXTABLES_INTERNAL -I.. xtables-legacy-multi.c iptables-xml.c xshared.c iptables-save.c iptables-restore.c iptables-standalone.c iptables.c -lext -lext4 -L../extensions -lxtables -L../libxtables -lip4tc -L../libiptc -lm -o ../$OUT_DIR/iptables
	$STRIP -s -S --strip-unneeded ../$OUT_DIR/iptables

	cd ..
}

build aarch64-linux-android arm64-v8a
build armv7a-linux-androideabi armeabi-v7a
build i686-linux-android x86
build x86_64-linux-android x86_64
