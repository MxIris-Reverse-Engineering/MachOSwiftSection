import Foundation
@_spi(Internals) import Demangling
import SwiftDeclaration
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection
import SwiftObjCInterop

/// The Swift members that answer an Objective-C class's or category's members
/// (evolution proposals `objc-imported-declarations` and
/// `swift-first-imported-declarations`), from the Swift definitions that
/// implement it, by the member's position in its list.
///
/// A member is paired in three steps, each only for what the one before left:
///
/// 1. the tie the index joined by symbol — the `To` thunk at the IMP, or the
///    implementation the thunk's code references (`objcMember`);
/// 2. the index's name-only tie of an override (`evidence == .selectorName`);
/// 3. a name-only tie made here for any other member. An OS framework strips
///    the thunks and `-O` inlines most bodies into them, so steps 1 and 2 tie
///    few members of an `@objc @implementation` class: `-[SHScenePresentation
///    isHostingSceneLayer:]` no longer calls `isHosting(sceneLayer:)`. The
///    definitions here implement the class, so a Swift member whose name the
///    importer gives the selector answers to it — when it is the only such
///    member, no other Objective-C member could take it as well, and its type
///    can be the Objective-C member's (`ObjCSwiftTypeCompatibility`). A name
///    carrying the importer's `NS_REFINED_FOR_SWIFT` prefix (`__layerFilter`)
///    counts, and wins over the plain one (`layerFilter`), which a header
///    refining the member leaves to a Swift declaration of its own.
///
/// With `recognizesRefinements`, it also says which Objective-C members the
/// header marks `NS_REFINED_FOR_SWIFT`, as far as the Swift side shows.
struct ObjCImplementingSwiftMembers {
    enum Member {
        case function(FunctionDefinition)
        case variable(VariableDefinition)
        case `subscript`(SubscriptDefinition)
    }

    /// Why an Objective-C member counts as one the header marks
    /// `NS_REFINED_FOR_SWIFT`.
    enum Refinement: Equatable {
        /// The Swift member answering it is named with the importer's `__`
        /// prefix: the implementation of a refined member.
        case answeredUnderPrefixedName
        /// A property no Swift member answers to, whose plain name a Swift
        /// property of a type it cannot have has taken. Swift does not let two
        /// properties of a type share a name, so the Objective-C one is known
        /// to Swift by another — the prefixed one, when the header refines it.
        case nameTakenByAnotherDeclaration
    }

    private struct Key: Hashable {
        let selector: String
        let isClassMethod: Bool
    }

    /// A Swift member the name-only step may pair: one the index tied to no
    /// Objective-C method.
    private struct Candidate {
        let member: Member
        /// What its symbols demangle to: a function's own, a property's
        /// getter and setter.
        let shapes: [ObjCMemberShape]
        /// A function's function type, a property's declared type.
        let typeNode: Node?
        /// The module its symbols place it in.
        let moduleName: String?
    }

    private enum NameMatch {
        case plain
        case prefixed
    }

    private var membersByObjCMemberIndex: [Int: Member] = [:]
    private var refinementsByObjCMemberIndex: [Int: Refinement] = [:]
    private var nameTakingMembersByObjCMemberIndex: [Int: Member] = [:]

