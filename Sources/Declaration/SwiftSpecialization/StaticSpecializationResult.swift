import Foundation
import Demangling
import MachOSwiftSection
import SwiftDeclaration
@_spi(Internals) import SwiftInspection

/// The result of specializing a generic type offline — on a `MachOFile`,
/// without the runtime (evolution proposal `offline-generic-specialization`).
///
/// `SpecializationResult` carries the metadata the type's accessor returned;
/// offline there is none, so this carries what the metadata would have been
/// read for: the instantiation's name and the argument of every generic
/// parameter. `TypeDefinition.specialize(with:in:)` turns it into a
/// specialized definition, which the interface printer renders with a bound
/// header, substituted field types, and layout comments the static layout
/// engine computes for these arguments.
public struct StaticSpecializationResult: Sendable {
    /// The generic type that was specialized.
    public let typeDescriptor: TypeContextDescriptorWrapper

    /// The instantiation's name, shaped like the runtime's name for the same
    /// instantiation: `Outer<Swift.Int>.Inner<Swift.String>`.
    public let typeName: TypeName

    /// The argument of every parameter of the type's generic context — the
    /// selected ones, and those a same-type requirement fixes — by depth.
    public let binding: GenericArgumentBinding

    /// The selection the specialization was made with, so the nested types
    /// that only inherit these parameters can be specialized with it too.
    public let selection: SpecializationSelection

    /// One entry per parameter of the request, in request order.
    public let resolvedArguments: [ResolvedArgument]

    public init(
        typeDescriptor: TypeContextDescriptorWrapper,
        typeName: TypeName,
        binding: GenericArgumentBinding,
        selection: SpecializationSelection,
        resolvedArguments: [ResolvedArgument]
    ) {
        self.typeDescriptor = typeDescriptor
        self.typeName = typeName
        self.binding = binding
        self.selection = selection
        self.resolvedArguments = resolvedArguments
    }

    /// The resolved argument for a parameter.
    public func argument(for parameterName: String) -> ResolvedArgument? {
        resolvedArguments.first { $0.parameterName == parameterName }
    }
}

// MARK: - ResolvedArgument

extension StaticSpecializationResult {
    /// The type a parameter was bound to.
    public struct ResolvedArgument: Sendable {
        /// The parameter's name (`A`, `B`, `A1`, …).
        public let parameterName: String

        /// The argument as a `.type`-wrapped type node.
        public let argumentNode: Node

        /// The inner specialization when the argument was
        /// `Argument.boundGeneric`, so a caller can walk the binding tree.
        public let innerResult: StaticSpecializationResult?

        public init(parameterName: String, argumentNode: Node, innerResult: StaticSpecializationResult? = nil) {
            self.parameterName = parameterName
            self.argumentNode = argumentNode
            self.innerResult = innerResult
        }
    }
}
