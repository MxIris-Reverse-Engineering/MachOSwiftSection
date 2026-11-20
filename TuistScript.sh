#!/usr/bin/env bash
# TuistScript.sh — MachOSwiftSection-Tuist.xcworkspace, the development-only Tuist workspace: this
# package and the five upstream packages the native MachOSwiftSection.xcworkspace lists beside the
# checkout (MachOKit, MachOKitExtensions, MachOObjCSection, swift-demangling, swift-semantic-string)
# built from source, every other dependency taken from Tuist's binary cache on this machine, and the
# packages' tests mapped into schemes. Releases, CI, `swift build` / `swift test` and the native
# workspace do not use it. Documentations/Internal/TuistDevelopment.md explains the setup.
#
# Usage:
#   ./TuistScript.sh install                      # resolve the dependencies (tuist install)
#   ./TuistScript.sh generate [--configuration <c>]
#                                                 # generate MachOSwiftSection-Tuist.xcworkspace
#                                                 # against the binary cache of one configuration
#                                                 # (Debug or Release; default: Debug)
#   ./TuistScript.sh warm [--configuration <c>]   # build the third-party dependencies into the
#                                                 # binary cache of one configuration, then generate
#   ./TuistScript.sh build [--configuration <c>] [-- <xcodebuild arguments>]
#                                                 # generate, then build the swift-section scheme
#   ./TuistScript.sh test [--configuration <c>] [-- <xcodebuild arguments>]
#                                                 # generate, then run the "MachOSwiftSection Tests"
#                                                 # scheme; exits with xcodebuild's exit code
#   ./TuistScript.sh release                      # give up every checkout this one claimed: remove the
#                                                 # projects Tuist generated into them and the workspace
#   ./TuistScript.sh <command> --local-dependencies
#                                                 # from now on take the five upstream packages from
#                                                 # the checkouts beside this one (`.worktrees/` in a
#                                                 # worktree), uncommitted edits included
#   ./TuistScript.sh <command> --remote-dependencies
#                                                 # from now on take them at the lock file's pins again
#                                                 # (the default)
#   ./TuistScript.sh <command> --dry-run          # print what would run
#   ./TuistScript.sh --help
#
# The mode holds for the commands after the one that switched it ($LOCAL_DEPENDENCIES_MARKER records
# it). Each mode has its own dependency checkouts; switching resolves again. When the local mode is
# switched on, TUIST_LOCAL_PACKAGE_CHECKOUTS names another directory to take the upstream packages
# from, each in a directory named like the package.
#
# Tuist writes a project into every package declared by path — this checkout always, the upstream
# checkouts in the local mode — and RuntimeViewer's TuistScript.sh does the same into the same
# checkouts. Both scripts claim a checkout before generating into it (the claim record below), and
# refuse a checkout another one holds.
#
# Every command uses the Xcode that DEVELOPER_DIR or xcode-select names. Tuist's dependency
# checkouts, its binary cache and the build products live under /Volumes/DerivedData/MachOSwiftSection/
# Tuist when that volume is mounted, and inside the checkout otherwise; TUIST_SCRIPT_ROOT names another
# directory. `warm`, `build` and `test` compile: run them through queued-build where that applies.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_REAL_PATH="$(cd "$PROJECT_DIR" && pwd -P)"
cd "$PROJECT_DIR"

WORKSPACE="MachOSwiftSection-Tuist.xcworkspace"
NATIVE_WORKSPACE="MachOSwiftSection.xcworkspace"
PACKAGE_NAME="MachOSwiftSection"
BUILD_SCHEME="swift-section"
TEST_SCHEME="MachOSwiftSection Tests"
COMMAND_LINE_PROJECT_DIRECTORY="Tuist/CommandLine"
# The lock file SwiftPM and Xcode resolved for this checkout, not committed: Tuist starts from its pins.
SEED_LOCK_FILE="Package.resolved"
TUIST_PACKAGE_RESOLVED="Tuist/Package.resolved"
# Test targets no scheme lists: IntegrationTests is the maintainer's manual-inspection target.
UNLISTED_TEST_TARGETS="IntegrationTests"
# The local dependency mode: the file recording the directory the upstream packages are taken from
# (absent in the remote mode).
LOCAL_DEPENDENCIES_MARKER="Tuist/.local-dependencies"
# The claim record, shared with RuntimeViewer's TuistScript.sh. A claimed checkout's git directory
# holds $OWNER_RECORD_NAME: the owner checkout's path, the command that releases the claim there, and
# the project Tuist generated into the claimed checkout. The owner lists the real paths it holds in
# its $CLAIMED_CHECKOUTS_FILE; a claim is live only while that list holds the claimed checkout.
OWNER_RECORD_NAME="tuist-generated-project-owner"
CLAIMED_CHECKOUTS_FILE="Tuist/.claimed-checkouts"
RELEASE_COMMAND="./TuistScript.sh release"
# RuntimeViewer's record before the shared one: live while its owner's Tuist/.local-dependencies,
# joined with the package's name, is the claimed checkout.
LEGACY_OWNER_RECORD_NAME="runtimeviewer-tuist-local-dependencies"
EXCLUDE_COMMENT="# Generated by MachOSwiftSection's TuistScript.sh"

COMMAND=""
CONFIGURATION="Debug"
DRY_RUN=false
REQUESTED_DEPENDENCY_MODE=""
EXTRA_ARGUMENTS=()

fail() { echo "error: $*" >&2; exit 1; }
log()  { echo "[TuistScript] $*"; }
warn() { echo "[TuistScript] warning: $*" >&2; }

