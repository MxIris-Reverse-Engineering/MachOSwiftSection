import Foundation

/// Result of validating a specialization selection
public struct SpecializationValidation: Sendable {
    /// Whether the selection is valid
    public let isValid: Bool

    /// Validation errors if any
    public let errors: [Error]

    /// Warnings that don't prevent specialization but may indicate issues
    public let warnings: [Warning]

    public init(isValid: Bool, errors: [Error] = [], warnings: [Warning] = []) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }

    /// A valid result with no errors or warnings
    public static let valid = SpecializationValidation(isValid: true, errors: [], warnings: [])

    /// Create a failed validation with errors
    public static func failed(_ errors: [Error]) -> SpecializationValidation {
        SpecializationValidation(isValid: false, errors: errors, warnings: [])
    }

    /// Create a failed validation with a single error
    public static func failed(_ error: Error) -> SpecializationValidation {
        SpecializationValidation(isValid: false, errors: [error], warnings: [])
    }
}

// MARK: - Error

extension SpecializationValidation {
    /// Validation error
    public enum Error: Swift.Error, Sendable, CustomStringConvertible {
        /// A required parameter is missing from the selection
        case missingArgument(parameterName: String)

        /// Selected type does not satisfy a protocol requirement
        case protocolRequirementNotSatisfied(
            parameterName: String,
            protocolName: String,
            actualType: String
        )

        /// Selected type does not satisfy a layout requirement
        case layoutRequirementNotSatisfied(
            parameterName: String,
            expectedLayout: SpecializationRequest.LayoutKind,
            actualType: String
        )

        /// Selected type does not inherit from the required base class.
        /// Either the type is not a class at all (e.g. a struct supplied
        /// for `<T: SomeClass>`), or it is a class whose superclass chain
        /// never reaches the expected base class.
        case baseClassRequirementNotSatisfied(
            parameterName: String,
            expectedBaseClass: String,
            actualType: String
        )

        /// Selected type does not match a same-type requirement
        /// (`A == ConcreteType` or `A == B`). For the GP-vs-GP shape the
        /// `expectedType` field carries the *other* parameter's selected
        /// type so the message reads symmetrically; the `parameterName`
        /// in that case is the LHS of the requirement.
        case sameTypeRequirementNotSatisfied(
            parameterName: String,
            expectedType: String,
            actualType: String
        )

        /// Could not resolve metadata for the parameter — preflight
        /// could not run conformance/layout checks. `specialize` runs
        /// the same metadata resolution path, so the failure is
        /// guaranteed to surface there as well; reporting it here lets
        /// the caller see the diagnostic before the accessor call.
        case metadataResolutionFailed(parameterName: String, reason: String)

        /// Could not construct the protocol descriptor that a
        /// requirement references — preflight could not run the
        /// conformance check. Distinct from `protocolNotInIndexer`
        /// (which is a warning): here the indexer *did* find the entry,
        /// but materializing it as a `MachOSwiftSection.Protocol` failed.
        case protocolDescriptorResolutionFailed(
            parameterName: String,
            protocolName: String,
            reason: String
        )

        public var description: String {
            switch self {
            case .missingArgument(let name):
                return "Missing argument for parameter '\(name)'"

            case .protocolRequirementNotSatisfied(let param, let proto, let actual):
                return "Type '\(actual)' for parameter '\(param)' does not conform to protocol '\(proto)'"

            case .layoutRequirementNotSatisfied(let param, let layout, let actual):
                return "Type '\(actual)' for parameter '\(param)' does not satisfy layout requirement '\(layout)'"

            case .baseClassRequirementNotSatisfied(let param, let baseClass, let actual):
                return "Type '\(actual)' for parameter '\(param)' does not inherit from required base class '\(baseClass)'"

            case .sameTypeRequirementNotSatisfied(let param, let expected, let actual):
                return "Type '\(actual)' for parameter '\(param)' does not equal required same-type '\(expected)'"

            case .metadataResolutionFailed(let param, let reason):
                return "Could not resolve metadata for parameter '\(param)': \(reason)"

            case .protocolDescriptorResolutionFailed(let param, let proto, let reason):
                return "Could not construct protocol descriptor for '\(proto)' (parameter '\(param)'): \(reason)"
            }
        }
    }
}

