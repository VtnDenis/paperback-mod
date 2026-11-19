#!/bin/bash
# Builds mod/PaperbackMod.dylib for arm64 iOS without the theos iOS toolchain
# (it isn't available for Linux): Logos -> clang -c -> ld64.lld.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export THEOS="${THEOS:-$HOME/theos}"
export PATH="/usr/local/swift/usr/bin:$PATH"
SDK="$THEOS/sdks/iPhoneOS16.5.sdk"
TC="$THEOS/toolchain/linux/iphone/bin"

# The swift toolchain's ld64.lld only links x86_64 Mach-O; Ubuntu's lld package
# does arm64. Keep a private copy.
LLVM_DIR="$HOME/.local/llvm21"
mkdir -p "$LLVM_DIR"
if [ ! -x "$LLVM_DIR/bin/ld64.lld" ]; then
  mkdir -p "$HOME/.cache/lld"
  ( cd "$HOME/.cache/lld" || exit 1
    apt-get download lld-21 >/dev/null 2>&1 || apt-get download lld-20 >/dev/null 2>&1 || apt-get download lld >/dev/null 2>&1
    for d in *.deb; do dpkg-deb -x "$d" x; done
    src="$(ls -d "$HOME/.cache/lld/x/usr/lib/llvm-"* | head -1)"
    cp -r "$src/." "$LLVM_DIR/" )
fi
LLD="$LLVM_DIR/bin/ld64.lld"
mkdir -p "$TC"
ln -sf "$LLD" "$TC/ld64.lld"
ln -sf "$LLD" "$TC/ld"

# substrate.h includes <CydiaSubstrate/CydiaSubstrate.h>; the vendored copy lives
# in the framework, so expose it under the name the header expects.
mkdir -p "$THEOS/vendor/include/CydiaSubstrate"
ln -sf "$THEOS/vendor/lib/CydiaSubstrate.framework/Headers/CydiaSubstrate.h" \
       "$THEOS/vendor/include/CydiaSubstrate/CydiaSubstrate.h"

cd "$ROOT/mod" || exit 1
mkdir -p obj
CFLAGS="-target arm64-apple-ios13.0 -isysroot $SDK -fobjc-arc -fmodules -I. -I$THEOS/include -I$THEOS/vendor/include -I$THEOS/vendor/lib/CydiaSubstrate.framework/Headers -O2 -c"
# Source list comes from the makefile so it can't drift out of sync.
OBJS=""
for f in $(sed -n 's/^PaperbackMod_FILES *:= *//p' Makefile); do
  base="${f%.*}"
  case "$f" in
    *.xm) perl "$THEOS/bin/logos.pl" "$f" > "obj/$base.mm"
          clang $CFLAGS -o "obj/$base.o" "obj/$base.mm" ;;
    *)    clang $CFLAGS -o "obj/$base.o" "$f" ;;
  esac
  OBJS="$OBJS obj/$base.o"
done

"$LLD" -arch arm64 -platform_version ios 13.0 16.5 -dylib \
  -syslibroot "$SDK" -o PaperbackMod.dylib \
  -install_name @executable_path/PaperbackMod.dylib \
  -undefined dynamic_lookup \
  $OBJS \
  -framework UIKit -framework Foundation -framework UserNotifications -framework AVFoundation

echo "built $(ls -l PaperbackMod.dylib | awk '{print $5}') bytes"
