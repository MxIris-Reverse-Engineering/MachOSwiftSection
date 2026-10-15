import Testing
@testable import SwiftPrivateDiscriminators

/// Recovering the source file a private discriminator was derived from. Every
/// expected value was computed with `md5 -s` outside this code base —
/// `md5 -s 'SwiftUICoreEnabled.swift'` is `09ce35833f3876fe3a3a46977d61fc64` —
/// and the discriminators, with the private types declared under them, are the
/// ones SwiftUICore and Foundation actually carry (macOS 26.7).
///
/// Each rule is tested with no known file names, so that only the image's own
/// names can produce the file name. Moved from RuntimeViewer with the search
/// itself (evolution proposal `private-declarations`).
@Suite
struct PrivateDiscriminatorSourceFilesTests {
    private static let swiftUICorePath = "/System/Library/Frameworks/SwiftUICore.framework/Versions/A/SwiftUICore"
    private static let foundationPath = "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation"

    /// A name as a reader is shown it — without discriminators — and the
    /// discriminators of the private declarations it reads.
    private static func name(_ printedName: String, discriminators: [String] = []) -> PrivateDiscriminatorSourceFiles.ImageName {
        PrivateDiscriminatorSourceFiles.ImageName(printedName: printedName, discriminators: discriminators)
    }

    private static func sourceFile(of discriminator: String, in imagePath: String = swiftUICorePath, among imageNames: [PrivateDiscriminatorSourceFiles.ImageName], knownFileNames: [String] = []) -> PrivateDiscriminatorSourceFiles.SourceFile? {
        PrivateDiscriminatorSourceFiles(recovering: [discriminator], imagePath: imagePath, imageNames: imageNames, knownFileNames: knownFileNames)
            .sourceFile(forDiscriminator: discriminator)
    }

    // MARK: - Names of the Image

    @Test("a framework's discriminator is recovered under the framework's own name, not the module its types print under")
    func frameworkDiscriminatorUsesFrameworkName() {
        let sourceFile = Self.sourceFile(
            of: "_09CE35833F3876FE3A3A46977D61FC64",
            among: [Self.name("SwiftUI.EnabledKey", discriminators: ["_09CE35833F3876FE3A3A46977D61FC64"])]
        )
        #expect(sourceFile == .init(fileName: "Enabled.swift", moduleName: "SwiftUICore", isSynthesized: false))
    }

    @Test("a file named after another type in the image is found through that type's name")
    func fileNamedAfterAnotherType() {
        let privateType = Self.name("SwiftUI.ResetDeltaModifier", discriminators: ["_C38EF38637B6130AEFD462CBD5EAC727"])

        #expect(Self.sourceFile(of: "_C38EF38637B6130AEFD462CBD5EAC727", among: [privateType]) == nil)
        #expect(Self.sourceFile(of: "_C38EF38637B6130AEFD462CBD5EAC727", among: [privateType, Self.name("SwiftUI._ViewInputs")])?.fileName == "ViewInputs.swift")
    }

    @Test("a private type nested in another type is recovered too")
    func nestedPrivateTypeIsRecovered() {
        let sourceFile = Self.sourceFile(
            of: "_09CE35833F3876FE3A3A46977D61FC64",
            among: [
                Self.name("SwiftUI.Outer"),
                Self.name("SwiftUI.Outer.EnabledKey", discriminators: ["_09CE35833F3876FE3A3A46977D61FC64"]),
            ]
        )
        #expect(sourceFile?.fileName == "Enabled.swift")
    }

    @Test("an acronym ends a word, so JSONEncoder suggests JSONEncoder.swift")
    func acronymEndsAWord() {
        let sourceFile = Self.sourceFile(
            of: "_12768CA107A31EF2DCE034FD75B541C9",
            in: Self.foundationPath,
            among: [Self.name("Foundation.__JSONEncoder", discriminators: ["_12768CA107A31EF2DCE034FD75B541C9"])]
        )
        #expect(sourceFile == .init(fileName: "JSONEncoder.swift", moduleName: "Foundation", isSynthesized: false))
    }

