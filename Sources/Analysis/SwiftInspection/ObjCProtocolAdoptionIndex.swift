import Foundation
import MachOKit
import MachOSwiftSection
@_spi(Core) import MachOObjCSection
@_spi(Internals) import MachOCaches

/// The Objective-C protocols one Swift class adopts directly (evolution
/// proposal `swift-declared-objc-protocols`). An `@objc` protocol has no
/// witness table, so the compiler emits no conformance record for it; what
/// records the conformance is Objective-C metadata. The compiler lists the
/// protocols a declaration names in the protocol list of the class data it
/// emits for that declaration (`GenClass.cpp`'s `visitConformances`, over
/// `getLocalConformances(.OnlyExplicit)`): the class's own `class_ro_t` for
/// the class declaration, a category for each extension. A non-`@objc`
/// protocol the declaration names contributes the `@objc` protocols it
/// inherits (`getObjCProtocols`).
package struct ObjCProtocolAdoption: Sendable, Hashable {
    /// The class's runtime name.
    package let classRuntimeName: String
    /// The protocols the class's `class_ro_t` lists, by runtime name.
    package let declaredProtocolRuntimeNames: [String]
    /// The protocols each of the image's categories on the class lists, one
    /// entry per category that lists any.
    package let categoryProtocolRuntimeNames: [[String]]

    /// Every protocol the class adopts directly, its declaration's first.
    package var allProtocolRuntimeNames: [String] {
        declaredProtocolRuntimeNames + categoryProtocolRuntimeNames.flatMap(\.self)
    }
}

/// Per-image index of the Objective-C protocols the image's Swift classes
/// adopt: every Swift class of `__objc_classlist`, then those without a class
/// object (`SwiftClassWithoutClassObjectIndex`), each with its own protocol
/// list and the ones of the image's categories on it. A category on a class
/// with resilient ancestry targets the class's stub, whose name the reader
/// cannot read, and is missed.
///
/// Built once per image, lazily, and evicted with the other ObjC-side
/// per-image state.
package final class ObjCProtocolAdoptionIndex: @unchecked Sendable {
    package static let shared = ObjCProtocolAdoptionIndex()

    private let cache = SharedCache<Storage>(evictionGroup: .objcHierarchy)

    private init() {}

    package final class Storage: @unchecked Sendable {
        /// Class-list order, then the classes without a class object.
        let adoptions: [ObjCProtocolAdoption]

        let adoptionsByClassRuntimeName: [String: ObjCProtocolAdoption]

        /// Protocol runtime name → the runtime names of the classes adopting
        /// it directly, in the order of `adoptions`.
        let adopterClassRuntimeNamesByProtocolRuntimeName: [String: [String]]

        init(adoptions: [ObjCProtocolAdoption]) {
            self.adoptions = adoptions
            var adoptionsByClassRuntimeName: [String: ObjCProtocolAdoption] = [:]
            var adopterClassRuntimeNamesByProtocolRuntimeName: [String: [String]] = [:]
            for adoption in adoptions {
                adoptionsByClassRuntimeName[adoption.classRuntimeName] = adoption
                for protocolRuntimeName in Set(adoption.allProtocolRuntimeNames) {
                    adopterClassRuntimeNamesByProtocolRuntimeName[protocolRuntimeName, default: []].append(adoption.classRuntimeName)
                }
            }
            self.adoptionsByClassRuntimeName = adoptionsByClassRuntimeName
            self.adopterClassRuntimeNamesByProtocolRuntimeName = adopterClassRuntimeNamesByProtocolRuntimeName
        }
    }

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

    /// What the Swift class the runtime knows as `classRuntimeName` adopts;
    /// `nil` when the image defines no Swift class of that name.
    package func adoption(ofClassRuntimeName classRuntimeName: String, in machO: some MachORepresentableWithCache) -> ObjCProtocolAdoption? {
        storage(in: machO)?.adoptionsByClassRuntimeName[classRuntimeName]
    }

    /// The runtime names of the image's Swift classes adopting the protocol
    /// directly, in class-list order.
    package func adopterClassRuntimeNames(ofProtocolRuntimeName protocolRuntimeName: String, in machO: some MachORepresentableWithCache) -> [String] {
        storage(in: machO)?.adopterClassRuntimeNamesByProtocolRuntimeName[protocolRuntimeName] ?? []
    }

    // MARK: - Build

    private static func build<MachO: ObjCImplementationClassReading & MachOSwiftSectionRepresentableWithCache>(in machO: MachO) -> Storage {
        var classRuntimeNames: [String] = []
        var declaredProtocolsByClass: [String: [String]] = [:]
        for classObject in machO.objcImplementationClassObjects() ?? [] where classObject.isSwift {
            guard let readOnlyData = machO.instanceReadOnlyData(of: classObject),
                  let className = machO.className(of: readOnlyData), !className.isEmpty,
                  declaredProtocolsByClass[className] == nil
            else { continue }
            classRuntimeNames.append(className)
            declaredProtocolsByClass[className] = machO.protocolNames(of: readOnlyData)
        }
        for swiftClass in SwiftClassWithoutClassObjectIndex.shared.classes(in: machO) where declaredProtocolsByClass[swiftClass.name] == nil {
            guard let readOnlyData = swiftClass.readOnlyData(in: machO) else { continue }
            classRuntimeNames.append(swiftClass.name)
            declaredProtocolsByClass[swiftClass.name] = machO.protocolNames(of: readOnlyData)
        }

        var categoryProtocolsByClass: [String: [[String]]] = [:]
        for category in machO.objcCategories() ?? [] {
            guard let targetClassName = machO.targetClassName(of: category), declaredProtocolsByClass[targetClassName] != nil else { continue }
            let protocolNames = machO.protocolNames(of: category)
            if !protocolNames.isEmpty {
                categoryProtocolsByClass[targetClassName, default: []].append(protocolNames)
            }
        }

        let adoptions = classRuntimeNames.map { className in
            ObjCProtocolAdoption(
                classRuntimeName: className,
                declaredProtocolRuntimeNames: declaredProtocolsByClass[className] ?? [],
                categoryProtocolRuntimeNames: categoryProtocolsByClass[className] ?? []
            )
        }
        return Storage(adoptions: adoptions)
    }
}