run() {
    if $DRY_RUN; then
        printf '+ '; printf '%q ' "$@"; echo
    else
        "$@"
    fi
}

# Runs a command with its output in a log under $LOG_DIR, echoing only its errors and last lines when
# it fails. For xcodebuild, whose output runs to thousands of lines. Returns the command's exit code.
run_logged() {
    local log_name="$1"; shift
    if $DRY_RUN; then
        printf '+ '; printf '%q ' "$@"; printf '> %q\n' "$LOG_DIR/$log_name.log"
        return 0
    fi
    mkdir -p "$LOG_DIR"
    local log_path="$LOG_DIR/$log_name.log"
    log "  log: $log_path"
    local exit_code=0
    "$@" > "$log_path" 2>&1 || exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        grep -E 'error:|✘|failed' "$log_path" | head -20 | sed 's/^/    /' >&2 || true
        tail -5 "$log_path" | sed 's/^/    /' >&2
    fi
    return $exit_code
}

# Runs a Tuist command with its output on the terminal as well as in a log under $LOG_DIR. On a
# terminal it runs under script(1), which keeps Tuist's colors; anywhere else through tee. Returns the
# command's own exit code either way.
run_tuist() {
    local log_name="$1"; shift
    if $DRY_RUN; then
        printf '+ '; printf '%q ' "$@"; printf '| tee %q\n' "$LOG_DIR/$log_name.log"
        return 0
    fi
    mkdir -p "$LOG_DIR"
    local log_path="$LOG_DIR/$log_name.log"
    log "  log: $log_path"
    local exit_code=0
    if [[ -t 0 && -t 1 ]]; then
        script -q "$log_path" "$@" || exit_code=$?
    else
        "$@" 2>&1 | tee "$log_path" || exit_code=${PIPESTATUS[0]}
    fi
    return $exit_code
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        install|generate|warm|build|test|release)
            [[ -z "$COMMAND" ]] || fail "one command at a time: $COMMAND, $1"
            COMMAND="$1"; shift;;
        --configuration)
            [[ $# -ge 2 ]] || fail "--configuration needs a name (Debug or Release)"
            CONFIGURATION="$2"; shift 2;;
        --local-dependencies|--remote-dependencies)
            [[ -z "$REQUESTED_DEPENDENCY_MODE" ]] || fail "one of --local-dependencies and --remote-dependencies at a time"
            REQUESTED_DEPENDENCY_MODE="${1#--}"; REQUESTED_DEPENDENCY_MODE="${REQUESTED_DEPENDENCY_MODE%-dependencies}"; shift;;
        --dry-run) DRY_RUN=true; shift;;
        --) shift; EXTRA_ARGUMENTS=("$@"); break;;
        -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0;;
        *) fail "unknown argument: $1 (see --help)";;
    esac
done
[[ -n "$COMMAND" ]] || fail "no command given (see --help)"
case "$CONFIGURATION" in
    Debug|Release) ;;
    *) fail "unknown configuration: $CONFIGURATION (expected Debug or Release)";;
