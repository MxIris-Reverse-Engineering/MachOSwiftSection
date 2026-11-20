import ProjectDescription

// Every target of MachOSwiftSection and of the five upstream packages its native workspace lists
// (MachOKit, MachOKitExtensions, MachOObjCSection, swift-demangling, swift-semantic-string) stays
// source, in both dependency modes; every other dependency comes out of the binary cache once
// `./TuistScript.sh warm` has filled it. The script reads the names from the packages' manifests and
// passes them in TUIST_SOURCE_TARGET_NAMES. No fullHandle: the cache stays on this machine and
// nothing is uploaded. Documentations/Internal/TuistDevelopment.md.
let sourceTargetNames = Environment.sourceTargetNames
    .getString(default: "")
    .split(separator: ",")
    .map(String.init)

let tuist = Tuist(
    project: .tuist(
        cacheOptions: .options(
            profiles: .profiles(
                ["development": .profile(.onlyExternal, except: sourceTargetNames.map { .named($0) })],
                default: "development"
            )
        )
    )
)
