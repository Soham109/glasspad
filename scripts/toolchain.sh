# Shared toolchain detection for scripts/test.sh and scripts/build-mac.sh. Source it, do not run it.
# Sets GP_SWIFT_FLAGS: extra swift flags needed when the active developer dir is the
# command line tools (swift-testing lives in a framework folder that is not on the default path).
# An existing DEVELOPER_DIR always wins over xcode-select.
GP_DEV_DIR="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
GP_SWIFT_FLAGS=()
case "$GP_DEV_DIR" in
  *CommandLineTools*)
    F="$GP_DEV_DIR/Library/Developer/Frameworks"
    GP_SWIFT_FLAGS=(-Xswiftc "-F$F" -Xlinker "-F$F" -Xlinker -rpath -Xlinker "$F")
    ;;
esac
export GP_DEV_DIR

# Build products live outside the repo: this checkout sits in an iCloud-synced Desktop, and the
# file provider tags bundles with Finder info, which makes codesign refuse the test bundle
# ("resource fork, Finder information, or similar detritus not allowed").
# One folder per checkout, so parallel worktrees never share (and fight over) SwiftPM's build.
GP_CHECKOUT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd -P)"
GP_BUILD_ROOT="${GLASSPAD_BUILD_ROOT:-$HOME/Library/Caches/glasspad-build/$(basename "$GP_CHECKOUT")-$(printf %s "$GP_CHECKOUT" | shasum | cut -c1-8)}"
export GP_BUILD_ROOT
