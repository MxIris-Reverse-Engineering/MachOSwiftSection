#if os(macOS)

import APINotes
import Foundation

/// The name mappings mined from a set of `.apinotes` files: C name ↔ Swift
/// name (for `SwiftName` renames) and C name → declaring module.
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

    /// C name → renamed Swift name, e.g. `NSActivityOptions` →
    /// `ProcessInfo.ActivityOptions` (declared in Foundation).
    package private(set) var swiftNamesByCName: [String: Name] = [:]

    /// Renamed Swift name → original C name, the reverse direction.
    package private(set) var cNamesBySwiftName: [String: Name] = [:]

    /// C name → declaring module, for **every** listed entity, renamed or
    /// not. An APINotes file is the compiler's own record of which module a C
    /// declaration belongs to, so attribution registers unconditionally —
    /// including `SwiftPrivate` entities, whose C name still appears in
    /// manglings even though their Swift spelling is underscored.
    package private(set) var moduleNamesByCName: [String: String] = [:]

    package init(files: [APINotesFile]) {
        for file in files {
            let module = file.apiNotesModule
            registerEntities(module.classes, declaredIn: file.moduleName)
            registerEntities(module.protocols, declaredIn: file.moduleName)
            registerEntities(module.tags, declaredIn: file.moduleName)
            registerEntities(module.enumerators, declaredIn: file.moduleName)
            registerEntities(module.typedefs, declaredIn: file.moduleName)
        }
    }

    package func swiftName(forCName cName: String) -> Name? {
        swiftNamesByCName[cName]
    }

    package func cName(forSwiftName swiftName: String) -> Name? {
        cNamesBySwiftName[swiftName]
    }

    package func moduleName(forCName cName: String) -> String? {
        moduleNamesByCName[cName]
    }

    private mutating func registerEntities(_ entities: [some CommonEntity]?, declaredIn moduleName: String) {
        guard let entities else { return }
        for entity in entities {
            let cName = entity.name
            moduleNamesByCName[cName] = moduleName
            guard let swiftName = entity.swiftName, entity.isSwiftPrivate != true else { continue }
            swiftNamesByCName[cName] = Name(moduleName: moduleName, name: swiftName)
            cNamesBySwiftName[swiftName] = Name(moduleName: moduleName, name: cName)
        }
    }
}

#endif
