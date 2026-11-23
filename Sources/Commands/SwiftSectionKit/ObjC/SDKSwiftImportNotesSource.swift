#if os(macOS)

import MachOKit
import MachOKitExtensions
import ObjCDeclarationRendering
import ObjCTypeIndexing
import SwiftTypeNameResolution
import TypeIndexing

/// The notes `objc interface --mark-sdk-swift-names` prints: what the API
/// notes of the binary's SDK say about how Swift imports a class or protocol
/// and its members, read from the active developer directory. API notes only:
/// no module interface is generated, so no sourcekitd work runs.
@available(macOS 13.0, *)
struct SDKSwiftImportNotesSource: Sendable {
    let typeDatabase: TypeDatabase

    /// The source for `machOFile`'s SDK, or `nil` after a warning when the
    /// binary names no platform an SDK covers, or this Mac has no SDK for it.
    static func make(for machOFile: MachOFile, output: some SwiftSectionOutput) async -> SDKSwiftImportNotesSource? {
        guard
            let buildPlatform = machOFile.loadCommands.buildVersionCommand?.platform,
            let platform = SDKPlatform(buildPlatform)
        else {
            output.report(SwiftSectionDiagnostic(severity: .warning, message: "warning: --mark-sdk-swift-names: the binary names no platform an SDK covers; printing it without the SDK's Swift names"))
            return nil
        }
        let availability = TypeIndexingAvailability.availability(for: platform)
        guard availability.isAvailable else {
            output.report(SwiftSectionDiagnostic(severity: .warning, message: "warning: --mark-sdk-swift-names: the active developer directory has no \(platform.rawValue) SDK; printing without the SDK's Swift names"))
            return nil
        }
        let typeDatabase = TypeDatabase(platform: platform)
        do {
            try await typeDatabase.index(dependencies: [], moduleFilter: { _ in false })
        } catch {
            output.report(SwiftSectionDiagnostic(severity: .warning, message: "warning: --mark-sdk-swift-names: reading the \(platform.rawValue) SDK failed (\(error)); printing without the SDK's Swift names"))
            return nil
        }
        return SDKSwiftImportNotesSource(typeDatabase: typeDatabase)
    }

    /// The notes for the declaration of `kind` named `name`. A category takes
    /// the notes of the class it extends — API notes list category methods
    /// under the class — and the builder leaves out the class's own note.
    func notes(for kind: ObjCDeclarationKind, named name: String) async -> ObjCSwiftImportNotes {
        switch kind {
        case .classes:
            return await ObjCSwiftImportNotes(apiNotesForClassNamed: name, in: typeDatabase)
        case .protocols:
            return await ObjCSwiftImportNotes(apiNotesForProtocolNamed: name, in: typeDatabase)
        case .categories:
            let className = name.split(separator: "(", maxSplits: 1).first.map(String.init) ?? name
            return await ObjCSwiftImportNotes(apiNotesForClassNamed: className, in: typeDatabase)
        case .structs, .unions:
            return ObjCSwiftImportNotes()
        }
    }
}

#endif