    @Test("a run of words from the middle of a name is a file name too")
    func middleRunOfWords() {
        let sourceFile = Self.sourceFile(
            of: "_25C7EE19F64B0E53EE4CB01B5E3710EB",
            among: [
                Self.name("SwiftUI.DisplayList.InterpolatorLayer.Contents", discriminators: ["_25C7EE19F64B0E53EE4CB01B5E3710EB"]),
                Self.name("__C.RBDisplayListInterpolatorOptionKey"),
            ]
        )
        #expect(sourceFile?.fileName == "DisplayListInterpolator.swift")
    }

    @Test("a word that often ends a file name is tried after a run of words")
    func commonLastWord() {
        let sourceFile = Self.sourceFile(
            of: "_82B2D47816BC992595021D60C278AFF0",
            among: [
                Self.name("SwiftUI.AtomicBuffer", discriminators: ["_82B2D47816BC992595021D60C278AFF0"]),
                Self.name("SwiftUI.MainThreadFlags"),
            ]
        )
        #expect(sourceFile?.fileName == "ThreadUtils.swift")
    }

    @Test("a name is tried in the plural")
    func pluralName() {
        let sourceFile = Self.sourceFile(
            of: "_59349949219F590F26B6A55CEC9D59A2",
            among: [Self.name("SwiftUI.Signpost.Level", discriminators: ["_59349949219F590F26B6A55CEC9D59A2"])]
        )
        #expect(sourceFile?.fileName == "Signposts.swift")
    }

    @Test("an extension's file name comes from two words of the names declared in it")
    func extensionFileFromItsOwnNames() {
        let sourceFile = Self.sourceFile(
            of: "_AEE0E21EC7C6B2D1204F94F94CBF7389",
            among: [Self.name("SwiftUI.DateTextStorage", discriminators: ["_AEE0E21EC7C6B2D1204F94F94CBF7389"])]
        )
        #expect(sourceFile?.fileName == "Text+Date.swift")
    }

    @Test("an extension's file name can start with any type of the image")
    func extensionFileOfAnotherType() {
        let privateType = Self.name("SwiftUI.ObjectLocation", discriminators: ["_7719FABF28E05207C06C2817640AD611"])

        #expect(Self.sourceFile(of: "_7719FABF28E05207C06C2817640AD611", among: [privateType]) == nil)
        #expect(Self.sourceFile(of: "_7719FABF28E05207C06C2817640AD611", among: [privateType, Self.name("SwiftUI.Binding")])?.fileName == "Binding+ObjectLocation.swift")
    }

    @Test("the file the compiler synthesizes for a file of the image is recovered through that file")
    func synthesizedFileIsRecovered() {
        let sourceFile = Self.sourceFile(
            of: "_7851CE71456138B12D1FE5F34D2E09D2",
            in: Self.foundationPath,
            among: [
                Self.name("Foundation.__JSONEncoder", discriminators: ["_12768CA107A31EF2DCE034FD75B541C9"]),
                Self.name("Foundation.SynthesizedConformance", discriminators: ["_7851CE71456138B12D1FE5F34D2E09D2"]),
            ]
        )
        #expect(sourceFile == .init(fileName: "JSONEncoder.swift", moduleName: "Foundation", isSynthesized: true))
    }

    @Test("the module a private type prints under is tried when the image's file name is not the module")
    func moduleFromPrintedNameIsTried() {
        let imagePath = "/Applications/My App.app/Contents/Frameworks/Shared.framework/Shared"
        let sourceFile = Self.sourceFile(
            of: "_49589088029ECC1F743D97737F6C44F6",
            in: imagePath,
            among: [
                Self.name("My_App.Row", discriminators: ["_49589088029ECC1F743D97737F6C44F6"]),
                Self.name("My_App.ContentView"),
            ]
        )
        #expect(sourceFile?.moduleName == "My_App")
    }

