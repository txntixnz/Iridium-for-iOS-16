#!/bin/bash
# Build and link the real DXBC translator for iOS 16; not an IPA or shader-output validation.
set -euo pipefail
ROOT="$(pwd)"
[ -f "$ROOT/ci/runtime-inputs.json" ] || { echo 'Run from the patched upstream checkout.' >&2; exit 2; }
[ "$(uname -s)" = Darwin ] || { echo 'Requires macOS with Xcode.' >&2; exit 2; }
JOBS="${IRIDIUM_BUILD_JOBS:-3}"
case "$JOBS" in ''|*[!0-9]*|0) echo 'IRIDIUM_BUILD_JOBS must be positive.' >&2; exit 2;; esac
OUT="$ROOT/.build/ios16-shader-runtime"
mkdir -p "$OUT"
exec > >(tee "$OUT/build.log") 2>&1
MADEIRA="$ROOT/testrepos/Madeira"
LLVM="$MADEIRA/toolchains/llvm-project/llvm"
DXMT="$MADEIRA/research/dxmt"
HOST="$OUT/llvm-host"
IOS="$OUT/llvm-ios"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
# The upstream fetcher verifies the pinned LLVM 15.0.7 archive SHA-256.
python3 ci/fetch-runtime-inputs.py --only llvm
# Same LLVM 15 iOS CMake correction as the production native preparation.
python3 - "$LLVM/cmake/modules/AddLLVM.cmake" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); s = p.read_text()
if s.count('MATCHES "Darwin"') != 2:
    raise SystemExit('Unexpected LLVM CMake input')
p.write_text(s.replace('MATCHES "Darwin"', 'MATCHES "Darwin|iOS"'))
PY
options=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  -DLLVM_TARGETS_TO_BUILD= -DLLVM_ENABLE_PROJECTS= -DLLVM_ENABLE_ASSERTIONS=OFF
  -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF
  -DLLVM_INCLUDE_DOCS=OFF -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF
  -DLLVM_ENABLE_TERMINFO=OFF -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_CURL=OFF
  -DLLVM_ENABLE_FFI=OFF -DLLVM_ENABLE_EH=OFF -DLLVM_ENABLE_RTTI=OFF)
cmake -S "$LLVM" -B "$HOST" "${options[@]}"
cmake --build "$HOST" --target llvm-tblgen --parallel "$JOBS"
cmake -S "$LLVM" -B "$IOS" "${options[@]}" \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
  -DCMAKE_C_FLAGS='-Werror=unguarded-availability -Werror=unguarded-availability-new' \
  -DCMAKE_CXX_FLAGS='-Werror=unguarded-availability -Werror=unguarded-availability-new' \
  -DLLVM_TABLEGEN="$HOST/bin/llvm-tblgen" -DLLVM_BUILD_UTILS=OFF \
  -DLLVM_INCLUDE_TOOLS=OFF -DLLVM_INCLUDE_UTILS=OFF
cmake --build "$IOS" --target LLVMPasses LLVMBitWriter --parallel "$JOBS"
mkdir -p "$OUT/headers" "$OUT/objects"
if ! xcrun --sdk iphoneos metal --version; then
  xcodebuild -downloadComponent MetalToolchain
fi
for name in air_msad air_samplepos air_tessellation; do
  xcrun --sdk iphoneos metal -std=metal3.0 --target=air64-apple-ios16.0 \
    -c "$DXMT/src/airconv/shaders/$name.metal" -o "$OUT/headers/$name.air"
  xxd -n "$name" -i "$OUT/headers/$name.air" "$OUT/headers/$name.h"
done
common=(-target arm64-apple-ios16.0 -isysroot "$SDK" -O2 -fblocks -std=c++20 -fno-rtti
  -Werror=unguarded-availability -Werror=unguarded-availability-new
  -D_FILE_OFFSET_BITS=64 -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS
  -I "$DXMT/include" -I "$DXMT/libs" -I "$DXMT/src/winemetal" -I "$DXMT/src/airconv"
  -I "$DXMT/include/native/directx" -I "$DXMT/include/native/windows"
  -I "$OUT/headers" -I "$IOS/include" -I "$LLVM/include")
failures=0
printf 'unit\tresult\n' > "$OUT/summary.tsv"
compile() {
  local source="$1" name="$2" exceptions="$3"
  rm -f "$OUT/objects/$name.o"
  if xcrun --sdk iphoneos clang++ "${common[@]}" "$exceptions" \
    -c "$source" -o "$OUT/objects/$name.o" > "$OUT/$name.log" 2>&1; then
    printf '%s\tPASS\n' "$name" | tee -a "$OUT/summary.tsv"
  else
    printf '%s\tFAIL\n' "$name" | tee -a "$OUT/summary.tsv"
    cat "$OUT/$name.log"
    failures=$((failures + 1))
  fi
}
for unit in airconv_context air_type air_signature air_operations dxbc_converter \
  dxbc_converter_gs dxbc_converter_ts dxbc_converter_basicblock dxbc_converter_cfg \
  dxbc_instructions dxbc_signature metallib_writer nt/air_builder nt/dxbc_converter_base \
  transforms/lower_16bit_texread; do
  compile "$DXMT/src/airconv/$unit.cpp" "${unit##*/}" -fno-exceptions
done
for unit in BlobContainer DXBCUtils ShaderBinary; do
  compile "$DXMT/libs/DXBCParser/$unit.cpp" "dxbc_$unit" -fexceptions
done
[ "$failures" -eq 0 ] || { echo "$failures translator units failed."; exit 1; }
# Force all translator objects into a real Mach-O link, with no undefined-symbol
# suppression. This catches dependency failures hidden by a static archive alone.
xcrun --sdk iphoneos libtool -static -o "$OUT/libairconv-ios16.a" "$OUT/objects/"*.o
xcrun --sdk iphoneos clang++ -target arm64-apple-ios16.0 -isysroot "$SDK" \
  -dynamiclib -Wl,-undefined,error -Wl,-force_load,"$OUT/libairconv-ios16.a" \
  "$IOS/lib/"*.a -framework Foundation -o "$OUT/airconv-link-check.dylib" \
  -Wl,-map,"$OUT/link.map"
xcrun otool -l "$OUT/airconv-link-check.dylib" > "$OUT/load-commands.log"
xcrun otool -L "$OUT/airconv-link-check.dylib" > "$OUT/dependencies.log"
xcrun nm -u "$OUT/airconv-link-check.dylib" > "$OUT/imports.log"
python3 - "$OUT/load-commands.log" <<'PY'
from pathlib import Path
import re, sys
s = Path(sys.argv[1]).read_text()
if not re.search(r'\bminos\s+16\.0\b', s):
    raise SystemExit('Linked diagnostic library does not declare the expected iOS 16.0 minimum')
PY
printf '%s\n' 'Translator compiled and linked for iOS 16.0.' \
  'Shader output is still upstream Metal 3.1/3.2. This does not prove Metal 3.0 shader execution.' \
  'No app, IPA, JIT, full runtime, or device compatibility is established.'
