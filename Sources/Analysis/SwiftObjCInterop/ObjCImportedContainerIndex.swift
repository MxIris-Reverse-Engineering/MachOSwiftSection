import Foundation
import FoundationToolbox
import MachOKit
import MachOSwiftSection
@_spi(Core) import MachOObjCSection
@_spi(Internals) import MachOCaches

/// One Objective-C class or category of an image, as read for importing it
/// into Swift (evolution proposal `objc-imported-declarations`): its methods
/// and properties as the method and property lists record them, in their
/// order, before anything is named.
package struct ObjCImportedContainerRecord: Sendable {
    package enum Kind: Sendable, Hashable {
        case `class`
        /// A category, by its own name (`NSTouchBar` of `NSView(NSTouchBar)`).
        case category(name: String)
    }

    package struct Method: Sendable, Hashable {
        package let selector: String
        /// The method list's encoding (`v24@0:8@16`): every object is `@`.
        package let typeEncoding: String
        package let implementationOffset: Int?
    }

    package struct Property: Sendable, Hashable {
        package let name: String
        /// The attribute string (`T@"NSString",C,N,V_title`).
        package let attributes: String
    }

    package let kind: Kind
    /// The class's runtime name — the category's target for a category.
    package let classRuntimeName: String
    /// A class's superclass by runtime name; `nil` for a root class, a
    /// superclass the reader cannot name, and a category.
    package let superclassRuntimeName: String?
    /// The protocols the class or category adopts, by runtime name.
    package let protocolRuntimeNames: [String]
    /// Whether the class data's Swift bit is set: a Swift class registered
    /// with the Objective-C runtime. Always `false` for a category.
    package let isSwiftClass: Bool
    package let instanceMethods: [Method]
    package let classMethods: [Method]
    package let instanceProperties: [Property]
    package let classProperties: [Property]

    /// The name a category is listed under, `NSView(NSTouchBar)` — the same
    /// `uniqueName` MachOObjCSection's models give it; a class's runtime name.
    package var uniqueName: String {
        switch kind {
        case .class: classRuntimeName
        case .category(let name): "\(classRuntimeName)(\(name))"
        }
    }
}

