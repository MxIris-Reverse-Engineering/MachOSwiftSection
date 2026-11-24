import ArgumentParser
import Foundation
import SwiftSectionKit
import SwiftPrinting

// The library's enums, spelled on the command line by their raw values. The
// library is in this package, so the conformances are not retroactive.
extension Architecture: ExpressibleByArgument {}
extension DumpSection: ExpressibleByArgument {}
extension TransformerModule: ExpressibleByArgument {}
extension ObjCDeclarationKind: ExpressibleByArgument {}

// Spelled in the command line's kebab case rather than by its raw value.
extension CImportedTypeNameSpelling: ExpressibleByArgument {
    public init?(argument: String) {
        guard let spelling = Self.allCases.first(where: { $0.argumentValue == argument }) else { return nil }
        self = spelling
    }

    public var defaultValueDescription: String {
        argumentValue
    }

    public static var allValueStrings: [String] {
        allCases.map(\.argumentValue)
    }

    private var argumentValue: String {
        switch self {
        case .swiftName: "swift-name"
        case .cName: "c-name"
        }
    }
}

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
        case CrossReferenceRequestError.imageNotFound(let name):
            return ValidationError("No analyzed image is named '\(name)'; --in-image and --function-image take an image's path or its file name.")
        case CrossReferenceRequestError.ambiguousFunction(let address, let imagePaths):
            return ValidationError("Several files hold a function at 0x\(String(address, radix: 16)): \(imagePaths.joined(separator: ", ")). Name its image with --function-image.")
        case SnapshotSourceError.binaryRequired(let snapshotPath):
            guard let annotatedInterfaceRequiresBinaries else { return error }
            return ValidationError(annotatedInterfaceRequiresBinaries(snapshotPath))
        case AvailabilityPlatformInferenceError.noPlatform(let path):
            return ValidationError("--emit-available could not infer an @available platform from \(path) (no LC_BUILD_VERSION, or a platform with no @available spelling); pass --platform explicitly.")
        case AvailabilityPlatformInferenceError.conflictingPlatforms(let platforms):
            return ValidationError("--emit-available found conflicting platforms across the inputs (\(platforms.joined(separator: ", "))); pass --platform explicitly.")
        case ObjCAvailabilityPlatformInferenceError.noPlatform(let path):
            return ValidationError("--emit-available could not infer an availability-macro platform from \(path) (no LC_BUILD_VERSION, or a platform the availability macros have no name for); pass --platform explicitly.")
        case ObjCAvailabilityPlatformInferenceError.conflictingPlatforms(let platforms):
            return ValidationError("--emit-available found conflicting platforms across the inputs (\(platforms.joined(separator: ", "))); pass --platform explicitly.")
        default:
            return error
        }
    }
}
