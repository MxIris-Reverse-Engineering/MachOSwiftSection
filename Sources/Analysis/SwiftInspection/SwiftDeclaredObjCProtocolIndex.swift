import Foundation
import FoundationToolbox
import MachOKit
import MachOKitExtensions
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import MachOCaches

/// An `@objc` protocol declared in Swift that this image defines (evolution
/// proposal `swift-declared-objc-protocols`). The compiler gives such a
/// protocol no Swift protocol descriptor, so `__swift5_protos` never lists
/// it; what it does get is a `__swift5_fieldmd` record of kind
/// `ObjCProtocol` naming it, and an Objective-C protocol record holding its
/// requirements.
package struct SwiftDeclaredObjCProtocol: Sendable, Hashable {
    /// How the index knows the image defines the protocol.
    package enum Evidence: Sendable, Hashable {
        /// A field descriptor of kind `ObjCProtocol`: `emitProtocolDecl`
        /// emits one for every protocol the module declares, before it
        /// branches on `isObjC()`.
        case fieldDescriptor(offset: Int)
        /// No reflection metadata: the record's `_TtP` runtime name spells
        /// one of the image's own modules.
        case runtimeName
    }

    /// The protocol's Swift mangling (`$s13DVTFoundation17DVTTeamCredentialP`),
    /// the form a host demangles the name from.
    package let mangledName: String
    /// `DVTFoundation.DVTTeamCredential`.
    package let qualifiedName: String
    package let evidence: Evidence
    /// The Objective-C record; `nil` when none could be paired with the
    /// declaration — the source renamed it with `@objc(Name)` to a name other
    /// than its Swift name, so nothing ties the two.
    package let record: ObjCProtocolRecord?

    /// Whether the source renamed the protocol for the runtime: its runtime
    /// name is not the `_TtP…_` mangling the compiler derives by default.
    /// An unpaired protocol was renamed, or it would have paired.
    package var hasExplicitObjCName: Bool {
        guard let record else { return true }
        return !record.runtimeName.hasPrefix("_TtP")
    }
}