esac
if [[ ${#EXTRA_ARGUMENTS[@]} -gt 0 && "$COMMAND" != build && "$COMMAND" != test ]]; then
    fail "only build and test pass arguments on to xcodebuild"
fi

# One directory per checkout: two worktrees must not share Tuist's dependency checkouts, which record
# where the packages declared by path are. The binary cache is shared; it is keyed by content.
CHECKOUT_NAME="$(basename "$PROJECT_DIR")-$(printf '%s' "$PROJECT_DIR" | shasum | cut -c1-8)"
if [[ -n "${TUIST_SCRIPT_ROOT:-}" ]]; then
    STORAGE_ROOT="$TUIST_SCRIPT_ROOT"
elif [[ -d "/Volumes/DerivedData" ]]; then
    STORAGE_ROOT="/Volumes/DerivedData/MachOSwiftSection/Tuist"
else
    STORAGE_ROOT=""
fi
if [[ -n "$STORAGE_ROOT" ]]; then
    export TUIST_XDG_CACHE_HOME="$STORAGE_ROOT/Cache"
    export TUIST_CACHE_WARM_SCRATCH_DIRECTORY="$STORAGE_ROOT/WarmScratch/$CHECKOUT_NAME"
    WORK_ROOT="$STORAGE_ROOT/Work/$CHECKOUT_NAME"
else
    WORK_ROOT="$PROJECT_DIR/DerivedData/Tuist"
fi
LOG_DIR="${LOG_DIR:-$PROJECT_DIR/Products/Logs/Tuist}"
# What the dependencies were last resolved for: the mode and the manifests. The two modes share
# Tuist/Package.resolved, so running in the other one, or after a manifest changed, resolves again.
INSTALLED_DEPENDENCIES_STAMP="$WORK_ROOT/InstalledDependencies"
# Every package's evaluated manifest, read once per install (dump_manifests).
MANIFESTS_DIRECTORY="$WORK_ROOT/Manifests"

# The manifests choose local checkouts or remote packages by this variable, for every package at
# once, swift-capstone included. The upstream packages come from their checkouts through
# --local-dependencies instead.
if [[ -n "${USING_LOCAL_DEPENDENCIES:-}" ]]; then
    warn "ignoring USING_LOCAL_DEPENDENCIES=$USING_LOCAL_DEPENDENCIES; --local-dependencies takes the upstream packages from their checkouts"
    unset USING_LOCAL_DEPENDENCIES
fi

# The Tuist that mise.toml pins: through mise when it is installed, from PATH otherwise.
PINNED_TUIST_VERSION="$(sed -n 's/^tuist *= *"\(.*\)"$/\1/p' mise.toml)"
if command -v mise >/dev/null 2>&1; then
    TUIST=(mise exec -- tuist)
elif command -v tuist >/dev/null 2>&1; then
    TUIST=(tuist)
else
    fail "Tuist not found. Install mise (https://mise.jdx.dev) and run \`mise install\` here, or install Tuist $PINNED_TUIST_VERSION."
fi
if ! $DRY_RUN; then
    tuist_version="$("${TUIST[@]}" version 2>/dev/null | tail -1)" || fail "\`${TUIST[*]} version\` failed; run \`mise install\` here"
    [[ "$tuist_version" == "$PINNED_TUIST_VERSION" ]] \
        || fail "Tuist $tuist_version found, mise.toml pins $PINNED_TUIST_VERSION; run \`mise install\` here"
fi

command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild not found"
command -v python3 >/dev/null 2>&1 || fail "python3 not found (the script reads the manifests with it)"

# The upstream packages the local mode takes from their checkouts: the members of the native
# workspace beside the checkout (`container:../<name>`), so a package added there is local here too.
read_local_package_names() {
    python3 - "$PROJECT_DIR/$NATIVE_WORKSPACE/contents.xcworkspacedata" <<'PYTHON'
import sys
import xml.etree.ElementTree as ElementTree

prefix = "container:../"
for element in ElementTree.parse(sys.argv[1]).getroot().iter("FileRef"):
    location = element.get("location", "")
    if location.startswith(prefix) and "/" not in location[len(prefix):]:
        print(location[len(prefix):])
PYTHON
}

LOCAL_PACKAGE_NAMES=()
local_package_names_output="$(read_local_package_names)" \
    || fail "cannot read which packages $NATIVE_WORKSPACE takes from beside the checkout"
for package_name in $local_package_names_output; do
    LOCAL_PACKAGE_NAMES+=("$package_name")
done
[[ ${#LOCAL_PACKAGE_NAMES[@]} -gt 0 ]] || fail "$NATIVE_WORKSPACE takes no package from beside the checkout"

# --- The claim record -----------------------------------------------------------------------------

git_directory_of() {   # $1: a checkout; prints nothing when it is not a git checkout
    git -C "$1" rev-parse --absolute-git-dir 2>/dev/null || true
}

real_path_of() {
    (cd "$1" 2>/dev/null && pwd -P) || true
}

# Prints "<owner>\t<release command>" for a live claim another checkout holds on $1 (a checkout),
# $2 being the package's name; prints nothing when none does.
foreign_live_claim() {
    local checkout="$1" package_name="$2" git_directory checkout_real_path owner release_command owner_directory
    git_directory="$(git_directory_of "$checkout")"
    [[ -n "$git_directory" ]] || return 0
    checkout_real_path="$(real_path_of "$checkout")"
    if [[ -f "$git_directory/$OWNER_RECORD_NAME" ]]; then
        owner="$(sed -n 1p "$git_directory/$OWNER_RECORD_NAME")"
        release_command="$(sed -n 2p "$git_directory/$OWNER_RECORD_NAME")"
        if [[ -n "$owner" && "$(real_path_of "$owner")" != "$PROJECT_REAL_PATH" ]] \
            && grep -qxF -- "$checkout_real_path" "$owner/$CLAIMED_CHECKOUTS_FILE" 2>/dev/null; then
            printf '%s\t%s\n' "$owner" "${release_command:-its TuistScript.sh}"
            return 0
        fi
    fi
    if [[ -f "$git_directory/$LEGACY_OWNER_RECORD_NAME" ]]; then
        owner="$(sed -n 1p "$git_directory/$LEGACY_OWNER_RECORD_NAME")"
        if [[ -n "$owner" && "$(real_path_of "$owner")" != "$PROJECT_REAL_PATH" ]]; then
            owner_directory="$(cat "$owner/Tuist/.local-dependencies" 2>/dev/null || true)"
            if [[ -n "$owner_directory" && "$(real_path_of "$owner_directory/$package_name")" == "$checkout_real_path" ]]; then
                printf '%s\t%s\n' "$owner" "./TuistScript.sh generate --remote-dependencies"
            fi
        fi
    fi
}

# Claims $1 (a checkout) for this one before Tuist generates $3 into it; $2 is the package's name.
# Refuses a checkout another checkout's Tuist workspace holds and a project file git tracks. An upstream
# checkout's repository gets the generated files in its info/exclude, which stays on this Mac; this
# checkout ignores its own in .gitignore.
claim_checkout() {
    local checkout="$1" package_name="$2" project_name="$3" claim git_directory checkout_real_path exclude_file pattern
    git_directory="$(git_directory_of "$checkout")"
    [[ -n "$git_directory" ]] || return 0
    claim="$(foreign_live_claim "$checkout" "$package_name")"
    if [[ -n "$claim" ]]; then
        fail "$checkout is in the Tuist workspace of ${claim%%$'\t'*}, and generating here would replace the project that workspace uses; run \`${claim#*$'\t'}\` there first"
    fi
    if git -C "$checkout" ls-files --error-unmatch "$project_name.xcodeproj" >/dev/null 2>&1; then
        fail "$checkout tracks $project_name.xcodeproj, which Tuist would overwrite"
    fi
    checkout_real_path="$(real_path_of "$checkout")"
    if $DRY_RUN; then
        log "would claim $checkout_real_path ($project_name.xcodeproj)"
        return 0
    fi
    printf '%s\n%s\n%s\n' "$PROJECT_DIR" "$RELEASE_COMMAND" "$project_name.xcodeproj" > "$git_directory/$OWNER_RECORD_NAME"
    mkdir -p "$(dirname "$CLAIMED_CHECKOUTS_FILE")"
    grep -qxF -- "$checkout_real_path" "$CLAIMED_CHECKOUTS_FILE" 2>/dev/null \
        || printf '%s\n' "$checkout_real_path" >> "$CLAIMED_CHECKOUTS_FILE"
    if [[ "$checkout_real_path" != "$PROJECT_REAL_PATH" ]]; then
        exclude_file="$(git -C "$checkout" rev-parse --path-format=absolute --git-path info/exclude)"
        mkdir -p "$(dirname "$exclude_file")"
        for pattern in "$EXCLUDE_COMMENT" "/$project_name.xcodeproj/" "/Derived/"; do
            grep -qxF -- "$pattern" "$exclude_file" 2>/dev/null || printf '%s\n' "$pattern" >> "$exclude_file"
        done
    fi
}

# Gives up the claim on $1 (a checkout's real path) when this checkout holds it: removes the project
# Tuist generated there unless git tracks it, so that opening the folder in Xcode opens its
# Package.swift again, and the record. Derived/ stays; it changes nothing for Xcode.
release_checkout() {
    local checkout_real_path="$1" git_directory project_file_name remaining
    git_directory="$(git_directory_of "$checkout_real_path")"
    if [[ -n "$git_directory" && -f "$git_directory/$OWNER_RECORD_NAME" ]] \
        && [[ "$(real_path_of "$(sed -n 1p "$git_directory/$OWNER_RECORD_NAME")")" == "$PROJECT_REAL_PATH" ]]; then
        project_file_name="$(sed -n 3p "$git_directory/$OWNER_RECORD_NAME")"
        if [[ -n "$project_file_name" && "$project_file_name" == *.xcodeproj ]] \
            && ! git -C "$checkout_real_path" ls-files --error-unmatch "$project_file_name" >/dev/null 2>&1; then
            run rm -rf "$checkout_real_path/$project_file_name"
        fi
        run rm -f "$git_directory/$OWNER_RECORD_NAME"
    fi
    if [[ -f "$CLAIMED_CHECKOUTS_FILE" ]] && ! $DRY_RUN; then
        remaining="$(grep -vxF -- "$checkout_real_path" "$CLAIMED_CHECKOUTS_FILE" || true)"
        if [[ -n "$remaining" ]]; then
            printf '%s\n' "$remaining" > "$CLAIMED_CHECKOUTS_FILE"
        else
            rm -f "$CLAIMED_CHECKOUTS_FILE"
        fi
    fi
}

# Gives up every claim on a checkout other than this one: the upstream checkouts of the local mode.
release_upstream_checkouts() {
    local checkout_real_path
    [[ -f "$CLAIMED_CHECKOUTS_FILE" ]] || return 0
    while IFS= read -r checkout_real_path; do
        [[ -n "$checkout_real_path" && "$checkout_real_path" != "$PROJECT_REAL_PATH" ]] || continue
        release_checkout "$checkout_real_path"
    done < <(cat "$CLAIMED_CHECKOUTS_FILE")
}

# --- The dependency mode --------------------------------------------------------------------------

# Points this process at the dependencies of one mode ($1: local or remote). Each mode resolves into a
# directory of its own, so switching back and forth keeps both sets of checkouts.
use_dependency_mode() {
    CURRENT_DEPENDENCY_MODE="$1"
    local directory_suffix=""
    if [[ "$1" == local ]]; then
        directory_suffix="-LocalDependencies"
        export TUIST_LOCAL_PACKAGE_CHECKOUTS="$LOCAL_DEPENDENCIES_DIRECTORY"
        export TUIST_LOCAL_PACKAGE_NAMES
        TUIST_LOCAL_PACKAGE_NAMES="$(IFS=,; printf '%s' "${LOCAL_PACKAGE_NAMES[*]}")"
    else
        unset TUIST_LOCAL_PACKAGE_CHECKOUTS TUIST_LOCAL_PACKAGE_NAMES
    fi
    if [[ -n "$STORAGE_ROOT" ]]; then
        export SWIFTPM_BUILD_DIR="$STORAGE_ROOT/Dependencies/$CHECKOUT_NAME$directory_suffix"
    elif [[ -n "$directory_suffix" ]]; then
        export SWIFTPM_BUILD_DIR="$PROJECT_DIR/Tuist/.build$directory_suffix"
    else
        unset SWIFTPM_BUILD_DIR
    fi
    DEPENDENCIES_DIRECTORY="${SWIFTPM_BUILD_DIR:-$PROJECT_DIR/Tuist/.build}"
}

# The mode from now on: what --local-dependencies or --remote-dependencies asks for, or what
# $LOCAL_DEPENDENCIES_MARKER recorded the last time.
RECORDED_LOCAL_DEPENDENCIES_DIRECTORY="$(cat "$LOCAL_DEPENDENCIES_MARKER" 2>/dev/null || true)"
case "$REQUESTED_DEPENDENCY_MODE" in
    local) LOCAL_DEPENDENCIES_DIRECTORY="${TUIST_LOCAL_PACKAGE_CHECKOUTS:-$(dirname "$PROJECT_DIR")}";;
    remote) LOCAL_DEPENDENCIES_DIRECTORY="";;
    *) LOCAL_DEPENDENCIES_DIRECTORY="$RECORDED_LOCAL_DEPENDENCIES_DIRECTORY";;
esac
if [[ -n "$LOCAL_DEPENDENCIES_DIRECTORY" ]]; then
    resolved_directory="$(cd "$LOCAL_DEPENDENCIES_DIRECTORY" 2>/dev/null && pwd)" \
        || fail "no directory $LOCAL_DEPENDENCIES_DIRECTORY to take the local dependencies from (./TuistScript.sh <command> --remote-dependencies goes back to the remote packages)"
    LOCAL_DEPENDENCIES_DIRECTORY="$resolved_directory"
    for package_name in "${LOCAL_PACKAGE_NAMES[@]}"; do
        [[ -f "$LOCAL_DEPENDENCIES_DIRECTORY/$package_name/Package.swift" ]] \
            || fail "no package $package_name in $LOCAL_DEPENDENCIES_DIRECTORY. The local dependency mode takes the packages $NATIVE_WORKSPACE lists beside the checkout, from directories with the same names."
    done
    DEPENDENCY_MODE=local
else
    DEPENDENCY_MODE=remote
fi

# A switch gives up the upstream checkouts the old mode generated projects into and records the new
# mode; ensure_dependencies resolves again before Tuist next runs.
if [[ "$LOCAL_DEPENDENCIES_DIRECTORY" != "$RECORDED_LOCAL_DEPENDENCIES_DIRECTORY" ]]; then
    log "switching to the $DEPENDENCY_MODE dependencies"
    release_upstream_checkouts
    if $DRY_RUN; then
        log "would record the $DEPENDENCY_MODE mode in $LOCAL_DEPENDENCIES_MARKER"
    elif [[ "$DEPENDENCY_MODE" == local ]]; then
        printf '%s\n' "$LOCAL_DEPENDENCIES_DIRECTORY" > "$LOCAL_DEPENDENCIES_MARKER"
    else
        rm -f "$LOCAL_DEPENDENCIES_MARKER"
    fi
fi
use_dependency_mode "$DEPENDENCY_MODE"

# The manifests evaluate MACHO_SWIFT_SECTION_SILENT_TEST; the hand-written test target reads it as
# TUIST_SILENT_TEST, the only form a Tuist manifest sees.
if [[ "${MACHO_SWIFT_SECTION_SILENT_TEST:-}" == "1" ]]; then
    export TUIST_SILENT_TEST=1
else
    unset TUIST_SILENT_TEST
fi

log "command=$COMMAND configuration=$CONFIGURATION tuist=$PINNED_TUIST_VERSION"
log "xcode: $(xcodebuild -version | tr '\n' ' ')(${DEVELOPER_DIR:-$(xcode-select -p)})"
log "storage: ${STORAGE_ROOT:-inside the checkout} (dependencies: $DEPENDENCIES_DIRECTORY)"
if [[ "$DEPENDENCY_MODE" == local ]]; then
    log "upstream packages: the checkouts in $LOCAL_DEPENDENCIES_DIRECTORY (${LOCAL_PACKAGE_NAMES[*]})"
else
    log "upstream packages: the lock file's pins (--local-dependencies takes them from their checkouts)"
fi

# --- Resolving -----------------------------------------------------------------------------------

# Compares the pins of Tuist/Package.resolved with those of the seed lock file, leaving out the
# packages named in the arguments: swift-syntax, which Tuist takes from PrecompiledLibraries, and the
# local mode's packages, which have no pin when they are declared by path. Prints the differences and
# returns 1 when there are any.
compare_lock_files() {
    python3 - "$TUIST_PACKAGE_RESOLVED" "$SEED_LOCK_FILE" "$@" <<'PYTHON'
import json
import sys

def read_pins(path):
    with open(path) as handle:
        document = json.load(handle)
    pins = {}
    for pin in document.get("pins", []):
        state = pin.get("state", {})
        pins[pin["identity"]] = state.get("version") or f"{state.get('branch')}@{state.get('revision', '')[:8]}"
    return pins

tuist_path, seed_path = sys.argv[1:3]
left_out = {package_name.lower() for package_name in sys.argv[3:]}
try:
    tuist_pins, seed_pins = read_pins(tuist_path), read_pins(seed_path)
except OSError as error:
    print(f"    cannot compare the lock files: {error}")
    sys.exit(1)
differences = [
    f"    {identity}: Tuist {tuist_pins.get(identity, 'absent')}, {seed_path} {seed_pins.get(identity, 'absent')}"
    for identity in sorted((tuist_pins.keys() | seed_pins.keys()) - left_out)
    if tuist_pins.get(identity) != seed_pins.get(identity)
]
if differences:
    print("\n".join(differences))
    sys.exit(1)
PYTHON
}

# What $INSTALLED_DEPENDENCIES_STAMP says once the current mode's dependencies are resolved: the mode,
# and the manifests and seed lock file the resolution read.
installed_dependencies_description() {
    local package_name
    if [[ "$CURRENT_DEPENDENCY_MODE" == local ]]; then
        echo "local $LOCAL_DEPENDENCIES_DIRECTORY"
    else
        echo "remote"
    fi
    echo "silent test: ${MACHO_SWIFT_SECTION_SILENT_TEST:-}"
    shasum Tuist/Package.swift Package.swift 2>/dev/null || true
    [[ -f "$SEED_LOCK_FILE" ]] && shasum "$SEED_LOCK_FILE"
    if [[ "$CURRENT_DEPENDENCY_MODE" == local ]]; then
        for package_name in "${LOCAL_PACKAGE_NAMES[@]}"; do
            shasum "$LOCAL_DEPENDENCIES_DIRECTORY/$package_name/Package.swift"
        done
    fi
}

install_dependencies() {
    # Tuist/Package.resolved is not committed. Every install starts it from the lock file SwiftPM
    # resolved for this checkout, so Tuist resolves the versions `swift build` and the native
    # workspace use rather than the newest ones.
    if [[ -f "$SEED_LOCK_FILE" ]]; then
        run cp "$SEED_LOCK_FILE" "$TUIST_PACKAGE_RESOLVED"
    else
        warn "no $SEED_LOCK_FILE to start from; Tuist resolves the newest versions the manifests allow"
        run rm -f "$TUIST_PACKAGE_RESOLVED"
    fi
    log "Resolving the $CURRENT_DEPENDENCY_MODE dependencies (tuist install)"
    # The manifests' TUIST_MAPS_LOCAL_PACKAGE_TESTS block leaves out or gives a product to the tests
    # Tuist would reject; Tuist records each manifest as it evaluates it here.
    run_tuist "install" env TUIST_MAPS_LOCAL_PACKAGE_TESTS=1 "${TUIST[@]}" install || fail "tuist install failed"
    if ! $DRY_RUN; then
        if [[ -f "$SEED_LOCK_FILE" ]]; then
            local differences
            if [[ "$CURRENT_DEPENDENCY_MODE" == local ]]; then
                differences="$(compare_lock_files swift-syntax "${LOCAL_PACKAGE_NAMES[@]}")" || true
            else
                differences="$(compare_lock_files swift-syntax)" || true
            fi
            if [[ -n "$differences" ]]; then
                warn "$TUIST_PACKAGE_RESOLVED resolved other versions than $SEED_LOCK_FILE:"
                printf '%s\n' "$differences" >&2
                warn "usually another Xcode resolved one of them: some packages pick their manifest by Swift version"
            fi
        fi
        mkdir -p "$WORK_ROOT"
        dump_manifests
        installed_dependencies_description > "$INSTALLED_DEPENDENCIES_STAMP"
    fi
}

# Evaluates the manifest of every package in the graph the way Tuist did, with
# TUIST_MAPS_LOCAL_PACKAGE_TESTS=1, into $MANIFESTS_DIRECTORY: this package and the upstream ones
# (from their checkouts in the local mode, from Tuist's checkouts in the remote mode), and every
# third-party checkout. $MANIFESTS_DIRECTORY/packages.tsv lists them as
# "<identity>\t<role>\t<directory>", the role being own-path, own-remote or third-party.
dump_manifests() {
    local package_name identity directory checkout
    run rm -rf "$MANIFESTS_DIRECTORY"
    mkdir -p "$MANIFESTS_DIRECTORY"
    {
        printf '%s\t%s\t%s\n' "$(lowercased "$PACKAGE_NAME")" own-path "$PROJECT_DIR"
        for package_name in "${LOCAL_PACKAGE_NAMES[@]}"; do
            if [[ "$CURRENT_DEPENDENCY_MODE" == local ]]; then
                printf '%s\t%s\t%s\n' "$(lowercased "$package_name")" own-path "$LOCAL_DEPENDENCIES_DIRECTORY/$package_name"
            else
                printf '%s\t%s\t%s\n' "$(lowercased "$package_name")" own-remote "$DEPENDENCIES_DIRECTORY/checkouts/$package_name"
            fi
        done
        for checkout in "$DEPENDENCIES_DIRECTORY"/checkouts/*; do
            [[ -f "$checkout/Package.swift" ]] || continue
            identity="$(lowercased "$(basename "$checkout")")"
            is_local_package_name "$identity" || printf '%s\t%s\t%s\n' "$identity" third-party "$checkout"
        done
    } > "$MANIFESTS_DIRECTORY/packages.tsv"
    log "Reading the manifests of $(wc -l < "$MANIFESTS_DIRECTORY/packages.tsv" | tr -d ' ') packages"
    # Eight at a time; each is a manifest evaluation, not a build.
    cut -f1,3 "$MANIFESTS_DIRECTORY/packages.tsv" | tr '\t' '\n' | tr '\n' '\0' \
        | xargs -0 -n 2 -P 8 /bin/bash -c '
            TUIST_MAPS_LOCAL_PACKAGE_TESTS=1 swift package --package-path "$2" --scratch-path "$0/Scratch/$1" dump-package \
                > "$0/$1.json" 2> "$0/$1.err" || rm -f "$0/$1.json"
        ' "$MANIFESTS_DIRECTORY"
    while IFS=$'\t' read -r identity _ directory; do
        if [[ ! -f "$MANIFESTS_DIRECTORY/$identity.json" ]]; then
            cat "$MANIFESTS_DIRECTORY/$identity.err" >&2 2>/dev/null || true
            fail "cannot read the manifest of $directory"
        fi
    done < <(grep -v $'\tthird-party\t' "$MANIFESTS_DIRECTORY/packages.tsv")
}

lowercased() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_local_package_name() {   # $1: an identity
    local package_name
    for package_name in "${LOCAL_PACKAGE_NAMES[@]}"; do
        [[ "$(lowercased "$package_name")" == "$1" ]] && return 0
    done
    return 1
}

# Resolves the dependencies unless they were last resolved for the current mode and manifests.
ensure_dependencies() {
    if [[ ! -d "$DEPENDENCIES_DIRECTORY/checkouts" || ! -f "$MANIFESTS_DIRECTORY/packages.tsv" ]]; then
        install_dependencies
    elif [[ "$(cat "$INSTALLED_DEPENDENCIES_STAMP" 2>/dev/null || true)" != "$(installed_dependencies_description)" ]]; then
        log "the dependencies were last resolved for another mode or other manifests"
        install_dependencies
    fi
}

# --- Reading the manifests ------------------------------------------------------------------------

# Reads $MANIFESTS_DIRECTORY and sets what the Tuist manifests read: the targets that stay source, the
# targets that get their warnings back, the test targets each scheme lists, and whether the tests can
# be mapped at all. Tuist maps the tests of every package declared by path or of none, and rejects a
# test that depends on an executable target or on a target no product contains; the manifests' block
# takes both away, so one left means that package's manifest has no block yet (an upstream checkout
# at an older commit, say), and the tests stay out this time.
read_manifests() {
    $DRY_RUN && return 0
    local key value analysis_path="$WORK_ROOT/ManifestAnalysis.txt"
    python3 - "$MANIFESTS_DIRECTORY" "$(lowercased "$PACKAGE_NAME")" "$UNLISTED_TEST_TARGETS" > "$analysis_path" <<'PYTHON' \
        || fail "cannot read the manifests in $MANIFESTS_DIRECTORY; run ./TuistScript.sh install"
import json
import os
import sys

manifests_directory, own_identity, unlisted_tests = sys.argv[1:4]
unlisted_tests = set(unlisted_tests.split(","))

packages = []
with open(os.path.join(manifests_directory, "packages.tsv")) as handle:
    for line in handle:
        identity, role, directory = line.rstrip("\n").split("\t")
        packages.append((identity, role, directory))

def load(identity):
    with open(os.path.join(manifests_directory, f"{identity}.json")) as handle:
        return json.load(handle)

def dependency_name(dependency):
    for kind in ("target", "byName"):
        if kind in dependency:
            return dependency[kind][0]
    return None

source_targets, warning_targets, test_entries, test_names, rejected = [], [], [], [], []
own_target_names = set()
for identity, role, directory in packages:
    if role == "third-party":
        continue
    manifest = load(identity)
    targets = manifest["targets"]
    names = [target["name"] for target in targets]
    # Tuist names the resource bundle of a target with resources <package>_<target>.
    names += [f"{manifest['name']}_{target['name']}" for target in targets if target.get("resources")]
    own_target_names.update(names)
    source_targets += names
    if role != "own-path":
        continue
    warning_targets += [target["name"] for target in targets if target["type"] != "test"]
    executable_names = {target["name"] for target in targets if target["type"] == "executable"}
    product_target_names = {
        name
        for product in manifest["products"] if "library" in product["type"]
        for name in product["targets"]
    }
    regular_names = {target["name"] for target in targets if target["type"] == "regular"}
    tests = [target for target in targets if target["type"] == "test"]
    test_names += [test["name"] for test in tests]
    for test in tests:
        for dependency in test["dependencies"]:
            name = dependency_name(dependency)
            if name in executable_names:
                rejected.append(f"{manifest['name']}'s {test['name']}, which depends on the executable target {name}")
            elif name in regular_names and name not in product_target_names:
                rejected.append(f"{manifest['name']}'s {test['name']}, which depends on {name}, a target no product contains")
    listed = [test["name"] for test in tests if test["name"] not in unlisted_tests]
    if listed:
        test_entries.append(f"{'.' if identity == own_identity else directory}={','.join(listed)}")

# Cache exceptions match target names in every package: a third-party target named like one of ours
# stays source too.
for identity, role, directory in packages:
    if role != "third-party":
        continue
    try:
        manifest = load(identity)
    except OSError:
        print(f"UNREAD={directory}")
        continue
    shared = sorted(own_target_names & {target["name"] for target in manifest["targets"]})
    if shared:
        print(f"SHARED_NAME={manifest['name']} has targets named like ones that stay source ({', '.join(shared)}); they stay source too")

print("SOURCE_TARGETS=" + ",".join(source_targets))
print("WARNING_TARGETS=" + ",".join(warning_targets))
print("TEST_TARGETS=" + ";".join(test_entries))
print("TEST_TARGET_NAMES=" + ",".join(test_names))
for reason in rejected:
    print("REJECTED=" + reason)
PYTHON
    TUIST_SOURCE_TARGET_NAMES=""
    TUIST_WARNING_TARGET_NAMES=""
    TUIST_PACKAGE_TEST_TARGETS=""
    TUIST_TEST_TARGET_NAMES=""
    TUIST_MAPS_LOCAL_PACKAGE_TESTS=1
    while IFS='=' read -r key value; do
        case "$key" in
            SOURCE_TARGETS) TUIST_SOURCE_TARGET_NAMES="$value";;
            WARNING_TARGETS) TUIST_WARNING_TARGET_NAMES="$value";;
            TEST_TARGETS) TUIST_PACKAGE_TEST_TARGETS="$value";;
            TEST_TARGET_NAMES) TUIST_TEST_TARGET_NAMES="$value";;
            REJECTED)
                warn "Tuist would reject $value"
                TUIST_MAPS_LOCAL_PACKAGE_TESTS=0;;
            SHARED_NAME) warn "$value";;
            UNREAD) warn "cannot read the manifest of $value; a target of it named like one of ours would stay source unnoticed";;
        esac
    done < "$analysis_path"
    if [[ "$TUIST_MAPS_LOCAL_PACKAGE_TESTS" != 1 ]]; then
        warn "the tests stay out of the workspace this time. Each manifest above needs the TUIST_MAPS_LOCAL_PACKAGE_TESTS block MachOSwiftSection's Package.swift ends with (Documentations/Internal/TuistDevelopment.md)."
        TUIST_PACKAGE_TEST_TARGETS=""
        TUIST_TEST_TARGET_NAMES=""
    fi
    export TUIST_SOURCE_TARGET_NAMES TUIST_WARNING_TARGET_NAMES TUIST_PACKAGE_TEST_TARGETS TUIST_TEST_TARGET_NAMES \
        TUIST_MAPS_LOCAL_PACKAGE_TESTS
}

# --- Commands -------------------------------------------------------------------------------------

claim_checkouts() {
    local package_name
    claim_checkout "$PROJECT_DIR" "$PACKAGE_NAME" "$PACKAGE_NAME"
    if [[ "$CURRENT_DEPENDENCY_MODE" == local ]]; then
        for package_name in "${LOCAL_PACKAGE_NAMES[@]}"; do
            claim_checkout "$LOCAL_DEPENDENCIES_DIRECTORY/$package_name" "$package_name" \
                "$(local_package_project_name "$package_name")"
        done
    fi
}

# The name Tuist gives the project it generates into an upstream checkout: the package's own name.
local_package_project_name() {
    python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["name"])' \
        "$MANIFESTS_DIRECTORY/$(lowercased "$1").json" 2>/dev/null || printf '%s\n' "$1"
}

# Generates the workspace against the binary cache of one configuration ($1, $CONFIGURATION by
# default).
generate_workspace() {
    local configuration="${1:-$CONFIGURATION}"
    ensure_dependencies
    read_manifests
    claim_checkouts
    log "Generating $WORKSPACE ($configuration, $CURRENT_DEPENDENCY_MODE dependencies)"
    run_tuist "generate-$configuration" "${TUIST[@]}" generate --no-open --configuration "$configuration" \
        || fail "tuist generate failed"
}

warm_cache() {
    ensure_dependencies
    read_manifests
    claim_checkouts
    if [[ -n "$STORAGE_ROOT" ]]; then
        # Tuist refuses to start with anything left in it from an earlier run, and never empties it.
        run rm -rf "$TUIST_CACHE_WARM_SCRATCH_DIRECTORY"
        run mkdir -p "$TUIST_CACHE_WARM_SCRATCH_DIRECTORY"
    fi
    log "Building the third-party dependencies into the binary cache ($CONFIGURATION)"
    # Without --cache-profile, `tuist cache warm` ignores the default profile in Tuist.swift and caches
    # every target it can, ours included.
    run_tuist "warm-$CONFIGURATION" "${TUIST[@]}" cache warm --configuration "$CONFIGURATION" \
        --cache-profile development --no-upload \
        || fail "tuist cache warm failed"
    # A workspace generated before the warm-up still builds the dependencies from source.
    generate_workspace "$CONFIGURATION"
}

xcodebuild_arguments() {
    printf '%s\n' -workspace "$WORKSPACE" -configuration "$CONFIGURATION" -destination 'platform=macOS' \
        -derivedDataPath "$WORK_ROOT/DerivedData/$CONFIGURATION" -skipPackagePluginValidation -skipMacroValidation
}

build_command() {
    generate_workspace
    local arguments=()
    while IFS= read -r argument; do arguments+=("$argument"); done < <(xcodebuild_arguments)
    log "Building $BUILD_SCHEME ($CONFIGURATION)"
    run_logged "build-$CONFIGURATION" xcodebuild build -scheme "$BUILD_SCHEME" "${arguments[@]}" \
        ${EXTRA_ARGUMENTS[@]+"${EXTRA_ARGUMENTS[@]}"} || fail "the build failed"
    $DRY_RUN || log "swift-section: $WORK_ROOT/DerivedData/$CONFIGURATION/Build/Products/$CONFIGURATION/swift-section"
}

test_command() {
    generate_workspace
    [[ -n "${TUIST_PACKAGE_TEST_TARGETS:-}" ]] || $DRY_RUN \
        || fail "the workspace has no test scheme this time (see the warning above)"
    local arguments=() result_bundle exit_code=0
    while IFS= read -r argument; do arguments+=("$argument"); done < <(xcodebuild_arguments)
    result_bundle="$WORK_ROOT/TestResults/$(date +%Y%m%d-%H%M%S).xcresult"
    log "Testing $TEST_SCHEME ($CONFIGURATION)"
    log "  result bundle: $result_bundle"
    run_logged "test-$CONFIGURATION" xcodebuild test -scheme "$TEST_SCHEME" "${arguments[@]}" \
        -resultBundlePath "$result_bundle" ${EXTRA_ARGUMENTS[@]+"${EXTRA_ARGUMENTS[@]}"} || exit_code=$?
    if ! $DRY_RUN && [[ -d "$result_bundle" ]]; then
        xcrun xcresulttool get test-results summary --path "$result_bundle" --compact 2>/dev/null \
            | python3 -c 'import json, sys; summary = json.load(sys.stdin); print("[TuistScript] result: {result}, {passedTests} passed, {failedTests} failed, {skippedTests} skipped".format(**summary))' \
            || true
    fi
    exit $exit_code
}

release_command() {
    local checkout_real_path
    if [[ -f "$CLAIMED_CHECKOUTS_FILE" ]]; then
        while IFS= read -r checkout_real_path; do
            [[ -n "$checkout_real_path" ]] && release_checkout "$checkout_real_path"
        done < <(cat "$CLAIMED_CHECKOUTS_FILE")
    fi
    run rm -f "$CLAIMED_CHECKOUTS_FILE"
    run rm -rf "$WORKSPACE" "$COMMAND_LINE_PROJECT_DIRECTORY/MachOSwiftSectionCommandLine.xcodeproj"
    log "released every checkout this one claimed; ./TuistScript.sh generate claims them again"
}

case "$COMMAND" in
    install) install_dependencies;;
    generate) generate_workspace;;
    warm) warm_cache;;
    build) build_command;;
    test) test_command;;
    release) release_command;;
esac
