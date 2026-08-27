#if os(macOS)

import APINotes
import Foundation
import SwiftPrinting

/// The name mappings mined from a set of `.apinotes` files: C name ↔ Swift
/// name (for `SwiftName` renames) and C name → declaring module.
///
/// Rename tables are split **per declaration category**, because a C name is
/// only unique per category: ObjC declares both a class and a protocol named
/// `NSObject`, and only the protocol carries a `SwiftName` rename
/// (`NSObjectProtocol`) — one merged table rewrote every class reference with
/// the protocol's rename.
///
/// Built once from parsed files and immutable afterwards; the owning
/// `TypeDatabase` actor provides all synchronization.
@available(macOS 13.0, *)
package struct APINotesIndex: Sendable {
    package struct Name: Sendable, Equatable {
        /// The module whose APINotes file declares the mapping.
        package let moduleName: String
        package let name: String

        package init(moduleName: String, name: String) {
            self.moduleName = moduleName
            self.name = name
        }
    }

    /// C class name → renamed Swift name (`Classes` entries).
    package private(set) var classSwiftNamesByCName: [String: Name] = [:]

    /// C protocol name → renamed Swift name (`Protocols` entries, e.g.
    /// `NSObject` → `NSObjectProtocol`).
    package private(set) var protocolSwiftNamesByCName: [String: Name] = [:]

    /// C tag / enumerator / typedef name → renamed Swift name, e.g.
    /// `NSActivityOptions` → `ProcessInfo.ActivityOptions`.
    package private(set) var valueTypeSwiftNamesByCName: [String: Name] = [:]

    /// Renamed Swift name → original C name, all categories merged (renamed
    /// spellings do not collide the way C names do).
    package private(set) var cNamesBySwiftName: [String: Name] = [:]

    /// C name → declaring module, for **every** listed entity, renamed or
    /// not. An APINotes file is the compiler's own record of which module a C
    /// declaration belongs to, so attribution registers unconditionally —
    /// including `SwiftPrivate` entities, whose C name still appears in
    /// manglings even though their Swift spelling is underscored.
    package private(set) var moduleNamesByCName: [String: String] = [:]

    package init(files: [APINotesFile]) {
        register(files: files)
    }

    /// Appends more files to the index. Within every table a later entry
    /// overwrites an earlier same-name one — the ordering hook the
    /// supplementary-file merge priority rides on (evolution proposal 0010:
    /// SDK APINotes first, then user-supplied files in caller order).
    package mutating func register(files: [APINotesFile]) {
        for file in files {
            let module = file.apiNotesModule
            registerEntities(module.classes, declaredIn: file.moduleName, into: \.classSwiftNamesByCName)
            registerEntities(module.protocols, declaredIn: file.moduleName, into: \.protocolSwiftNamesByCName)
            registerEntities(module.tags, declaredIn: file.moduleName, into: \.valueTypeSwiftNamesByCName)
            registerEntities(module.enumerators, declaredIn: file.moduleName, into: \.valueTypeSwiftNamesByCName)
            registerEntities(module.typedefs, declaredIn: file.moduleName, into: \.valueTypeSwiftNamesByCName)
        }
    }

    /// The rename for `cName` in `category`. `.other` (a reference whose
    /// mangling does not pin the category, e.g. a typealias) consults the
    /// value-type then class tables, but never the protocol table — protocol
    /// references always mangle as protocols, and the `NSObject` name split
    /// is exactly what that isolation protects.
    ///
    /// `.objcClass` falls back to the value-type table on a class-table miss:
    /// a CF-bridged type reaches field metadata as a *foreign class* node
    /// spelled with its C tag name (`AGGraphStorage`, `CGContext` — the
    /// consuming binary emits a class-kind foreign descriptor for it), while
    /// its APINotes entry sits under `Tags`/`Typedefs` per C semantics. A tag
    /// and an ObjC class live in different C namespaces so they *can* share a
    /// name in principle, but the class table is consulted first, and a
    /// rename that exists only tag-side while a same-named distinct ObjC
    /// class is being referenced has no known real-world instance.
    package func swiftName(forCName cName: String, category: CImportedTypeNameCategory) -> Name? {
        switch category {
        case .objcClass:
            return classSwiftNamesByCName[cName] ?? valueTypeSwiftNamesByCName[cName]
        case .objcProtocol:
            return protocolSwiftNamesByCName[cName]
        case .valueType:
            return valueTypeSwiftNamesByCName[cName]
        case .other:
            return valueTypeSwiftNamesByCName[cName] ?? classSwiftNamesByCName[cName]
        }
    }

    package func cName(forSwiftName swiftName: String) -> Name? {
        cNamesBySwiftName[swiftName]
    }

    package func moduleName(forCName cName: String) -> String? {
        moduleNamesByCName[cName]
    }

    private mutating func registerEntities(
        _ entities: [some CommonEntity]?,
        declaredIn moduleName: String,
        into renameTable: WritableKeyPath<Self, [String: Name]>
    ) {
        guard let entities else { return }
        for entity in entities {
            let cName = entity.name
            moduleNamesByCName[cName] = moduleName
            guard let swiftName = entity.swiftName, entity.isSwiftPrivate != true else { continue }
            self[keyPath: renameTable][cName] = Name(moduleName: moduleName, name: swiftName)
            cNamesBySwiftName[swiftName] = Name(moduleName: moduleName, name: cName)
        }
    }
}

#endif