    /// `typeDefinitions` and `extensionDefinitions` must be indexed.
    init(objcMembers: [ObjCImportedMemberDefinition], typeDefinitions: [TypeDefinition], extensionDefinitions: [ExtensionDefinition], recognizesRefinements: Bool) {
        var joinedMembersByKey: [Key: Member] = [:]
        var nameOnlyMembersByKey: [Key: Member] = [:]
        var candidates: [Candidate] = []

        /// Files a member the index tied; `false` when it tied it to nothing.
        func record(_ objcMember: ObjCMember?, as member: Member) -> Bool {
            guard let objcMember else { return false }
            let key = Key(selector: objcMember.selector, isClassMethod: objcMember.isClassMethod)
            if objcMember.evidence == .selectorName {
                if nameOnlyMembersByKey[key] == nil {
                    nameOnlyMembersByKey[key] = member
                }
            } else if joinedMembersByKey[key] == nil {
                joinedMembersByKey[key] = member
            }
            return true
        }
        func add(functions: [FunctionDefinition], constructors: [FunctionDefinition], variables: [VariableDefinition], subscripts: [SubscriptDefinition]) {
            for function in functions where !record(function.objcMember, as: .function(function)) {
                let node = function.node.materialize()
                guard let shape = ObjCMemberShape(demangledSymbol: node) else { continue }
                candidates.append(Candidate(member: .function(function), shapes: [shape], typeNode: ObjCSwiftTypeCompatibility.functionType(ofDemangledMember: node), moduleName: Self.moduleName(ofDemangledMember: node)))
            }
            // An initializer's other entry point: the allocator above is the
            // one the interface prints, so this one is never a candidate.
            for constructor in constructors {
                _ = record(constructor.objcMember, as: .function(constructor))
            }
            for variable in variables where !record(variable.objcMember, as: .variable(variable)) {
                let nodes = variable.accessors.map { $0.symbol.demangledNode.materialize() }
                let shapes = nodes.compactMap { ObjCMemberShape(demangledSymbol: $0) }
                guard !shapes.isEmpty, let node = nodes.first else { continue }
                candidates.append(Candidate(member: .variable(variable), shapes: shapes, typeNode: ObjCSwiftTypeCompatibility.propertyType(ofDemangledMember: node), moduleName: Self.moduleName(ofDemangledMember: node)))
            }
            for `subscript` in subscripts {
                _ = record(`subscript`.objcMember, as: .subscript(`subscript`))
            }
        }
        for typeDefinition in typeDefinitions {
            add(
                functions: typeDefinition.functions + typeDefinition.staticFunctions + typeDefinition.allocators,
                constructors: typeDefinition.constructors,
                variables: typeDefinition.variables + typeDefinition.staticVariables,
                subscripts: typeDefinition.subscripts + typeDefinition.staticSubscripts
            )
        }
        for extensionDefinition in extensionDefinitions {
            add(
                functions: extensionDefinition.functions + extensionDefinition.staticFunctions + extensionDefinition.allocators,
                constructors: extensionDefinition.constructors,
                variables: extensionDefinition.variables + extensionDefinition.staticVariables,
                subscripts: extensionDefinition.subscripts + extensionDefinition.staticSubscripts
            )
        }

        // Steps 1 and 2: what the index tied.
        var unpairedIndices: [Int] = []
        for (index, objcMember) in objcMembers.enumerated() {
            let keys = Self.keys(of: objcMember)
            if let member = keys.lazy.compactMap({ joinedMembersByKey[$0] }).first ?? keys.lazy.compactMap({ nameOnlyMembersByKey[$0] }).first {
                membersByObjCMemberIndex[index] = member
            } else {
                unpairedIndices.append(index)
            }
        }

        // Step 3: by name, a pairing both sides agree on.
        var bestCandidateIndicesByObjCMemberIndex: [Int: [Int]] = [:]
        var objcMemberIndicesByCandidateIndex: [Int: [Int]] = [:]
        for index in unpairedIndices {
            let objcMember = objcMembers[index]
            var plainCandidateIndices: [Int] = []
            var prefixedCandidateIndices: [Int] = []
            for (candidateIndex, candidate) in candidates.enumerated() {
                guard let match = Self.nameMatch(of: candidate, for: objcMember), !Self.isClearlyIncompatible(candidate, with: objcMember) else { continue }
                switch match {
                case .plain: plainCandidateIndices.append(candidateIndex)
                case .prefixed: prefixedCandidateIndices.append(candidateIndex)
                }
            }
            let bestCandidateIndices = prefixedCandidateIndices.isEmpty ? plainCandidateIndices : prefixedCandidateIndices
            bestCandidateIndicesByObjCMemberIndex[index] = bestCandidateIndices
            for candidateIndex in bestCandidateIndices {
                objcMemberIndicesByCandidateIndex[candidateIndex, default: []].append(index)
            }
        }
        for (index, bestCandidateIndices) in bestCandidateIndicesByObjCMemberIndex {
            guard bestCandidateIndices.count == 1, let candidateIndex = bestCandidateIndices.first, objcMemberIndicesByCandidateIndex[candidateIndex] == [index] else { continue }
            membersByObjCMemberIndex[index] = candidates[candidateIndex].member
        }

        guard recognizesRefinements else { return }
        for (index, objcMember) in objcMembers.enumerated() {
            if let member = membersByObjCMemberIndex[index] {
                if Self.isNamedWithRefinedForSwiftPrefix(member, answering: objcMember) {
                    refinementsByObjCMemberIndex[index] = .answeredUnderPrefixedName
                }
            } else if objcMember.kind == .property, let nameTakingCandidate = candidates.first(where: { Self.takesName(of: objcMember, candidate: $0) }) {
                refinementsByObjCMemberIndex[index] = .nameTakenByAnotherDeclaration
                nameTakingMembersByObjCMemberIndex[index] = nameTakingCandidate.member
            }
        }
    }

    /// The Swift member answering to the Objective-C member at `index` of the
    /// list the pairing was made for, or `nil`.
    func member(answeringMemberAt index: Int) -> Member? {
        membersByObjCMemberIndex[index]
    }

    /// Why the Objective-C member at `index` counts as `NS_REFINED_FOR_SWIFT`,
    /// or `nil` when nothing says it is.
    func refinement(ofMemberAt index: Int) -> Refinement? {
        refinementsByObjCMemberIndex[index]
    }

    /// The Swift property that took the plain name of the Objective-C
    /// property at `index`, when that is why the property counts as
    /// `NS_REFINED_FOR_SWIFT` (`Refinement.nameTakenByAnotherDeclaration`);
    /// `nil` otherwise. The Generated Interface words the Objective-C property
    /// right above it (evolution proposal
    /// `swift-first-imported-declarations`).
    func member(takingNameOfMemberAt index: Int) -> Member? {
        nameTakingMembersByObjCMemberIndex[index]
    }

