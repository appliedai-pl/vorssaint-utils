#!/bin/zsh

set -euo pipefail
cd "$(dirname "$0")/.."
architecture_test_dir=$(mktemp -d)
trap 'command rm -rf "$architecture_test_dir"' EXIT

sed -n '/^DEV=0$/,/^if (( DEV )); then$/p' build.sh \
    | sed '$d' > "$architecture_test_dir/architecture.zsh"
[[ -s "$architecture_test_dir/architecture.zsh" ]]

uname() { print -r -- "$TEST_HOST_ARCH"; }
sysctl() { print -r -- "$TEST_ARM64_AVAILABLE"; }

for TEST_HOST_ARCH in arm64 x86_64; do
    TEST_ARM64_AVAILABLE=0
    [[ "$TEST_HOST_ARCH" == arm64 ]] && TEST_ARM64_AVAILABLE=1
    (
        set --
        source "$architecture_test_dir/architecture.zsh"
        [[ "$BUILD_ARCH" == "$TEST_HOST_ARCH" ]]
        [[ "$TARGET" == "$TEST_HOST_ARCH-apple-macosx14.0" ]]
    )
    for target_arch in arm64 x86_64; do
        (
            set -- --arch="$target_arch" --test-suite=metrics
            source "$architecture_test_dir/architecture.zsh"
            [[ "$BUILD_ARCH" == "$target_arch" ]]
            [[ "$TARGET" == "$target_arch-apple-macosx14.0" ]]
            [[ "$TEST" == 1 && "${TEST_ARGS[*]}" == --suite=metrics ]]
        )
    done
done

(
    TEST_HOST_ARCH=x86_64
    TEST_ARM64_AVAILABLE=1
    set --
    source "$architecture_test_dir/architecture.zsh"
    [[ "$BUILD_ARCH" == arm64 && "$TARGET" == arm64-apple-macosx14.0 ]]
)

for invalid_arch in i386 unsupported ''; do
    if (
        set -- --arch="$invalid_arch"
        source "$architecture_test_dir/architecture.zsh"
    ); then
        print -u2 -- "Invalid architecture was accepted: $invalid_arch"
        exit 1
    fi
done

sed -n '/^APP_OBJECT_DIR=/,/^echo "▸ Compiling protected fan helper…"$/p' build.sh \
    | sed '$d' > "$architecture_test_dir/compile-app.zsh"
sed -n '/^    TEST_OBJECT_DIR=/,/^    TEST_SOURCES=(/p' build.sh \
    | sed '$d' > "$architecture_test_dir/test-directory.zsh"
sed -n '/^    TEST_OUTPUT_FILE_MAP=/,/^    test_status=0$/p' build.sh \
    | sed '$d' > "$architecture_test_dir/compile-tests.zsh"
for section in compile-app test-directory compile-tests; do
    [[ -s "$architecture_test_dir/$section.zsh" ]]
done

(
    cd "$architecture_test_dir"
    EXECUTABLE=Vorssaint
    APP_SOURCES=(fixture.swift)
    TEST_SOURCES=(fixture.swift)
    APP_OPTIMIZATION_FLAGS=(-Onone)
    SDK=fixture-sdk
    SDK_COMPAT_FLAGS=()
    VM_STATISTICS_COMPAT_FLAGS=()
    HID_EVENT_SYSTEM_FLAGS=()
    BUILD_VARIANT_FLAGS=()
    write_swift_output_file_map() { true; }
    swiftc() {
        local output_file='' compile_target=''
        while (( $# )); do
            case "$1" in
                -o) output_file="$2"; shift 2 ;;
                -target) compile_target="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        [[ -n "$output_file" && -n "$compile_target" ]]
        [[ -f "$output_file" ]] || print -r -- "$compile_target" > "$output_file"
    }
    for BUILD_ARCH in arm64 x86_64 arm64 x86_64; do
        TARGET="$BUILD_ARCH-apple-macosx14.0"
        source "$architecture_test_dir/compile-app.zsh"
        [[ "$(cat build/Vorssaint)" == "$TARGET" ]]
        source "$architecture_test_dir/test-directory.zsh"
        source "$architecture_test_dir/compile-tests.zsh"
        [[ "$(cat build/metrics-tests)" == "$TARGET" ]]
    done
)
print 'BUILD ARCHITECTURE TESTS OK'
