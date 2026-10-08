import Foundation
@_spi(Internals) import Demangling
import MachOKit
import MachOSwiftSection
import SwiftDeclaration
import SwiftDeclarationRendering
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

/// The arguments of every parameter of one instantiation of a generic type,
/// grouped by depth, and the instantiation's name (evolution proposal
/// `offline-generic-specialization`).
///
/// A specialization request offers only the parameters that take a key
/// argument. A parameter a same-type requirement fixes takes none — `A` in
/// `extension Outer where A == Int { struct Inner<B> }` — but the
/// instantiation still binds it, and its name spells it:
/// `Outer<Swift.Int>.Inner<Swift.String>`. The runtime recovers such an
/// argument from the requirement (`_gatherWrittenGenericParameters`); this
/// does the same with nodes: the requirement's right-hand side, with the
/// arguments known so far substituted and any member of a concrete type
/// projected through its conformance.
///
/// Shared by both specializations: the offline one binds its result with it,
/// and the runtime one names its definition with it, so the two give the
/// same instantiation the same name.
package struct GenericInstantiation {
    package let binding: GenericArgumentBinding

    /// The instantiation's name, `.type`-wrapped.
    package let typeNode: Node

    /// - Parameter keyArguments: One `.type`-wrapped node per parameter that
    ///   takes a key argument, in the order of the generic context's
    ///   cumulative parameter list — `SpecializationRequest.parameters`'s
    ///   order.
    package init<MachO: MachOSwiftSectionRepresentableWithCache>(
        of descriptor: TypeContextDescriptorWrapper,
        keyArguments: [Node],
        in machO: MachO
    ) throws {
        guard let genericContext = try descriptor.genericContext(in: machO.context) else {
            throw GenericInstantiationError.notGeneric
        }
        let parameters = genericContext.parameters
        let depthLayout = GenericParameterDepthLayout.make(for: genericContext, ownedBy: .type(descriptor), in: machO.context)
        guard depthLayout.parameterCount == parameters.count else {
            throw GenericInstantiationError.depthLayoutMismatch(parameterCount: parameters.count, layoutParameterCount: depthLayout.parameterCount)
        }

        var argumentsByFlatIndex: [Node?] = Array(repeating: nil, count: parameters.count)
        var remainingKeyArguments = keyArguments[...]
        for (flatIndex, parameter) in parameters.enumerated() where parameter.hasKeyArgument {
            guard let argument = remainingKeyArguments.popFirst() else {
                throw GenericInstantiationError.keyArgumentCountMismatch(expected: parameters.filter(\.hasKeyArgument).count, actual: keyArguments.count)
            }
            argumentsByFlatIndex[flatIndex] = Self.typeWrapped(argument)
        }
        guard remainingKeyArguments.isEmpty else {
            throw GenericInstantiationError.keyArgumentCountMismatch(expected: parameters.filter(\.hasKeyArgument).count, actual: keyArguments.count)
        }

        try Self.fillFixedParameters(
            &argumentsByFlatIndex,
            depthLayout: depthLayout,
            requirements: genericContext.requirements,
            in: machO
        )

        let arguments = argumentsByFlatIndex.compactMap { $0 }
        guard let argumentsByDepth = depthLayout.grouped(arguments) else {
            throw GenericInstantiationError.depthLayoutMismatch(parameterCount: arguments.count, layoutParameterCount: depthLayout.parameterCount)
        }
        self.binding = GenericArgumentBinding(argumentsByDepth: argumentsByDepth)
        self.typeNode = try SymbolicDemangler.instantiatedTypeNode(for: descriptor, binding: binding, in: machO.context)
    }

    /// Fills every parameter without a key argument from the same-type
    /// requirement that fixes it. A right-hand side can name another fixed
    /// parameter (`C == B`, `B == Int`), so the requirements are applied until
    /// no further one resolves.
    ///
    /// A requirement between two parameters (`First == Second`) is read both
    /// ways, as the runtime's `_gatherWrittenGenericParameters` reads it: the
    /// compiler writes the parameter that keeps its key argument on the LEFT,
    /// so it is the right-hand parameter that takes the left one's argument.
    private static func fillFixedParameters<MachO: MachOSwiftSectionRepresentableWithCache>(
        _ argumentsByFlatIndex: inout [Node?],
        depthLayout: GenericParameterDepthLayout,
        requirements: [GenericRequirementDescriptor],
        in machO: MachO
    ) throws {
        var unresolvedFlatIndices = argumentsByFlatIndex.indices.filter { argumentsByFlatIndex[$0] == nil }
        guard !unresolvedFlatIndices.isEmpty else { return }

        // The same-type requirements whose subject is a parameter itself, by
        // that parameter's position in the cumulative list; and, for those
        // whose right-hand side is a parameter too, the left-hand parameter
        // by the right-hand one's position.
        var fixingRequirementByFlatIndex: [Int: MangledName] = [:]
        var leftHandFlatIndexByRightHandFlatIndex: [Int: Int] = [:]
        for requirement in requirements where requirement.layout.flags.kind == .sameType {
            guard let subjectNode = try? SymbolicDemangler.demangleType(for: requirement.paramMangledName(in: machO.context), in: machO.context),
                  let position = genericParameterPosition(of: subjectNode),
                  let flatIndex = depthLayout.flatIndex(depth: position.depth, index: position.index),
                  let rightHandSide = try? requirement.type(in: machO.context)
            else { continue }
            if fixingRequirementByFlatIndex[flatIndex] == nil {
                fixingRequirementByFlatIndex[flatIndex] = rightHandSide
            }
            if let rightHandSideNode = try? SymbolicDemangler.demangleType(for: rightHandSide, in: machO.context),
               let rightHandPosition = genericParameterPosition(of: rightHandSideNode),
               let rightHandFlatIndex = depthLayout.flatIndex(depth: rightHandPosition.depth, index: rightHandPosition.index),
               leftHandFlatIndexByRightHandFlatIndex[rightHandFlatIndex] == nil {
                leftHandFlatIndexByRightHandFlatIndex[rightHandFlatIndex] = flatIndex
            }
        }

        var didResolveParameter = true
        while !unresolvedFlatIndices.isEmpty, didResolveParameter {
            didResolveParameter = false
            let partialBinding = Self.partialBinding(argumentsByFlatIndex, depthLayout: depthLayout)
            for flatIndex in unresolvedFlatIndices {
                if let rightHandSide = fixingRequirementByFlatIndex[flatIndex],
                   let rightHandSideNode = try? SymbolicDemangler.demangleType(for: rightHandSide, in: machO.context) {
                    let argument = DependentMemberProjection.projectingConcreteMembers(in: partialBinding.substituting(in: rightHandSideNode), in: machO)
                    if !containsGenericParameter(argument) {
                        argumentsByFlatIndex[flatIndex] = typeWrapped(argument)
                        didResolveParameter = true
                        continue
                    }
                }
                if let leftHandFlatIndex = leftHandFlatIndexByRightHandFlatIndex[flatIndex],
                   let leftHandArgument = argumentsByFlatIndex[leftHandFlatIndex] {
                    argumentsByFlatIndex[flatIndex] = leftHandArgument
                    didResolveParameter = true
                }
            }
            unresolvedFlatIndices.removeAll { argumentsByFlatIndex[$0] != nil }
        }

        if let unresolvedFlatIndex = unresolvedFlatIndices.first {
            let position = depthLayout.position(ofParameterAt: unresolvedFlatIndex)
            throw GenericInstantiationError.unresolvedFixedParameter(
                name: position.map { genericParameterName(depth: UInt64($0.depth), index: UInt64($0.index)) } ?? "#\(unresolvedFlatIndex)"
            )
        }
    }

    /// The arguments known so far, every unknown one standing for itself, so
    /// a substitution leaves the parameters still to be resolved in place.
    private static func partialBinding(_ argumentsByFlatIndex: [Node?], depthLayout: GenericParameterDepthLayout) -> GenericArgumentBinding {
        let arguments = argumentsByFlatIndex.enumerated().map { flatIndex, argument in
            argument ?? depthLayout.position(ofParameterAt: flatIndex).map { position in
                Node.createTransient(kind: .type, child: Node.createTransient(kind: .dependentGenericParamType, children: [
                    .createTransient(kind: .index, index: UInt64(position.depth)),
                    .createTransient(kind: .index, index: UInt64(position.index)),
                ]))
            } ?? Node.createTransient(kind: .type, child: .createTransient(kind: .errorType))
        }
        return GenericArgumentBinding(argumentsByDepth: depthLayout.grouped(arguments) ?? [])
    }

    private static func genericParameterPosition(of subjectNode: Node) -> (depth: Int, index: Int)? {
        let parameterNode = subjectNode.kind == .type ? subjectNode.firstChild : subjectNode
        guard let parameterNode, parameterNode.kind == .dependentGenericParamType,
              parameterNode.children.count == 2,
              let depth = parameterNode.children[0].index,
              let index = parameterNode.children[1].index
        else { return nil }
        return (Int(depth), Int(index))
    }

    private static func containsGenericParameter(_ node: Node) -> Bool {
        node.kind == .dependentGenericParamType || node.children.contains(where: containsGenericParameter)
    }

    private static func typeWrapped(_ node: Node) -> Node {
        node.kind == .type ? node : Node.createTransient(kind: .type, child: node)
    }
}

/// Why an instantiation's arguments or name could not be built.
package enum GenericInstantiationError: LocalizedError {
    case notGeneric
    case keyArgumentCountMismatch(expected: Int, actual: Int)
    case depthLayoutMismatch(parameterCount: Int, layoutParameterCount: Int)
    case unresolvedFixedParameter(name: String)

    package var errorDescription: String? {
        switch self {
        case .notGeneric:
            return "the type is not generic"
        case .keyArgumentCountMismatch(let expected, let actual):
            return "the type takes \(expected) key argument(s), \(actual) supplied"
        case .depthLayoutMismatch(let parameterCount, let layoutParameterCount):
            return "the generic context declares \(parameterCount) parameter(s) but its depths cover \(layoutParameterCount)"
        case .unresolvedFixedParameter(let name):
            return "the argument of \(name), which a same-type requirement fixes, could not be determined from that requirement"
        }
    }
}
