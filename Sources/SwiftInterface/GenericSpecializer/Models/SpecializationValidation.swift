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

        public var description: String {
            switch self {
            case .missingArgument(let name):
                return "Missing argument for parameter '\(name)'"

            case .protocolRequirementNotSatisfied(let param, let proto, let actual):
                return "Type '\(actual)' for parameter '\(param)' does not conform to protocol '\(proto)'"

            case .layoutRequirementNotSatisfied(let param, let layout, let actual):
                return "Type '\(actual)' for parameter '\(param)' does not satisfy layout requirement '\(layout)'"
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

        public var description: String {
            switch self {
            case .extraArgument(let param):
                return "Extra argument '\(param)' is not needed for this specialization"
            case .associatedTypePathInSelection(let path):
                return "Selection key '\(path)' refers to an associated-type path; associated types are derived from the substituted parameter and cannot be set directly"
            case .protocolNotInIndexer(let param, let proto):
                return "Cannot validate conformance of parameter '\(param)' to '\(proto)': protocol descriptor not found in indexer (add the defining image as a sub-indexer to enable the check)"
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