/// Per-image index of the Objective-C classes, categories and protocol
/// records an image defines, read for importing them into Swift (evolution
/// proposal `objc-imported-declarations`). Built once per image on first use
/// through the shared-cache machinery, and evicted with the other ObjC-side
/// per-image state. It holds names and encodings only, no `NodeReference`.
@Loggable(.private, subsystem: "com.machoswiftsection.swift-inspection", category: "ObjCImportedContainerIndex")
package final class ObjCImportedContainerIndex: @unchecked Sendable {
    package static let shared = ObjCImportedContainerIndex()

    private let cache = SharedCache<Storage>(evictionGroup: .objcHierarchy)

    private init() {}

    package final class Storage: @unchecked Sendable {
        let classRecordsByRuntimeName: [String: ObjCImportedContainerRecord]
        let categoryRecordsByUniqueName: [String: ObjCImportedContainerRecord]
        /// Swift's record of a protocol when clang emitted one under the
        /// same name too, as `SwiftDeclaredObjCProtocolIndex` keeps it.
        let protocolRecordsByRuntimeName: [String: ObjCProtocolRecord]

        init(classRecordsByRuntimeName: [String: ObjCImportedContainerRecord], categoryRecordsByUniqueName: [String: ObjCImportedContainerRecord], protocolRecordsByRuntimeName: [String: ObjCProtocolRecord]) {
            self.classRecordsByRuntimeName = classRecordsByRuntimeName
            self.categoryRecordsByUniqueName = categoryRecordsByUniqueName
            self.protocolRecordsByRuntimeName = protocolRecordsByRuntimeName
        }
    }

    package func storage(in machO: some MachORepresentableWithCache) -> Storage? {
        cache.storage(in: machO) { machO in
            machO.objcImplementationClassReader.map { Self.build(in: $0) }
        }
    }

    package func remove(for machO: some MachORepresentableWithCache) {
        cache.remove(for: machO)
    }

    // MARK: - Queries

    /// The class the Objective-C runtime knows as `runtimeName`, when this
    /// image defines it.
    package func classRecord(named runtimeName: String, in machO: some MachORepresentableWithCache) -> ObjCImportedContainerRecord? {
        storage(in: machO)?.classRecordsByRuntimeName[runtimeName]
    }

    /// The category listed as `uniqueName` (`NSView(NSTouchBar)`), when this
    /// image defines it.
    package func categoryRecord(uniqueName: String, in machO: some MachORepresentableWithCache) -> ObjCImportedContainerRecord? {
        storage(in: machO)?.categoryRecordsByUniqueName[uniqueName]
    }

    /// The image's record of the protocol the runtime knows as
    /// `runtimeName`. An image holds a record of every protocol it adopts or
    /// names, not only of the ones it defines.
    package func protocolRecord(named runtimeName: String, in machO: some MachORepresentableWithCache) -> ObjCProtocolRecord? {
        storage(in: machO)?.protocolRecordsByRuntimeName[runtimeName]
    }

    /// Every class of the image by runtime name, sorted.
    package func classRuntimeNames(in machO: some MachORepresentableWithCache) -> [String] {
        storage(in: machO)?.classRecordsByRuntimeName.keys.sorted() ?? []
    }

    /// Every category of the image by unique name, sorted.
    package func categoryUniqueNames(in machO: some MachORepresentableWithCache) -> [String] {
        storage(in: machO)?.categoryRecordsByUniqueName.keys.sorted() ?? []
    }

    // MARK: - Build

    private static func build<MachO: ObjCImplementationClassReading & MachOSwiftSectionRepresentableWithCache>(in machO: MachO) -> Storage {
        var classRecordsByRuntimeName: [String: ObjCImportedContainerRecord] = [:]
        for classObject in machO.objcImplementationClassObjects() ?? [] {
            guard let readOnlyData = machO.instanceReadOnlyData(of: classObject),
                  let runtimeName = machO.className(of: readOnlyData)
            else {
                #log(.debug, "Skipped a class object whose class data the reader could not read.")
                continue
            }
            let metaClassReadOnlyData = machO.metaClass(of: classObject).flatMap { machO.instanceReadOnlyData(of: $0) }
            let record = ObjCImportedContainerRecord(
                kind: .class,
                classRuntimeName: runtimeName,
                superclassRuntimeName: machO.superclassName(of: classObject),
                protocolRuntimeNames: machO.protocolNames(of: readOnlyData),
                isSwiftClass: classObject.isSwiftStable,
                instanceMethods: methods(machO.methods(of: readOnlyData)),
                classMethods: metaClassReadOnlyData.map { methods(machO.methods(of: $0)) } ?? [],
                instanceProperties: properties(machO.properties(of: readOnlyData)),
                classProperties: metaClassReadOnlyData.map { properties(machO.properties(of: $0)) } ?? []
            )
            // A name listed twice keeps its first class object.
            if classRecordsByRuntimeName[runtimeName] == nil {
                classRecordsByRuntimeName[runtimeName] = record
            }
        }

        var categoryRecordsByUniqueName: [String: ObjCImportedContainerRecord] = [:]
        for category in machO.objcCategories() ?? [] {
            guard let targetClassName = machO.targetClassName(of: category),
                  let categoryName = machO.categoryName(of: category)
            else { continue }
            let record = ObjCImportedContainerRecord(
                kind: .category(name: categoryName),
                classRuntimeName: targetClassName,
                superclassRuntimeName: nil,
                protocolRuntimeNames: machO.protocolNames(of: category),
                isSwiftClass: false,
                instanceMethods: methods(machO.instanceMethods(of: category)),
                classMethods: methods(machO.classMethods(of: category)),
                instanceProperties: properties(machO.instanceProperties(of: category)),
                classProperties: properties(machO.classProperties(of: category))
            )
            if categoryRecordsByUniqueName[record.uniqueName] == nil {
                categoryRecordsByUniqueName[record.uniqueName] = record
            }
        }

        // Swift's record first: a name clang also emitted keeps Swift's.
        var protocolRecordsByRuntimeName: [String: ObjCProtocolRecord] = [:]
        for record in machO.objcProtocolRecords() where protocolRecordsByRuntimeName[record.runtimeName].map({ !$0.isEmittedBySwift && record.isEmittedBySwift }) ?? true {
            protocolRecordsByRuntimeName[record.runtimeName] = record
        }

        return Storage(
            classRecordsByRuntimeName: classRecordsByRuntimeName,
            categoryRecordsByUniqueName: categoryRecordsByUniqueName,
            protocolRecordsByRuntimeName: protocolRecordsByRuntimeName
        )
    }

    private static func methods(_ rawMethods: [RawObjCMethod]) -> [ObjCImportedContainerRecord.Method] {
        rawMethods.map { ObjCImportedContainerRecord.Method(selector: $0.selector, typeEncoding: $0.typeEncoding, implementationOffset: $0.implementationOffset) }
    }

    private static func properties(_ properties: [ObjCImplementationClassFacts.Property]) -> [ObjCImportedContainerRecord.Property] {
        properties.map { ObjCImportedContainerRecord.Property(name: $0.name, attributes: $0.attributes) }
    }
}