    /// A local type's name starts with the type, not a module: what comes
    /// before its first dot is no module name to hash under.
    @Test("a local type's name lends no module name")
    func localTypeNameLendsNoModuleName() {
        let imagePath = "/Applications/My App.app/Contents/Frameworks/Shared.framework/Shared"
        let sourceFiles = PrivateDiscriminatorSourceFiles.Candidates(
            imagePath: imagePath,
            imageNames: [Self.name("Visitor #1 in My_App.Holder.(rows in _49589088029ECC1F743D97737F6C44F6)() -> Any", discriminators: ["_49589088029ECC1F743D97737F6C44F6"])]
        )
        #expect(sourceFiles.moduleNames == ["Shared"])
    }

    /// The discriminator is made up — `md5 -s 'SwiftUICoreGlue.swift'` — since
    /// the point is that those bytes read two ways: `CoreGlue.swift`, the known
    /// name, hashed under `SwiftUI`, is `Glue.swift` under `SwiftUICore`.
    @Test("a digest two module names read alike is read under the module name tried first")
    func digestIsReadUnderTheFirstModuleName() {
        let sourceFile = Self.sourceFile(
            of: "_CE8713EF1F659E3933681417E097F9F6",
            among: [Self.name("SwiftUI.Foo", discriminators: ["_CE8713EF1F659E3933681417E097F9F6"])],
            knownFileNames: ["CoreGlue.swift"]
        )
        #expect(sourceFile == .init(fileName: "Glue.swift", moduleName: "SwiftUICore", isSynthesized: false))
    }

    @Test("only the discriminators asked for are looked for")
    func onlyRequestedDiscriminators() {
        let sourceFiles = PrivateDiscriminatorSourceFiles(
            recovering: ["_09CE35833F3876FE3A3A46977D61FC64"],
            imagePath: Self.swiftUICorePath,
            imageNames: [
                Self.name("SwiftUI.EnabledKey", discriminators: ["_09CE35833F3876FE3A3A46977D61FC64"]),
                Self.name("SwiftUI.ResetDeltaModifier", discriminators: ["_C38EF38637B6130AEFD462CBD5EAC727"]),
                Self.name("SwiftUI._ViewInputs"),
            ],
            knownFileNames: []
        )
        #expect(sourceFiles.sourceFile(forDiscriminator: "_09CE35833F3876FE3A3A46977D61FC64")?.fileName == "Enabled.swift")
        #expect(sourceFiles.sourceFile(forDiscriminator: "_C38EF38637B6130AEFD462CBD5EAC727") == nil)
    }

    @Test("a discriminator no candidate produces is left unrecovered")
    func unproducedDiscriminatorIsUnrecovered() {
        let sourceFile = Self.sourceFile(
            of: "_70EED0686586E4A728468B96DBF4A6DF",
            among: [Self.name("SwiftUI.NearestScrollableAxesEnvironmentKey", discriminators: ["_70EED0686586E4A728468B96DBF4A6DF"])]
        )
        #expect(sourceFile == nil)
    }

    // MARK: - Known File Names

    @Test("a known file name recovers a discriminator the image's names do not produce")
    func knownFileNameIsTried() {
        let privateType = Self.name("SwiftUI.ResetDeltaModifier", discriminators: ["_C38EF38637B6130AEFD462CBD5EAC727"])

        #expect(Self.sourceFile(of: "_C38EF38637B6130AEFD462CBD5EAC727", among: [privateType], knownFileNames: ["ViewInputs.swift"])?.fileName == "ViewInputs.swift")
    }

    @Test("the bundled file names include OpenSwiftUI's, and are what is tried by default")
    func bundledFileNamesAreTriedByDefault() {
        let privateType = Self.name("SwiftUI.ResetDeltaModifier", discriminators: ["_C38EF38637B6130AEFD462CBD5EAC727"])
        let sourceFiles = PrivateDiscriminatorSourceFiles(recovering: ["_C38EF38637B6130AEFD462CBD5EAC727"], imagePath: Self.swiftUICorePath, imageNames: [privateType])

        #expect(sourceFiles.sourceFile(forDiscriminator: "_C38EF38637B6130AEFD462CBD5EAC727")?.fileName == "ViewInputs.swift")
    }
}