    // MARK: - Matching

    /// A factory method is a class method in Objective-C.
    private static func isClassMethod(_ objcMember: ObjCImportedMemberDefinition) -> Bool {
        objcMember.isClassMember || objcMember.kind == .factoryInitializer
    }

    /// A property's getter, then its setter; a method's selector.
    private static func keys(of objcMember: ObjCImportedMemberDefinition) -> [Key] {
        [objcMember.selector, objcMember.setterSelector].compactMap { $0 }.map { Key(selector: $0, isClassMethod: isClassMethod(objcMember)) }
    }

    /// Whether a shape of `candidate` is the importer's name for a selector of
    /// `objcMember`, with or without the `NS_REFINED_FOR_SWIFT` prefix. A
    /// property pairs with a property, a method with a method, an initializer
    /// with an initializer; a subscript's selectors are fixed and a factory
    /// method's Swift initializer has no shape a class method fits, so neither
    /// is paired by name.
    private static func nameMatch(of candidate: Candidate, for objcMember: ObjCImportedMemberDefinition) -> NameMatch? {
        let isClassMethod = isClassMethod(objcMember)
        let selectors = [objcMember.selector, objcMember.setterSelector].compactMap { $0 }
        var match: NameMatch?
        for shape in candidate.shapes where fits(shape, objcMember.kind) {
            for selector in selectors {
                if shape.isConsistent(withSelector: selector, isClassMethod: isClassMethod) {
                    match = match ?? .plain
                } else if let unprefixedShape = shape.removingRefinedForSwiftPrefix, unprefixedShape.isConsistent(withSelector: selector, isClassMethod: isClassMethod) {
                    match = .prefixed
                }
            }
        }
        return match
    }

    private static func fits(_ shape: ObjCMemberShape, _ kind: ObjCImportedMemberDefinition.Kind) -> Bool {
        switch (shape.kind, kind) {
        case (.getter, .property), (.setter, .property), (.method, .method), (.initializer, .initializer):
            true
        default:
            false
        }
    }

    private static func isClearlyIncompatible(_ candidate: Candidate, with objcMember: ObjCImportedMemberDefinition) -> Bool {
        guard let typeNode = candidate.typeNode else { return false }
        switch objcMember.kind {
        case .property:
            guard let objcType = ObjCTypeEncodingParser.propertyType(fromAttributes: objcMember.typeEncoding) else { return false }
            return ObjCSwiftTypeCompatibility.isClearlyIncompatible(objcType: objcType, swiftType: typeNode, implementingModuleName: candidate.moduleName)
        case .method, .initializer, .factoryInitializer:
            guard let methodType = ObjCTypeEncodingParser.methodType(from: objcMember.typeEncoding, matchingArgumentsOf: objcMember.selector) else { return false }
            return ObjCSwiftTypeCompatibility.isClearlyIncompatible(objcMethodType: methodType, swiftFunctionType: typeNode, comparesResult: objcMember.kind == .method, implementingModuleName: candidate.moduleName)
        case .subscript:
            return false
        }
    }

    /// Whether a Swift property of a type the Objective-C property cannot have
    /// is named like it.
    private static func takesName(of objcMember: ObjCImportedMemberDefinition, candidate: Candidate) -> Bool {
        guard case .variable = candidate.member else { return false }
        let isNamedLikeIt = candidate.shapes.contains { shape in
            if case .getter = shape.kind {
                return shape.isConsistent(withSelector: objcMember.selector, isClassMethod: objcMember.isClassMember)
            }
            return false
        }
        return isNamedLikeIt && isClearlyIncompatible(candidate, with: objcMember)
    }

    /// Whether `member`'s Swift name carries the `NS_REFINED_FOR_SWIFT` prefix
    /// the selector it answers does not.
    private static func isNamedWithRefinedForSwiftPrefix(_ member: Member, answering objcMember: ObjCImportedMemberDefinition) -> Bool {
        guard !objcMember.selector.hasPrefix(ObjCMemberShape.refinedForSwiftPrefix) else { return false }
        let nodes: [Node]
        switch member {
        case .function(let function):
            nodes = [function.node.materialize()]
        case .variable(let variable):
            nodes = variable.accessors.map { $0.symbol.demangledNode.materialize() }
        case .subscript:
            return false
        }
        return nodes.contains { node in
            ObjCMemberShape(demangledSymbol: node)?.removingRefinedForSwiftPrefix != nil
        }
    }

    /// The module of a member symbol's context: an extension's module, or the
    /// module of the type declaring it.
    private static func moduleName(ofDemangledMember root: Node) -> String? {
        if let extensionNode = root.first(of: .extension), let module = extensionNode.children.first(where: { $0.kind == .module }) {
            return module.text
        }
        return root.first(of: .module)?.text
    }
}
