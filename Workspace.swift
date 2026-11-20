import ProjectDescription

// MachOSwiftSection-Tuist.xcworkspace, the development-only workspace Tuist generates beside the
// native MachOSwiftSection.xcworkspace (Documentations/Internal/TuistDevelopment.md).
//
// The packages' test targets live in the projects Tuist converts from their Package.swift files, which
// only a workspace scheme can reference. TuistScript.sh lists them in TUIST_PACKAGE_TEST_TARGETS as
// "<package directory>=<test target>,<test target>;…", one entry per package whose tests are mapped:
// MachOSwiftSection always (directory "."), the upstream packages in the local dependency mode
// (absolute directories). IntegrationTests, the maintainer's manual-inspection target, is never listed.
let packageTestTargets: [(directory: String, targets: [String])] = Environment.packageTestTargets
    .getString(default: "")
    .split(separator: ";")
    .compactMap { entry in
        let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1].split(separator: ",").map(String.init))
    }

func packageName(ofDirectory directory: String) -> String {
    directory == "." ? "MachOSwiftSection" : String(directory.split(separator: "/").last ?? Substring(directory))
}

func projectPath(ofDirectory directory: String) -> Path {
    directory.hasPrefix("/") ? .path(directory) : .relativeToRoot(directory)
}

let workspace = Workspace(
    name: "MachOSwiftSection-Tuist",
    projects: ["Tuist/CommandLine"],
    schemes: packageTestTargets.map { entry in
        var testableTargets = entry.targets.map { targetName in
            TestableTarget.testableTarget(
                target: .project(path: projectPath(ofDirectory: entry.directory), target: targetName),
                parallelization: .swiftTestingOnly
            )
        }
        if entry.directory == "." {
            testableTargets.append(.testableTarget(
                target: .project(path: "Tuist/CommandLine", target: "SwiftSectionCommandTests"),
                parallelization: .swiftTestingOnly
            ))
        }
        return .scheme(
            name: "\(packageName(ofDirectory: entry.directory)) Tests",
            testAction: .targets(
                testableTargets,
                // The test process as `swift test` runs it. The Thread Performance Checker inserts
                // libRPAC.dylib, which rebinds calls in the loaded images: the cross-reference tests that
                // compare a cache image read in process with the same image read from its file then
                // see calls into libRPAC. The Main Thread Checker swizzles Objective-C methods the same
                // way. Tuist 4.210 writes only the Main Thread Checker's attribute; TuistScript.sh adds
                // disablePerformanceAntipatternChecker to the generated schemes.
                diagnosticsOptions: .options(mainThreadCheckerEnabled: false, performanceAntipatternCheckerEnabled: false)
            )
        )
    }
)
