import Foundation
import MachOKit
import MachOBase

/// The variable-length tail of a function type metadata record.
///
/// Everything a function type knows beyond "how many parameters and what it
/// returns" lives after the three-word header, in blocks whose presence the
/// flag word decides. The blocks appear in a fixed order and each starts on
/// its own alignment — a `UInt32` block followed by a pointer-sized one
/// leaves four bytes of padding — which is why the offsets are computed
/// cumulatively rather than as a sum of sizes.
///
/// Order (`swift::TargetFunctionTypeMetadata`'s trailing objects):
///
/// ```
/// parameter type      × numberOfParameters      always
/// FunctionParameterTypeFlags  × numberOfParameters      hasParameterFlags
/// differentiability kind                        isDifferentiable
/// global actor type                             hasGlobalActor
/// FunctionTypeExtendedFlags                     hasExtendedFlags
/// thrown error type                             extended flags say typed throws
/// ```
///
/// Function type metadata is allocated by the runtime and appears in no
/// Mach-O section, so these reads are only meaningful against live in-process
/// metadata.
extension FunctionTypeMetadata {
    public var flags: FunctionTypeFlags<StoredSize> { layout.flags }

    public var numberOfParameters: Int { layout.flags.numberOfParameters.cast() }

    private static func aligned(_ value: Int, to alignment: Int) -> Int {
        (value + alignment - 1) & ~(alignment - 1)
    }

    private static var pointerSize: Int { MemoryLayout<ConstMetadataPointer<Metadata>>.size }

    /// Location of the first parameter type, in the same coordinate space as
    /// ``offset``.
    public var parametersOffset: Int {
        offset + layoutSize
    }

    /// Location of the ``FunctionParameterTypeFlags`` array, or `nil` when the record
    /// carries none — which is the common case, since the compiler omits the
    /// whole array when every parameter is an ordinary by-value one.
    public var parameterFlagsOffset: Int? {
        guard layout.flags.hasParameterFlags else { return nil }
        return Self.aligned(parametersOffset + numberOfParameters * Self.pointerSize, to: MemoryLayout<FunctionParameterTypeFlags>.alignment)
    }

    /// Location of the differentiability kind word, or `nil` when the
    /// function is not differentiable.
    public var differentiabilityKindOffset: Int? {
        guard layout.flags.isDifferentiable else { return nil }
        return Self.aligned(endOfParameterFlags, to: MemoryLayout<FunctionTypeDifferentiabilityKind.RawValue>.alignment)
    }

    /// Location of the global actor type, or `nil` when the function is not
    /// globally isolated.
    public var globalActorOffset: Int? {
        guard layout.flags.hasGlobalActor else { return nil }
        return Self.aligned(endOfDifferentiabilityKind, to: Self.pointerSize)
    }

    /// Location of the ``FunctionTypeExtendedFlags`` word, or `nil` when the
    /// record carries none.
    public var extendedFlagsOffset: Int? {
        guard layout.flags.hasExtendedFlags else { return nil }
        return Self.aligned(endOfGlobalActor, to: MemoryLayout<FunctionTypeExtendedFlags>.alignment)
    }

    private var endOfParameters: Int {
        parametersOffset + numberOfParameters * Self.pointerSize
    }

    private var endOfParameterFlags: Int {
        guard let parameterFlagsOffset else { return endOfParameters }
        return parameterFlagsOffset + numberOfParameters * MemoryLayout<FunctionParameterTypeFlags>.size
    }

    private var endOfDifferentiabilityKind: Int {
        guard let differentiabilityKindOffset else { return endOfParameterFlags }
        return differentiabilityKindOffset + MemoryLayout<FunctionTypeDifferentiabilityKind.RawValue>.size
    }

    private var endOfGlobalActor: Int {
        guard let globalActorOffset else { return endOfDifferentiabilityKind }
        return globalActorOffset + Self.pointerSize
    }

    private var endOfExtendedFlags: Int {
        guard let extendedFlagsOffset else { return endOfGlobalActor }
        return extendedFlagsOffset + MemoryLayout<FunctionTypeExtendedFlags>.size
    }
}

// MARK: - ReadingContext Support

extension FunctionTypeMetadata {
    /// The parameter types, in declaration order.
    public func parameters<Context: ReadingContext>(in context: Context) throws -> [ConstMetadataPointer<Metadata>] {
        guard numberOfParameters > 0 else { return [] }
        return try context.readElements(at: try context.addressFromOffset(parametersOffset), numberOfElements: numberOfParameters)
    }

    /// The per-parameter flags, in declaration order, or an empty array when
    /// the record carries none. An empty result means "every parameter is an
    /// ordinary by-value one", not "unknown".
    public func parameterFlags<Context: ReadingContext>(in context: Context) throws -> [FunctionParameterTypeFlags] {
        guard let parameterFlagsOffset, numberOfParameters > 0 else { return [] }
        return try context.readElements(at: try context.addressFromOffset(parameterFlagsOffset), numberOfElements: numberOfParameters)
    }

    /// The differentiability kind, or `nil` when the function is not
    /// differentiable. A recognized raw value is required; an unknown one
    /// reads as `nil` too, so a caller that must distinguish should check
    /// ``FunctionTypeFlags/isDifferentiable`` itself.
    public func differentiabilityKind<Context: ReadingContext>(in context: Context) throws -> FunctionTypeDifferentiabilityKind? {
        guard let differentiabilityKindOffset else { return nil }
        let rawValue: FunctionTypeDifferentiabilityKind.RawValue = try context.readElement(at: try context.addressFromOffset(differentiabilityKindOffset))
        return FunctionTypeDifferentiabilityKind(rawValue: rawValue)
    }

    /// The global actor the function is isolated to, or `nil` when it is not
    /// globally isolated.
    public func globalActorType<Context: ReadingContext>(in context: Context) throws -> ConstMetadataPointer<Metadata>? {
        guard let globalActorOffset else { return nil }
        // Annotated: asking for the optional directly would instantiate the
        // read at `Optional<Pointer<…>>`, a different in-memory shape.
        let pointer: ConstMetadataPointer<Metadata> = try context.readElement(at: try context.addressFromOffset(globalActorOffset))
        return pointer
    }

    /// The extended flag word, or `nil` when the record carries none.
    public func extendedFlags<Context: ReadingContext>(in context: Context) throws -> FunctionTypeExtendedFlags? {
        guard let extendedFlagsOffset else { return nil }
        return try context.readElement(at: try context.addressFromOffset(extendedFlagsOffset))
    }

    /// Location of the thrown error type, or `nil` when the function does not
    /// declare a concrete error type.
    ///
    /// Unlike the other offsets this one is not pure arithmetic: whether the
    /// block is present is recorded in the extended flags' VALUE, not in the
    /// first flag word, so answering needs a read.
    public func thrownErrorTypeOffset<Context: ReadingContext>(in context: Context) throws -> Int? {
        guard let extendedFlags = try extendedFlags(in: context), extendedFlags.isTypedThrows else { return nil }
        return Self.aligned(endOfExtendedFlags, to: Self.pointerSize)
    }

    /// The concrete error type of a `throws(MyError)` function, or `nil` when
    /// the function throws untyped or does not throw.
    public func thrownErrorType<Context: ReadingContext>(in context: Context) throws -> ConstMetadataPointer<Metadata>? {
        guard let thrownErrorTypeOffset = try thrownErrorTypeOffset(in: context) else { return nil }
        let pointer: ConstMetadataPointer<Metadata> = try context.readElement(at: try context.addressFromOffset(thrownErrorTypeOffset))
        return pointer
    }
}
