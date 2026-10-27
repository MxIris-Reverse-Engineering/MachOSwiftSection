import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
import MachOObjCSection
@testable import MachOTestingSupport
@_spi(Internals) @testable import SwiftInspection

/// `SwiftClassWithoutClassObjectIndex` (evolution proposal
/// `objc-classes-without-class-objects`): the Swift classes
/// `__objc_classlist` does not list — generic ones, one with a resilient
/// superclass, ones with generic ancestry — their `class_ro_t` read from
/// Swift metadata through both readers, and the ObjC method table built
/// from it.
@Suite(.serialized, ExclusiveImageAccess(ClassesWithoutClassObjectsFixture.moduleName))
struct SwiftClassWithoutClassObjectIndexTests {
    private static let moduleName = ClassesWithoutClassObjectsFixture.moduleName

    private static let kitModuleName = ClassesWithoutClassObjectsFixture.kitModuleName

    private static let resilientChildRuntimeName = "_TtC\(moduleName.count)\(moduleName)14ResilientChild"

    private static let concreteSubclassRuntimeName = "_TtC\(moduleName.count)\(moduleName)16ConcreteSubclass"

    private static func classesByQualifiedName(in machO: some MachORepresentableWithCache) -> [String: SwiftClassWithoutClassObject] {
        Dictionary(SwiftClassWithoutClassObjectIndex.shared.classes(in: machO).map { ($0.qualifiedName, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The offset of the one Swift symbol whose name ends in `suffix`.
    private static func offset(ofSymbolEndingIn suffix: String, in machO: some MachORepresentable) -> Int? {
        let offsets = machO.swiftSymbols.filter { $0.name.hasSuffix(suffix) }.map(\.offset)
        return offsets.count == 1 ? offsets[0] : nil
    }

    private static func expectSelectors(of swiftClass: SwiftClassWithoutClassObject, in machO: some ObjCImplementationClassReading, instance instanceSelectors: Set<String>, class classSelectors: Set<String> = []) throws {
        let readOnlyData = try #require(swiftClass.readOnlyData(in: machO), "\(swiftClass.name)")
        #expect(!readOnlyData.isMetaClass, "\(swiftClass.name)")
        #expect(Set(machO.methods(of: readOnlyData).map(\.selector)).isSuperset(of: instanceSelectors), "\(swiftClass.name)")
        let metaclassReadOnlyData = try #require(swiftClass.metaclassReadOnlyData(in: machO), "\(swiftClass.name)")
        #expect(metaclassReadOnlyData.isMetaClass, "\(swiftClass.name)")
        #expect(Set(machO.methods(of: metaclassReadOnlyData).map(\.selector)).isSuperset(of: classSelectors), "\(swiftClass.name)")
    }

    private static func expectClasses(in machO: some ObjCImplementationClassReading, keepsLocalSymbols: Bool) throws {
        let classes = classesByQualifiedName(in: machO)

        // The negative control has a class object in the class list.
        #expect(classes["\(moduleName).PlainWidget"] == nil)

        let genericWidget = try #require(classes["\(moduleName).GenericWidget"])
        #expect(genericWidget.kind == .generic)
        #expect(genericWidget.name == "\(moduleName).GenericWidget<A>")
        #expect(genericWidget.superclass == .objectiveC(runtimeName: "NSObject"))
        #expect(genericWidget.hasObjectiveCAncestry)
        #expect(genericWidget.classStubOffset == nil)
        try expectSelectors(of: genericWidget, in: machO, instance: ["description", "poke"], class: ["classPoke"])

        let nestedGenericWidget = try #require(classes["\(moduleName).Namespace.NestedGenericWidget"])
        #expect(nestedGenericWidget.name == "\(moduleName).Namespace.NestedGenericWidget<A, B>")
        try expectSelectors(of: nestedGenericWidget, in: machO, instance: ["nestedPoke"])

        // The native object model: `SwiftObject` stands in for a superclass.
        let genericNativeRoot = try #require(classes["\(moduleName).GenericNativeRoot"])
        #expect(genericNativeRoot.kind == .generic)
        #expect(genericNativeRoot.superclass == .objectiveC(runtimeName: "_TtCs12_SwiftObject"))
        #expect(!genericNativeRoot.hasObjectiveCAncestry)

        // A resilient superclass: the descriptor records the stub, stripped
        // or not; the superclass is a Swift class of another image.
        let resilientChild = try #require(classes["\(moduleName).ResilientChild"])
        #expect(resilientChild.kind == .resilientAncestry)
        #expect(resilientChild.name == resilientChildRuntimeName)
        #expect(resilientChild.superclass == .swiftClass(displayName: "\(kitModuleName).ResilientBase"))
        #expect(resilientChild.hasObjectiveCAncestry)
        let resilientChildStubOffset = try #require(resilientChild.classStubOffset)
        if keepsLocalSymbols {
            // A public stub: `…CMs` names its isa word.
            #expect(resilientChildStubOffset == offset(ofSymbolEndingIn: "14ResilientChildCMs", in: machO))
        }
        try expectSelectors(of: resilientChild, in: machO, instance: ["description", "resilientPoke"])

        // A generic superclass of another image keeps its arguments.
        let resilientGenericChild = try #require(classes["\(moduleName).ResilientGenericChild"])
        #expect(resilientGenericChild.kind == .resilientAncestry)
        #expect(resilientGenericChild.superclass == .swiftClass(displayName: "\(kitModuleName).ResilientGenericBase<Swift.Int>"))
        try expectSelectors(of: resilientGenericChild, in: machO, instance: ["resilientGenericPoke"])

        // Generic ancestry: the stub only its symbol names, and the
        // superclass another class without a class object.
        let concreteSubclass = try #require(classes["\(moduleName).ConcreteSubclass"])
        #expect(concreteSubclass.kind == .genericAncestry)
        #expect(concreteSubclass.name == concreteSubclassRuntimeName)
        #expect(concreteSubclass.superclass == .withoutClassObject(name: "\(moduleName).GenericWidget<A>"))
        #expect(concreteSubclass.hasObjectiveCAncestry)
        if keepsLocalSymbols {
            // A non-public stub has no `…CMs` alias: the isa word is one
            // reserved word into the full stub `…CMt`.
            let concreteSubclassStubOffset = try #require(concreteSubclass.classStubOffset)
            let fullStubOffset = try #require(offset(ofSymbolEndingIn: "16ConcreteSubclassCMt", in: machO))
            #expect(concreteSubclassStubOffset == fullStubOffset + 8)
            #expect(offset(ofSymbolEndingIn: "16ConcreteSubclassCMs", in: machO) == nil)
        } else {
            #expect(concreteSubclass.classStubOffset == nil)
        }
        try expectSelectors(of: concreteSubclass, in: machO, instance: ["description", "concretePoke"])

        // Generic ancestry on the native object model: no stub at all.
        let nativeConcreteSubclass = try #require(classes["\(moduleName).NativeConcreteSubclass"])
        #expect(nativeConcreteSubclass.kind == .genericAncestry)
        #expect(nativeConcreteSubclass.superclass == .withoutClassObject(name: "\(moduleName).GenericNativeRoot<A>"))
        #expect(!nativeConcreteSubclass.hasObjectiveCAncestry)
        #expect(nativeConcreteSubclass.classStubOffset == nil)
    }

    @Test func classesWithoutClassObjectsAreReadFromTheFile() throws {
        try Self.expectClasses(in: try ClassesWithoutClassObjectsFixture.machOFile(.full), keepsLocalSymbols: true)
    }

    @Test func classesWithoutClassObjectsAreReadFromAStrippedFile() throws {
        try Self.expectClasses(in: try ClassesWithoutClassObjectsFixture.machOFile(.strippedLocals), keepsLocalSymbols: false)
    }

    @Test func classesWithoutClassObjectsAreReadInProcess() throws {
        try Self.expectClasses(in: try ClassesWithoutClassObjectsFixture.loadedImage(), keepsLocalSymbols: true)
    }

    /// The method index answers for these classes under the names this index
    /// gives them, and walks their chains: through another class without a
    /// class object, and on to `NSObject` in the system's dyld shared cache.
    @Test func hierarchiesWalkThroughClassesWithoutClassObjects() throws {
        let machOFile = try ClassesWithoutClassObjectsFixture.machOFile(.full)
        let methodIndex = ObjCClassMethodIndex.shared
        #expect(methodIndex.runtimeNames(forSwiftClassQualifiedName: "\(Self.moduleName).GenericWidget", in: machOFile) == ["\(Self.moduleName).GenericWidget<A>"])
        #expect(methodIndex.runtimeNames(forSwiftClassQualifiedName: "\(Self.moduleName).ConcreteSubclass", in: machOFile) == [Self.concreteSubclassRuntimeName])

        let genericWidget = try #require(methodIndex.hierarchy(forRuntimeName: "\(Self.moduleName).GenericWidget<A>", in: machOFile))
        #expect(genericWidget.isAncestorChainComplete)
        #expect(genericWidget.ancestors.first?.className == "NSObject")
        #expect(genericWidget.ancestorDeclaring(selector: "description", isClassMethod: false)?.className == "NSObject")
        #expect(genericWidget.ancestorDeclaring(selector: "poke", isClassMethod: false) == nil)

        let concreteSubclass = try #require(methodIndex.hierarchy(forRuntimeName: Self.concreteSubclassRuntimeName, in: machOFile))
        #expect(concreteSubclass.isAncestorChainComplete)
        #expect(concreteSubclass.ancestors.map(\.className).prefix(2) == ["\(Self.moduleName).GenericWidget<A>", "NSObject"])
        #expect(concreteSubclass.ancestorDeclaring(selector: "poke", isClassMethod: false)?.className == "\(Self.moduleName).GenericWidget<A>")
        #expect(concreteSubclass.ancestorDeclaring(selector: "concretePoke", isClassMethod: false) == nil)

        // A Swift superclass another image defines: the chain stops at once,
        // unnamed — no lookup could answer for its Swift spelling.
        let resilientChild = try #require(methodIndex.hierarchy(forRuntimeName: Self.resilientChildRuntimeName, in: machOFile))
        #expect(!resilientChild.isAncestorChainComplete)
        #expect(resilientChild.unresolvedAncestorName == nil)
        #expect(resilientChild.ancestors.isEmpty)
    }

    /// In-process every class object's superclass is a pointer, but a class
    /// without a class object only has its superclass's name: the resolver
    /// looks it up in the loaded images, and the chain reaches `NSObject`
    /// as it does from the file.
    @Test func hierarchiesWalkThroughClassesWithoutClassObjectsInProcess() throws {
        let machOImage = try ClassesWithoutClassObjectsFixture.loadedImage()
        let methodIndex = ObjCClassMethodIndex.shared
        let genericWidget = try #require(methodIndex.hierarchy(forRuntimeName: "\(Self.moduleName).GenericWidget<A>", in: machOImage))
        #expect(genericWidget.isAncestorChainComplete)
        #expect(genericWidget.ancestorDeclaring(selector: "description", isClassMethod: false)?.className == "NSObject")

        let concreteSubclass = try #require(methodIndex.hierarchy(forRuntimeName: Self.concreteSubclassRuntimeName, in: machOImage))
        #expect(concreteSubclass.isAncestorChainComplete)
        #expect(concreteSubclass.ancestors.map(\.className).prefix(2) == ["\(Self.moduleName).GenericWidget<A>", "NSObject"])
    }
}
