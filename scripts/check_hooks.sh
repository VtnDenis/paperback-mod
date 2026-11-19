#!/bin/bash
# Confirms the Logos constructor still runs _logosLocalInit, i.e. the %hooks
# are installed at load time.
set -e
ROOT="$(cd "$(dirname "cd "$ROOT/mod"")/.." && pwd)"\ncd "$ROOT/mod"
NM=/usr/local/swift/usr/bin/llvm-nm
OBJDUMP=/usr/local/swift/usr/bin/llvm-objdump
SYM=$("$NM" PaperbackMod.dylib | grep -o '__ZL24_logosLocalCtor[^ ]*' | head -1)
echo "ctor: $SYM"
"$OBJDUMP" --macho --disassemble --disassemble-symbols="$SYM" PaperbackMod.dylib \
  | grep -E 'bl|b\t' | grep -iE 'logosLocalInit|MSHook' || echo "NO _logosLocalInit CALL"
