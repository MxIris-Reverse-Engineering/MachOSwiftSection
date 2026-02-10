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

        /// Selected type does not satisfy a same-type requirement
        case sameTypeRequirementNotSatisfied(
            parameterName: String,
            expectedType: String,
            actualType: String
        )

        /// Selected type does not satisfy a base class requirement
        case baseClassRequirementNotSatisfied(
            parameterName: String,
            expectedBaseClass: String,
            actualType: String
        )

        /// Selected type does not satisfy a layout requirement
        case layoutRequirementNotSatisfied(
            parameterName: String,
            expectedLayout: SpecializationRequest.LayoutKind,
            actualType: String
        )

        /// Could not resolve candidate type to metadata
        case candidateResolutionFailed(
            parameterName: String,
            candidateTypeName: String,
            reason: String
        )

        /// Associated type could not be resolved
        case associatedTypeResolutionFailed(
            parameterName: String,
            associatedTypePath: [String],
            reason: String
        )

        /// The selected type is generic and requires further specialization
        case requiresFurtherSpecialization(
            parameterName: String,
            typeName: String,
            genericParameters: [String]
        )

        /// Unknown or unexpected error
        case unknown(String)

        public var description: String {
            switch self {
            case .missingArgument(let name):
                return "Missing argument for parameter '\(name)'"

            case .protocolRequirementNotSatisfied(let param, let proto, let actual):
                return "Type '\(actual)' for parameter '\(param)' does not conform to protocol '\(proto)'"

            case .sameTypeRequirementNotSatisfied(let param, let expected, let actual):
                return "Type '\(actual)' for parameter '\(param)' must be same as '\(expected)'"

            case .baseClassRequirementNotSatisfied(let param, let base, let actual):
                return "Type '\(actual)' for parameter '\(param)' must inherit from '\(base)'"

            case .layoutRequirementNotSatisfied(let param, let layout, let actual):
                return "Type '\(actual)' for parameter '\(param)' does not satisfy layout requirement '\(layout)'"

            case .candidateResolutionFailed(let param, let candidate, let reason):
                return "Cannot resolve candidate '\(candidate)' for parameter '\(param)': \(reason)"

            case .associatedTypeResolutionFailed(let param, let path, let reason):
                return "Cannot resolve associated type '\(param).\(path.joined(separator: "."))': \(reason)"

            case .requiresFurtherSpecialization(let param, let type, let genericParams):
                return "Type '\(type)' for parameter '\(param)' is generic and requires specialization of: \(genericParams.joined(separator: ", "))"

            case .unknown(let message):
                return "Validation error: \(message)"
            }
        }
    }
}

// MARK: - Warning

extension SpecializationValidation {
    /// Validation warning
    public enum Warning: Sendable, CustomStringConvertible {
        /// The selected type may cause performance issues
        case potentialPerformanceIssue(
            parameterName: String,
            reason: String
        )

        /// The selected type is deprecated
        case deprecatedType(
            parameterName: String,
            typeName: String
        )

        /// Extra argument provided that is not needed
        case extraArgument(parameterName: String)

        public var description: String {
            switch self {
            case .potentialPerformanceIssue(let param, let reason):
                return "Parameter '\(param)' may cause performance issues: \(reason)"

            case .deprecatedType(let param, let type):
                return "Type '\(type)' for parameter '\(param)' is deprecated"

            case .extraArgument(let param):
                return "Extra argument '\(param)' is not needed for this specialization"
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