// MARK: - Warning

extension SpecializationValidation {
    /// Validation warning
    public enum Warning: Sendable, CustomStringConvertible {
        /// Extra argument provided that is not needed
        case extraArgument(parameterName: String)

        /// User supplied a key matching an associated-type path
        /// (e.g. "A.Element"). Associated types are derived during
        /// specialization and cannot be set directly; the entry is ignored.
        case associatedTypePathInSelection(path: String)

        /// A parameter requirement references a protocol that the indexer
        /// doesn't have a definition for, so runtime preflight cannot
        /// validate conformance. Add the protocol's defining image as a
        /// sub-indexer to enable the check.
        case protocolNotInIndexer(parameterName: String, protocolName: String)

        /// `RuntimeFunctions.conformsToProtocol` itself threw — preflight
        /// could not determine whether the parameter conforms. Distinct
        /// from `protocolRequirementNotSatisfied` (an error), which fires
        /// when the call ran successfully and returned `nil`. A throw
        /// here usually indicates a transient runtime issue or a
        /// malformed protocol descriptor pointer.
        case conformanceCheckFailed(
            parameterName: String,
            protocolName: String,
            reason: String
        )

        /// Could not resolve the RHS of a `baseClass` requirement to a
        /// runtime metadata pointer. Preflight cannot enforce the
        /// constraint when the RHS mangled name fails to resolve via
        /// `swift_getTypeByMangledNameInContext`; surfaced as a warning so
        /// the caller knows validation skipped this requirement.
        /// `specialize` will still drive the metadata accessor; if the
        /// mismatch is real, the runtime will reject it there.
        case baseClassRequirementResolutionFailed(
            parameterName: String,
            reason: String
        )

        /// Could not resolve the RHS of a `sameType` requirement to a
        /// runtime metadata pointer (or, for the GP-vs-GP shape, the
        /// other parameter's selection). Preflight skips the check;
        /// `specialize` continues unchanged.
        case sameTypeRequirementResolutionSkipped(
            parameterName: String,
            reason: String
        )

        public var description: String {
            switch self {
            case .extraArgument(let param):
                return "Extra argument '\(param)' is not needed for this specialization"
            case .associatedTypePathInSelection(let path):
                return "Selection key '\(path)' refers to an associated-type path; associated types are derived from the substituted parameter and cannot be set directly"
            case .protocolNotInIndexer(let param, let proto):
                return "Cannot validate conformance of parameter '\(param)' to '\(proto)': protocol descriptor not found in indexer (add the defining image as a sub-indexer to enable the check)"
            case .conformanceCheckFailed(let param, let proto, let reason):
                return "Conformance check for parameter '\(param)' against protocol '\(proto)' failed to run: \(reason)"
            case .baseClassRequirementResolutionFailed(let param, let reason):
                return "Could not resolve required base class for parameter '\(param)'; preflight skipped the inheritance check: \(reason)"
            case .sameTypeRequirementResolutionSkipped(let param, let reason):
                return "Could not resolve same-type requirement for parameter '\(param)'; preflight skipped the equality check: \(reason)"
            }
        }
    }
}

// MARK: - Builder

extension SpecializationValidation {
    /// Builder for constructing validation results
    public final class Builder: @unchecked Sendable {
        private var errors: [Error] = []
        private var warnings: [Warning] = []

        public init() {}

        /// Add an error
        @discardableResult
        public func addError(_ error: Error) -> Builder {
            errors.append(error)
            return self
        }

        /// Add a warning
        @discardableResult
        public func addWarning(_ warning: Warning) -> Builder {
            warnings.append(warning)
            return self
        }

        /// Build the validation result
        public func build() -> SpecializationValidation {
            SpecializationValidation(
                isValid: errors.isEmpty,
                errors: errors,
                warnings: warnings
            )
        }
    }

    /// Create a new builder
    public static func builder() -> Builder {
        Builder()
    }
}

// MARK: - LocalizedError Conformance

extension SpecializationValidation.Error: LocalizedError {
    public var errorDescription: String? {
        description
    }
}