/// Per-image index of the `@objc` protocols declared in Swift that the image
/// defines, each paired with its Objective-C protocol record.
///
/// Which protocols the image defines comes from `__swift5_fieldmd`, never
/// from the records' `IsSwift` bit: Swift emits a record carrying the bit for
/// every Swift `@objc` protocol the image merely references, and clang emits
/// one without it when Objective-C code references a Swift protocol through a
/// generated header. Swift's and clang's record symbols are named differently
/// (`_PROTOCOL_<name>` and `_OBJC_PROTOCOL_$_<name>`), so one image can hold
/// both for the same protocol; the pairing goes by name and prefers Swift's.
///
/// - A protocol the source did not rename pairs with the record whose `_TtP`
///   runtime name demangles to the same qualified name.
/// - A renamed one (`@objc(Name)`) pairs with the record whose runtime name
///   is its own Swift name — the common `@objc(X) protocol X` — and stays
///   unpaired otherwise.
/// - An image built without reflection metadata has no field descriptors;
///   then a record whose `_TtP` name spells one of the image's own modules is
///   the image's, and a renamed protocol goes unseen.
///
/// Built once per image, lazily, and evicted with the other ObjC-side
/// per-image state. This module sits below the event layer, so what could
/// not be read is only logged.
@Loggable(.private, subsystem: "com.machoswiftsection.swift-inspection", category: "SwiftDeclaredObjCProtocolIndex")
package final class SwiftDeclaredObjCProtocolIndex: @unchecked Sendable {
    package static let shared = SwiftDeclaredObjCProtocolIndex()

    private let cache = SharedCache<Storage>(evictionGroup: .objcHierarchy)

    private init() {}

    package final class Storage: @unchecked Sendable {
        /// Field-descriptor order, then the records the fallback found.
        let protocols: [SwiftDeclaredObjCProtocol]

        /// Records Swift emitted that no declaration of this image claims:
        /// another module's renamed protocol the image references, or one of
        /// its own renamed to a name other than its Swift name.
        let unclaimedSwiftEmittedRecords: [ObjCProtocolRecord]

        /// Runtime name → Swift qualified name, for every paired protocol.
        let qualifiedNamesByRuntimeName: [String: String]

        init(protocols: [SwiftDeclaredObjCProtocol], unclaimedSwiftEmittedRecords: [ObjCProtocolRecord]) {
            self.protocols = protocols
            self.unclaimedSwiftEmittedRecords = unclaimedSwiftEmittedRecords
            var qualifiedNamesByRuntimeName: [String: String] = [:]
            for declaredProtocol in protocols {
                if let record = declaredProtocol.record {
                    qualifiedNamesByRuntimeName[record.runtimeName] = declaredProtocol.qualifiedName
                }
            }
            self.qualifiedNamesByRuntimeName = qualifiedNamesByRuntimeName
        }
    }

    /// The image's index, built on first use.
    package func storage(in machO: some MachORepresentableWithCache) -> Storage? {
        cache.storage(in: machO) { machO in
            machO.objcImplementationClassReader.map { Self.build(in: $0) }
        }
    }

    package func contains(in machO: some MachORepresentableWithCache) -> Bool {
        cache.contains(in: machO)
    }

    package func remove(for machO: some MachORepresentableWithCache) {
        cache.remove(for: machO)
    }

    // MARK: - Queries

    /// The image's protocols: field-descriptor order, then the ones the
    /// fallback found.
    package func protocols(in machO: some MachORepresentableWithCache) -> [SwiftDeclaredObjCProtocol] {
        storage(in: machO)?.protocols ?? []
    }

    /// The Swift qualified name of the image's protocol that goes by
    /// `runtimeName` for the Objective-C runtime.
    package func qualifiedName(forRuntimeName runtimeName: String, in machO: some MachORepresentableWithCache) -> String? {
        storage(in: machO)?.qualifiedNamesByRuntimeName[runtimeName]
    }

    /// Records Swift emitted that no declaration of this image claims.
    package func unclaimedSwiftEmittedRecords(in machO: some MachORepresentableWithCache) -> [ObjCProtocolRecord] {
        storage(in: machO)?.unclaimedSwiftEmittedRecords ?? []
    }

    // MARK: - Build

    private struct Declaration {
        let mangledName: String
        let qualifiedName: String
        let fieldDescriptorOffset: Int
    }

    private static func build<MachO: ObjCImplementationClassReading & MachOSwiftSectionRepresentableWithCache>(in machO: MachO) -> Storage {
        let records = machO.objcProtocolRecords()
        // Swift's record first: a name clang also emitted keeps Swift's.
        var recordsByRuntimeName: [String: ObjCProtocolRecord] = [:]
        for record in records where recordsByRuntimeName[record.runtimeName].map({ !$0.isEmittedBySwift && record.isEmittedBySwift }) ?? true {
            recordsByRuntimeName[record.runtimeName] = record
        }
        var recordsByDefaultQualifiedName: [String: ObjCProtocolRecord] = [:]
        for record in recordsByRuntimeName.values {
            if let qualifiedName = qualifiedName(ofDefaultRuntimeName: record.runtimeName) {
                recordsByDefaultQualifiedName[qualifiedName] = record
            }
        }

        let fieldDescriptorDeclarations = declarations(in: machO)
        let declarations = fieldDescriptorDeclarations ?? []
        var claimedRuntimeNames: Set<String> = []
        var protocols: [SwiftDeclaredObjCProtocol] = []
        let declarationCountsByBaseName = Dictionary(declarations.map { (baseName(of: $0.qualifiedName), 1) }, uniquingKeysWith: +)
        for declaration in declarations {
            var record = recordsByDefaultQualifiedName[declaration.qualifiedName]
            if record == nil {
                // Renamed: paired only with a record named exactly like the
                // protocol, and only when no other declaration shares that
                // name — two modules linked into one image could.
                let name = baseName(of: declaration.qualifiedName)
                if declarationCountsByBaseName[name] == 1, let renamedRecord = recordsByRuntimeName[name] {
                    record = renamedRecord
                }
            }
            if let record {
                claimedRuntimeNames.insert(record.runtimeName)
            }
            protocols.append(SwiftDeclaredObjCProtocol(
                mangledName: declaration.mangledName,
                qualifiedName: declaration.qualifiedName,
                evidence: .fieldDescriptor(offset: declaration.fieldDescriptorOffset),
                record: record
            ))
        }

        // Without reflection metadata — no `__swift5_fieldmd` at all — a
        // `_TtP` record naming one of the image's own modules is the image's.
        // With it, every protocol the image declares has a field descriptor,
        // and a `_TtP` record nothing claimed is another module's.
        if fieldDescriptorDeclarations == nil {
            let moduleNames = moduleNames(in: machO)
            for (qualifiedName, record) in recordsByDefaultQualifiedName.sorted(by: { $0.value.offset < $1.value.offset }) {
                guard let moduleName = qualifiedName.split(separator: ".").first.map(String.init), moduleNames.contains(moduleName) else { continue }
                claimedRuntimeNames.insert(record.runtimeName)
                protocols.append(SwiftDeclaredObjCProtocol(
                    mangledName: swiftMangledName(ofDefaultRuntimeName: record.runtimeName) ?? record.runtimeName,
                    qualifiedName: qualifiedName,
                    evidence: .runtimeName,
                    record: record
                ))
            }
        }

        let unclaimedSwiftEmittedRecords = recordsByRuntimeName.values
            .filter { $0.isEmittedBySwift && !claimedRuntimeNames.contains($0.runtimeName) && qualifiedName(ofDefaultRuntimeName: $0.runtimeName) == nil }
            .sorted { $0.offset < $1.offset }
        return Storage(protocols: protocols, unclaimedSwiftEmittedRecords: unclaimedSwiftEmittedRecords)
    }

    /// The field descriptors of kind `ObjCProtocol`, named; `nil` when the
    /// image has no `__swift5_fieldmd` — one built without reflection
    /// metadata.
    private static func declarations(in machO: some MachOSwiftSectionRepresentableWithCache) -> [Declaration]? {
        guard let fieldDescriptors = try? machO.swift.fieldDescriptors else { return nil }
        var declarations: [Declaration] = []
        for fieldDescriptor in fieldDescriptors where fieldDescriptor.kind == .objCProtocol {
            do {
                let mangledName = try fieldDescriptor.mangledTypeName(in: machO.context).symbolString
                guard let qualifiedName = qualifiedName(ofSwiftMangledName: mangledName) else {
                    #log(.error, "skipped the @objc protocol field descriptor at offset \(fieldDescriptor.offset, privacy: .public): its name \(mangledName, privacy: .public) names no protocol")
                    continue
                }
                declarations.append(Declaration(mangledName: mangledName, qualifiedName: qualifiedName, fieldDescriptorOffset: fieldDescriptor.offset))
            } catch {
                #log(.error, "skipped the @objc protocol field descriptor at offset \(fieldDescriptor.offset, privacy: .public): name unreadable: \(String(describing: error), privacy: .public)")
            }
        }
        return declarations
    }

    /// The modules the image's Swift metadata belongs to: the module context
    /// at the root of every type and protocol descriptor's parent chain. More
    /// than one when modules were linked statically into one image.
    private static func moduleNames(in machO: some MachOSwiftSectionRepresentableWithCache) -> Set<String> {
        let context = machO.context
        let descriptors = ((try? machO.swift.contextDescriptors) ?? []) + ((try? machO.swift.protocolDescriptors) ?? []).map { ContextDescriptorWrapper.protocol($0) }
        var moduleNames: Set<String> = []
        for descriptor in descriptors {
            if let moduleName = moduleName(of: descriptor, in: context) {
                moduleNames.insert(moduleName)
            }
        }
        return moduleNames
    }

    private static func moduleName(of descriptor: ContextDescriptorWrapper, in context: some ReadingContext) -> String? {
        var current: ContextDescriptorWrapper? = descriptor
        while let currentContext = current {
            if case .module(let moduleDescriptor) = currentContext {
                return try? moduleDescriptor.name(in: context)
            }
            current = try? currentContext.parent(in: context)?.resolved
        }
        return nil
    }

    /// `DVTFoundation.DVTTeamCredential` from the field descriptor's
    /// `$s13DVTFoundation17DVTTeamCredentialP`.
    private static func qualifiedName(ofSwiftMangledName mangledName: String) -> String? {
        guard let node = try? demangleAsNodeTransient(mangledName), let protocolNode = node.first(of: .protocol) else { return nil }
        return NodeTypeNaming.protocolQualifiedName(of: protocolNode)
    }

    /// The qualified name a `_TtP…_` runtime name spells, or `nil` for any
    /// other name: a renamed protocol's or an Objective-C one's.
    package static func qualifiedName(ofDefaultRuntimeName runtimeName: String) -> String? {
        guard runtimeName.hasPrefix("_TtP") else { return nil }
        guard let node = try? demangleAsNodeTransient(runtimeName), let protocolNode = node.first(of: .protocol) else { return nil }
        return NodeTypeNaming.protocolQualifiedName(of: protocolNode)
    }

    /// The modern spelling of a `_TtP…_` runtime name, for a protocol the
    /// fallback found: no field descriptor spells it.
    private static func swiftMangledName(ofDefaultRuntimeName runtimeName: String) -> String? {
        guard let node = try? demangleAsNodeTransient(runtimeName), let protocolNode = node.first(of: .protocol) else { return nil }
        return try? mangleAsString(Node.createTransient(kind: .global, child: protocolNode))
    }

    private static func baseName(of qualifiedName: String) -> String {
        qualifiedName.split(separator: ".").last.map(String.init) ?? qualifiedName
    }
}
