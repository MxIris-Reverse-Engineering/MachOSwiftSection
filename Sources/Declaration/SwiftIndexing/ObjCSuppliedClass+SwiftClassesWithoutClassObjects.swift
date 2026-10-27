import MachOKit
import MachOKitExtensions
import ObjCIndexing
import SwiftInspection

extension ObjCSuppliedClass {
    /// The Swift classes of `machO` the image keeps no class object for,
    /// read from their Swift metadata, for
    /// `ObjCInterfaceIndexer(machO:imagePath:suppliedClasses:eventHandler:)`
    /// (evolution proposal `objc-classes-without-class-objects`): every
    /// generic class, under its qualified name with its generic parameters
    /// (`Xcode_Service.MenuBarPanelWindow<A>`), and every class
    /// `__objc_stublist` registers — one whose metadata the Swift runtime
    /// allocates or initializes before the Objective-C runtime sees it (a
    /// resilient superclass, generic ancestry), which the compiler registers
    /// when an Objective-C class is among its ancestors — under its
    /// `class_ro_t` name. The superclass is named by its runtime name
    /// wherever the class list or the Objective-C runtime knows one, so the
    /// indexer links a chain through the image's own classes; a Swift
    /// superclass another image defines keeps its Swift spelling
    /// (`SwiftUI.NSHostingView<Xcode_Service.MenuBarLabel>`).
    ///
    /// Empty for a reader of another kind, and for an image built without
    /// Objective-C interop.
    public static func swiftClassesWithoutClassObjects(in machO: some MachORepresentableWithCache) -> [ObjCSuppliedClass] {
        SwiftClassWithoutClassObjectIndex.shared.classes(in: machO).filter { $0.kind == .generic || $0.hasObjectiveCAncestry }.map { swiftClass in
            ObjCSuppliedClass(
                name: swiftClass.name,
                superClassName: swiftClass.superclass.name.isEmpty ? nil : swiftClass.superclass.name,
                readOnlyDataOffset: swiftClass.readOnlyDataOffset,
                metaclassReadOnlyDataOffset: swiftClass.metaclassReadOnlyDataOffset,
                classStubOffset: swiftClass.classStubOffset,
                kind: Kind(swiftClass.kind)
            )
        }
    }
}

extension ObjCSuppliedClass.Kind {
    init(_ kind: SwiftClassWithoutClassObject.Kind) {
        switch kind {
        case .generic: self = .genericSwiftClass
        case .resilientAncestry: self = .swiftClassWithResilientAncestry
        case .genericAncestry: self = .swiftClassWithGenericAncestry
        }
    }
}
