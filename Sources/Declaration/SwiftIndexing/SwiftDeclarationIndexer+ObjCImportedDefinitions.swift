import Foundation
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection
import SwiftObjCInterop
import SwiftDeclaration

/// The image's Objective-C classes, categories and protocols as Swift imports
/// them (evolution proposal `objc-imported-declarations`). A definition is
/// made when asked for — an image can define thousands of classes — and
/// indexes itself on its first print. A class or category Swift implements
/// comes with the Swift definitions the printer takes its members from.
extension SwiftDeclarationIndexer {
    /// The runtime names of the Objective-C classes the image defines, sorted.
    public var objcImportedClassRuntimeNames: [String] {
        ObjCImportedContainerIndex.shared.classRuntimeNames(in: machO)
    }

    /// The names the image's Objective-C categories are listed under
    /// (`NSView(NSTouchBar)`), sorted.
    public var objcImportedCategoryUniqueNames: [String] {
        ObjCImportedContainerIndex.shared.categoryUniqueNames(in: machO)
    }

    /// The class the Objective-C runtime knows as `runtimeName` as Swift
    /// imports it, or `nil` when the image defines no class of that name.
    /// It comes with the image's Swift extensions of the class, whose
    /// `@objc` members the linker merges into the class's own lists: a
    /// Swift class with its own definition, its extensions and its
    /// conformances; a class declared in Objective-C with its `@objc
    /// @implementation` bodies and the extensions adding `@objc` members.
    public func objcImportedClassDefinition(named runtimeName: String) -> ObjCImportedClassDefinition? {
        guard let record = ObjCImportedContainerIndex.shared.classRecord(named: runtimeName, in: machO) else { return nil }
        guard record.isSwiftClass else {
            return ObjCImportedClassDefinition(record: record, swiftClassDefinition: nil, swiftExtensions: swiftExtensions(ofObjCClassNamed: runtimeName), in: machO)
        }
        guard let classNode = ObjCRuntimeNames.swiftClassNode(forRuntimeName: runtimeName, in: machO) else {
            return ObjCImportedClassDefinition(record: record, swiftClassDefinition: nil, swiftExtensions: [], in: machO)
        }
        let typeNode = Node.createTransient(kind: .type, child: classNode)
        let typeName = TypeName(node: InternedNodeReferenceCache.shared.reference(interning: typeNode, in: machO), kind: .class)
        guard let swiftClassDefinition = allTypeDefinitions[typeName] else {
            return ObjCImportedClassDefinition(record: record, swiftClassDefinition: nil, swiftExtensions: [], in: machO)
        }
        let extensionName = typeName.extensionName
        let swiftExtensions = (typeExtensionDefinitions[extensionName] ?? []) + (conformanceExtensionDefinitions[extensionName] ?? [])
        return ObjCImportedClassDefinition(record: record, swiftClassDefinition: swiftClassDefinition, swiftExtensions: swiftExtensions, in: machO)
    }

    /// The category listed as `uniqueName` (`NSView(NSTouchBar)`) as Swift
    /// imports it, or `nil` when the image defines none. It comes with the
    /// image's Swift extensions of the class, which implement a category
    /// Swift wrote — an `@objc @implementation` of a category declared in a
    /// header, or a plain extension with `@objc` members.
    public func objcImportedCategoryDefinition(uniqueName: String) -> ObjCImportedCategoryDefinition? {
        guard let record = ObjCImportedContainerIndex.shared.categoryRecord(uniqueName: uniqueName, in: machO),
              case .category(let categoryName) = record.kind
        else { return nil }
        return ObjCImportedCategoryDefinition(record: record, categoryName: categoryName, swiftExtensions: swiftExtensions(ofObjCClassNamed: record.classRuntimeName), in: machO)
    }

    /// The image's Swift extensions of the class declared in Objective-C as
    /// `className` (`extension __C.NSView`).
    private func swiftExtensions(ofObjCClassNamed className: String) -> [ExtensionDefinition] {
        typeExtensionDefinitions.values.flatMap { $0 }.filter { extensionDefinition in
            ObjCImplementationClasses.cImportedClassName(of: extensionDefinition.extensionName.node) == className
        }
    }

    /// The protocol the Objective-C runtime knows as `runtimeName` as Swift
    /// imports it, read from the image's record of it; `nil` when the image
    /// holds none. An image holds a record of every protocol it adopts or
    /// names, not only of the ones it defines.
    public func objcImportedProtocolDefinition(named runtimeName: String) -> ObjCImportedProtocolDefinition? {
        guard let record = ObjCImportedContainerIndex.shared.protocolRecord(named: runtimeName, in: machO) else { return nil }
        return ObjCImportedProtocolDefinition(record: record, in: machO)
    }
}
