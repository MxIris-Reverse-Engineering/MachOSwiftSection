import Foundation
import MachOKit
@_spi(Internals) import MachOCodeReferences

extension CrossReferenceAnalyzer {
    /// The images among `candidates` whose symbol table imports
    /// `symbolName` — for a C function or an Objective-C class, the ones that
    /// reach it by that name: a shared cache image keeps those undefined
    /// symbols even where the cache builder bound the calls directly.
    ///
    /// Not every image that can reach it. Another image may re-export it
    /// under a name of its own, which its callers import instead
    /// (`reexportedNames(ofSymbolsNamed:inImageAt:)`). And not for a Swift
    /// symbol: only 245 of the macOS 27.2 cache's 4,113 images keep any among
    /// their undefined symbols, so this finds a few of the images that use
    /// one. `imageIndices(callingFunctionAt:symbolNames:among:)` covers both.
    public func imageIndices(importing symbolName: String, among candidates: some Sequence<Int>) -> [Int] {
        imageSet.imageIndices(importingAnyOf: [symbolName], among: candidates)
    }

    /// The images among `candidates` whose symbol table imports any of
    /// `symbolNames`.
    public func imageIndices(importingAnyOf symbolNames: [String], among candidates: some Sequence<Int>) -> [Int] {
        imageSet.imageIndices(importingAnyOf: symbolNames, among: candidates)
    }

    /// The images among `candidates` that can send `selector`: the ones whose
    /// `__objc_selrefs` reference it, and — for a selector a libobjc entry
    /// point sends, `init` for `objc_alloc_init` — the ones importing or
    /// defining such an entry point. An image may send `init` through
    /// `objc_alloc_init` alone, keeping no `init` selector reference.
    public func imageIndices(referencingSelector selector: String, among candidates: some Sequence<Int>) -> [Int] {
        objectiveC.imageIndices(referencingSelector: selector, among: candidates)
    }

    /// Where the image at `imageIndex` defines a class named `name`: one
    /// location, or none. The first query on an image reads the names of all
    /// its classes.
    public func objectiveCClassLocations(named name: String, inImageAt imageIndex: Int) -> [CodeLocation] {
        objectiveC.classLocations(named: name, inImageAt: imageIndex)
    }

    /// The images among `candidates` that can reference the Objective-C class
    /// at `classLocation`: the image defining it, and the images importing a
    /// symbol that names the class or its metaclass.
    ///
    /// Most images reach another image's class as `_OBJC_CLASS_$_<name>`, but
    /// not all: a block literal's `isa` is `__NSConcreteStackBlock`, an XPC
    /// type is `__xpc_type_dictionary`. So every symbol the defining image
    /// has at either address counts. A Swift class is reached through Swift
    /// symbols as well, which the cache drops from its images' undefined
    /// symbols, so every image that can bind to its image counts too.
    public func imageIndices(referencingObjectiveCClassAt classLocation: CodeLocation, among candidates: some Sequence<Int>) -> [Int] {
        objectiveC.imageIndices(referencingClassAt: classLocation, among: candidates, includingSwiftLinkage: true)
    }

    /// `includingSwiftLinkage` false leaves out the images linking a Swift
    /// class's image, for a class known to export no Swift symbol — see
    /// `imageIndices(referencingSwiftType:among:)`.
    func imageIndices(referencingObjectiveCClassAt classLocation: CodeLocation, among candidates: some Sequence<Int>, includingSwiftLinkage: Bool) -> [Int] {
        objectiveC.imageIndices(referencingClassAt: classLocation, among: candidates, includingSwiftLinkage: includingSwiftLinkage)
    }
}
