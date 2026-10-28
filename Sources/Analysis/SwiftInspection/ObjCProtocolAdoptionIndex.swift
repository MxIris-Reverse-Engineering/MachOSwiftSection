import Foundation
import MachOKit
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Core) import MachOObjCSection
@_spi(Internals) import MachOCaches

/// The Objective-C protocols one Swift class of the image adopts in its own
/// class data (evolution proposal `swift-declared-objc-protocols`). An
/// `@objc` protocol has no witness table, so the compiler emits no
/// conformance record for it; what records the conformance is Objective-C
/// metadata. The compiler lists the protocols a declaration names in the
/// protocol list of the class data it emits for it (`GenClass.cpp`'s
/// `visitConformances`, over `getLocalConformances(.OnlyExplicit)`) — and it
/// folds the extensions the class's own module declares into the class's
/// own data, so `class_ro_t` lists theirs too. A non-`@objc` protocol a
/// declaration names contributes the `@objc` protocols it inherits
/// (`getObjCProtocols`).
package struct ObjCProtocolAdoption: Sendable, Hashable {
    /// The class's runtime name.
    package let classRuntimeName: String
    /// The class's Swift qualified name, the key a declaration looks its
    /// adoption up by; `nil` when the runtime name names no Swift class.
    package let swiftClassQualifiedName: String?
    /// The protocols the class's `class_ro_t` lists, by runtime name.
    package let declaredProtocolRuntimeNames: [String]
    /// The listed protocols a Swift protocol the class conforms to inherits:
    /// the compiler lists those too, so they say nothing the Swift
    /// conformance does not. Known for the image's own Swift protocols only —
    /// another image's requirement signature is not read.
    package let impliedProtocolRuntimeNames: Set<String>
}

/// The Objective-C protocols one of the image's categories lists: an
/// extension the image declares of a class another module declares — an
/// Objective-C class, or a Swift class of another module — since one of the
/// class's own module is folded into the class's data.
package struct ObjCCategoryProtocolAdoption: Sendable, Hashable {
    /// The category's offset in the image.
    package let offset: Int
    /// The extended class's runtime name.
    package let classRuntimeName: String
    /// The protocols the category lists, by runtime name.
    package let protocolRuntimeNames: [String]
    /// Those a Swift protocol the image conforms the class to inherits, as
    /// for ``ObjCProtocolAdoption/impliedProtocolRuntimeNames``.
    package let impliedProtocolRuntimeNames: Set<String>
}

