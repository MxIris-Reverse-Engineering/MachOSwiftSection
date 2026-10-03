import ArgumentParser
import Foundation
import SwiftSectionKit

// The library's enums, spelled on the command line by their raw values. The
// library is in this package, so the conformances are not retroactive.
extension Architecture: ExpressibleByArgument {}
extension DumpSection: ExpressibleByArgument {}
extension TransformerModule: ExpressibleByArgument {}
extension ObjCDeclarationKind: ExpressibleByArgument {}

extension SwiftSectionEnvironment {
    /// What the command line stamps into headers and provenance.
    static var commandLine: SwiftSectionEnvironment {
        SwiftSectionEnvironment(generator: GeneratorIdentity(name: "swift-section", version: BundledVersion.value))
    }
}

/// The image the input options name, rejecting the combinations a
/// `MachOSource` cannot express with the messages the command line has always
/// printed for them. Shared by the Swift and the ObjC option groups.
func makeMachOSource(
    filePath: String?,
    isDyldSharedCache: Bool,
    usesSystemDyldSharedCache: Bool,
    cacheImageName: String?,
    cacheImagePath: String?,
    architecture: Architecture?
) throws -> MachOSource {
    guard isDyldSharedCache || usesSystemDyldSharedCache else {
        guard let filePath else { throw SwiftSectionCommandError.missingFilePath }
        return .file(path: filePath, architecture: architecture)
    }
    guard usesSystemDyldSharedCache || filePath != nil else {
        throw SwiftSectionCommandError.missingFilePath
    }
    let image = try makeDyldSharedCacheImage(cacheImageName: cacheImageName, cacheImagePath: cacheImagePath)
    if usesSystemDyldSharedCache {
        return .systemDyldSharedCache(image: image)
    } else {
        // Checked above.
        return .dyldSharedCache(cachePath: filePath!, image: image)
    }
}

/// The binary-loading options of `snapshot`: `--dyld-shared-cache` turns every
/// binary input into a cache to extract the named image from.
func makeBinaryLoadingOptions(
    isDyldSharedCache: Bool,
    cacheImageName: String?,
    cacheImagePath: String?,
    architecture: Architecture?
) throws -> BinaryLoadingOptions {
    BinaryLoadingOptions(
        architecture: architecture,
        dyldSharedCacheImage: isDyldSharedCache
            ? try makeDyldSharedCacheImage(cacheImageName: cacheImageName, cacheImagePath: cacheImagePath)
            : nil
    )
}

private func makeDyldSharedCacheImage(cacheImageName: String?, cacheImagePath: String?) throws -> DyldSharedCacheImage {
    if cacheImagePath != nil, cacheImageName != nil {
        throw SwiftSectionCommandError.ambiguousCacheImageNameAndCacheImagePath
    } else if let cacheImageName {
        return .name(cacheImageName)
    } else if let cacheImagePath {
        return .path(cacheImagePath)
    } else {
        throw SwiftSectionCommandError.missingCacheImageNameOrCacheImagePath
    }
}

enum CommandLineErrorTranslation {
    /// `error` as the command line has always reported it.
    ///
    /// The library words its errors without naming options; the command line
    /// names them, and a usage mistake is a `ValidationError` (usage text,
    /// exit code 64) rather than a plain failure (exit code 1). Anything not
    /// listed passes through unchanged.
    ///
    /// `annotatedInterfaceRequiresBinaries` words the `--interface` mistake of
    /// handing a snapshot document to `diff` or `evolution`; the two have
    /// always worded it differently.
    static func translated(
        _ error: any Swift.Error,
        annotatedInterfaceRequiresBinaries: ((_ snapshotPath: String) -> String)? = nil
    ) -> any Swift.Error {
        switch error {
        case let machOSourceError as MachOSourceError:
            switch machOSourceError {
            case .fatBinaryRequiresArchitecture(let availableArchitectures):
                return SwiftSectionCommandError.fatBinaryRequiresArchitecture(availableArchitectures: availableArchitectures)
            case .architectureNotFound:
                return SwiftSectionCommandError.invalidArchitecture
            case .dyldSharedCacheImageNotFound:
                return SwiftSectionCommandError.imageNotFound
            case .systemDyldSharedCacheUnavailable:
                return SwiftSectionCommandError.unsupportedSystemVersionForDyldSharedCache
            }
        case SnapshotSourceError.binaryRequired(let snapshotPath):
            guard let annotatedInterfaceRequiresBinaries else { return error }
            return ValidationError(annotatedInterfaceRequiresBinaries(snapshotPath))
        default:
            return error
        }
    }
}