/// Per-image index of the Objective-C protocols the image adopts: the ones
/// each Swift class of `__objc_classlist` and each without a class object
/// (`SwiftClassWithoutClassObjectIndex`) lists in its own class data, and
/// the ones each category lists. A category on a class with resilient
/// ancestry targets the class's stub, whose name the reader cannot read,
/// and is missed.
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

        /// Category-list order; only the categories that list a protocol.
        let categoryAdoptions: [ObjCCategoryProtocolAdoption]

        /// Keyed by Swift qualified name; a name several classes print as
        /// (same-named private classes) keys none of them.
        let adoptionsBySwiftClassQualifiedName: [String: ObjCProtocolAdoption]

        /// Protocol runtime name → the runtime names of the classes adopting
        /// it directly: the image's classes in the order of `adoptions`, then
        /// the classes its categories extend.
        let adopterClassRuntimeNamesByProtocolRuntimeName: [String: [String]]

        init(adoptions: [ObjCProtocolAdoption], categoryAdoptions: [ObjCCategoryProtocolAdoption]) {
            self.adoptions = adoptions
            self.categoryAdoptions = categoryAdoptions
            var adoptionsBySwiftClassQualifiedName: [String: ObjCProtocolAdoption] = [:]
            var ambiguousQualifiedNames: Set<String> = []
            var adopterClassRuntimeNamesByProtocolRuntimeName: [String: [String]] = [:]
            func noteAdopter(_ classRuntimeName: String, of protocolRuntimeNames: [String]) {
                for protocolRuntimeName in Set(protocolRuntimeNames) where adopterClassRuntimeNamesByProtocolRuntimeName[protocolRuntimeName]?.contains(classRuntimeName) != true {
                    adopterClassRuntimeNamesByProtocolRuntimeName[protocolRuntimeName, default: []].append(classRuntimeName)
                }
            }
            for adoption in adoptions {
                if let qualifiedName = adoption.swiftClassQualifiedName,
                   adoptionsBySwiftClassQualifiedName.updateValue(adoption, forKey: qualifiedName) != nil {
                    ambiguousQualifiedNames.insert(qualifiedName)
                }
                noteAdopter(adoption.classRuntimeName, of: adoption.declaredProtocolRuntimeNames)
            }
            for categoryAdoption in categoryAdoptions {
                noteAdopter(categoryAdoption.classRuntimeName, of: categoryAdoption.protocolRuntimeNames)
            }
            for qualifiedName in ambiguousQualifiedNames {
                adoptionsBySwiftClassQualifiedName[qualifiedName] = nil
            }
            self.adoptionsBySwiftClassQualifiedName = adoptionsBySwiftClassQualifiedName
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

    /// What the Swift class whose qualified name is `qualifiedName` adopts in
    /// its own class data; `nil` when the image defines no such class, or
    /// several print as that name.
    package func adoption(ofSwiftClassQualifiedName qualifiedName: String, in machO: some MachORepresentableWithCache) -> ObjCProtocolAdoption? {
        storage(in: machO)?.adoptionsBySwiftClassQualifiedName[qualifiedName]
    }

    /// The image's categories that list a protocol, in category-list order.
    package func categoryAdoptions(in machO: some MachORepresentableWithCache) -> [ObjCCategoryProtocolAdoption] {
        storage(in: machO)?.categoryAdoptions ?? []
    }

    /// The runtime names of the classes adopting the protocol directly: the
    /// image's Swift classes in class-list order, then the classes its
    /// categories extend.
    package func adopterClassRuntimeNames(ofProtocolRuntimeName protocolRuntimeName: String, in machO: some MachORepresentableWithCache) -> [String] {
        storage(in: machO)?.adopterClassRuntimeNamesByProtocolRuntimeName[protocolRuntimeName] ?? []
    }

    // MARK: - Build

    private static func build<MachO: ObjCImplementationClassReading & MachOSwiftSectionRepresentableWithCache>(in machO: MachO) -> Storage {
        var classRuntimeNames: [String] = []
        var declaredProtocolsByClass: [String: [String]] = [:]
        var qualifiedNamesByClass: [String: String] = [:]
        for classObject in machO.objcImplementationClassObjects() ?? [] where classObject.isSwift {
            guard let readOnlyData = machO.instanceReadOnlyData(of: classObject),
                  let className = machO.className(of: readOnlyData), !className.isEmpty,
                  declaredProtocolsByClass[className] == nil
            else { continue }
            classRuntimeNames.append(className)
            declaredProtocolsByClass[className] = machO.protocolNames(of: readOnlyData)
            qualifiedNamesByClass[className] = ObjCRuntimeNames.swiftClassNode(forRuntimeName: className, in: machO).flatMap(NodeTypeNaming.nominalQualifiedName(of:))
        }
        for swiftClass in SwiftClassWithoutClassObjectIndex.shared.classes(in: machO) where declaredProtocolsByClass[swiftClass.name] == nil {
            guard let readOnlyData = swiftClass.readOnlyData(in: machO) else { continue }
            classRuntimeNames.append(swiftClass.name)
            declaredProtocolsByClass[swiftClass.name] = machO.protocolNames(of: readOnlyData)
            qualifiedNamesByClass[swiftClass.name] = swiftClass.qualifiedName
        }

        var categories: [(offset: Int, classRuntimeName: String, protocolRuntimeNames: [String])] = []
        for category in machO.objcCategories() ?? [] {
            guard let targetClassName = machO.targetClassName(of: category), !targetClassName.isEmpty else { continue }
            let protocolNames = machO.protocolNames(of: category)
            if !protocolNames.isEmpty {
                categories.append((category.offset, targetClassName, protocolNames))
            }
        }

        // The classes implied protocols are looked for on: the image's own by
        // qualified name, the ones its categories extend by runtime name.
        var classKeys: Set<ClassKey> = []
        for className in classRuntimeNames where !(declaredProtocolsByClass[className] ?? []).isEmpty {
            if let qualifiedName = qualifiedNamesByClass[className] {
                classKeys.insert(.swift(qualifiedName: qualifiedName))
            }
        }
        for category in categories {
            classKeys.insert(classKey(ofRuntimeName: category.classRuntimeName, qualifiedNamesByClass: qualifiedNamesByClass))
        }
        let impliedProtocolsByClass = impliedProtocolRuntimeNames(ofClasses: classKeys, in: machO)

        let adoptions = classRuntimeNames.map { className in
            let qualifiedName = qualifiedNamesByClass[className]
            return ObjCProtocolAdoption(
                classRuntimeName: className,
                swiftClassQualifiedName: qualifiedName,
                declaredProtocolRuntimeNames: declaredProtocolsByClass[className] ?? [],
                impliedProtocolRuntimeNames: qualifiedName.flatMap { impliedProtocolsByClass[.swift(qualifiedName: $0)] } ?? []
            )
        }
        let categoryAdoptions = categories.map { category in
            ObjCCategoryProtocolAdoption(
                offset: category.offset,
                classRuntimeName: category.classRuntimeName,
                protocolRuntimeNames: category.protocolRuntimeNames,
                impliedProtocolRuntimeNames: impliedProtocolsByClass[classKey(ofRuntimeName: category.classRuntimeName, qualifiedNamesByClass: qualifiedNamesByClass)] ?? []
            )
        }
        return Storage(adoptions: adoptions, categoryAdoptions: categoryAdoptions)
    }

    /// A class as a conformance record names it: a Swift class by its
    /// descriptor, read as its qualified name; an Objective-C class by its
    /// runtime name.
    private enum ClassKey: Hashable {
        case swift(qualifiedName: String)
        case objc(runtimeName: String)
    }

    private static func classKey(ofRuntimeName runtimeName: String, qualifiedNamesByClass: [String: String]) -> ClassKey {
        if let qualifiedName = qualifiedNamesByClass[runtimeName] ?? NodeTypeNaming.swiftClassQualifiedName(fromRuntimeName: runtimeName) {
            return .swift(qualifiedName: qualifiedName)
        }
        return .objc(runtimeName: runtimeName)
    }

    /// For each class of `classKeys`, the Objective-C protocols the image's
    /// own Swift protocols it conforms to inherit, at any depth. A
    /// conformance to a protocol without such an ancestor is skipped before
    /// its type is named, which is most of them.
    private static func impliedProtocolRuntimeNames(ofClasses classKeys: Set<ClassKey>, in machO: some MachOSwiftSectionRepresentableWithCache) -> [ClassKey: Set<String>] {
        guard !classKeys.isEmpty, let conformances = try? machO.swift.protocolConformances else { return [:] }
        var inheritedByProtocolOffset: [Int: Set<String>] = [:]
        var impliedByClass: [ClassKey: Set<String>] = [:]
        for conformance in conformances {
            guard case .element(let protocolDescriptor)? = conformance.protocol else { continue }
            let inherited = inheritedObjCProtocolRuntimeNames(of: protocolDescriptor, cache: &inheritedByProtocolOffset, in: machO)
            guard !inherited.isEmpty, let classKey = classKey(of: conformance.typeReference, in: machO), classKeys.contains(classKey) else { continue }
            impliedByClass[classKey, default: []].formUnion(inherited)
        }
        return impliedByClass
    }

    private static func classKey(of typeReference: ResolvedTypeReference, in machO: some MachOSwiftSectionRepresentableWithCache) -> ClassKey? {
        switch typeReference {
        case .directTypeDescriptor(.type(.class(let classDescriptor))?):
            guard let contextNode = try? SymbolicDemangler.demangleContext(for: .type(.class(classDescriptor)), in: machO.context),
                  let qualifiedName = NodeTypeNaming.nominalQualifiedName(of: contextNode)
            else { return nil }
            return .swift(qualifiedName: qualifiedName)
        case .directObjCClassName(let runtimeName?):
            return .objc(runtimeName: runtimeName)
        case .indirectObjCClass(.symbol(let symbol)?):
            let prefix = "_OBJC_CLASS_$_"
            guard symbol.name.hasPrefix(prefix) else { return nil }
            return .objc(runtimeName: String(symbol.name.dropFirst(prefix.count)))
        default:
            return nil
        }
    }

    /// The Objective-C protocols a Swift protocol of the image inherits,
    /// directly or through the image's other Swift protocols; memoized per
    /// descriptor, which also ends a cycle.
    private static func inheritedObjCProtocolRuntimeNames(of descriptor: ProtocolDescriptor, cache: inout [Int: Set<String>], in machO: some MachOSwiftSectionRepresentableWithCache) -> Set<String> {
        if let cached = cache[descriptor.offset] { return cached }
        cache[descriptor.offset] = []
        guard let protocolType = try? MachOSwiftSection.`Protocol`(descriptor: descriptor, in: machO.context) else { return [] }
        var names: Set<String> = []
        // `Self`'s protocol requirements are the inherited protocols.
        for requirement in protocolType.requirementInSignatures where requirement.paramManagledName.rawString == "x" {
            guard case .protocol(.element(let reference)) = requirement.content else { continue }
            switch reference {
            case .objc(let objcProtocol):
                if let name = try? objcProtocol.name(in: machO.context) {
                    names.insert(name)
                }
            case .swift(let inheritedDescriptor):
                names.formUnion(inheritedObjCProtocolRuntimeNames(of: inheritedDescriptor, cache: &cache, in: machO))
            }
        }
        cache[descriptor.offset] = names
        return names
    }
}
