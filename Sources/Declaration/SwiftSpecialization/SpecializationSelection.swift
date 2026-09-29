import Foundation
import MachOSwiftSection

/// User's selection of concrete types for generic parameters
public struct SpecializationSelection: Sendable {
    /// Parameter name to argument mapping
    public let arguments: [String: Argument]

    public init(arguments: [String: Argument]) {
        self.arguments = arguments
    }

    /// Get argument for a parameter name
    public subscript(parameterName: String) -> Argument? {
        arguments[parameterName]
    }

    /// Check if all required parameters are provided
    public func hasArgument(for parameterName: String) -> Bool {
        arguments[parameterName] != nil
    }

    /// Get all parameter names that have selections
    public var selectedParameterNames: [String] {
        Array(arguments.keys)
    }
}

// MARK: - Argument

extension SpecializationSelection {
    /// A selected type for a generic parameter
    public enum Argument: @unchecked Sendable {
        /// Runtime metatype (Any.Type)
        case metatype(Any.Type)

        /// Metadata directly provided
        case metadata(Metadata)

        /// Selected from candidate list (requires resolution in MachO context)
        case candidate(SpecializationRequest.Candidate)

        /// Already specialized generic type (for recursive specialization)
        case specialized(SpecializationResult)

        /// Bind a generic candidate (e.g. `Array`, `Dictionary`) to a nested
        /// selection. The specializer recursively builds an inner
        /// `SpecializationRequest` from `baseCandidate`'s descriptor and
        /// substitutes `innerArguments`; the resulting metadata feeds the
        /// outer key-arguments buffer in place of a concrete leaf type.
        ///
        /// `baseCandidate.isGeneric` must be `true`. Selecting a non-generic
        /// candidate via this case produces a typed
        /// `SpecializerError.specializationFailed` at specialization time.
        case boundGeneric(
            baseCandidate: SpecializationRequest.Candidate,
            innerArguments: [String: Argument]
        )
    }
}

// MARK: - Builder Pattern

extension SpecializationSelection {
    /// Builder for constructing selections incrementally
    public final class Builder: @unchecked Sendable {
        private var arguments: [String: Argument] = [:]

        public init() {}

        /// Add a metatype argument
        @discardableResult
        public func set(_ parameterName: String, to type: Any.Type) -> Builder {
            arguments[parameterName] = .metatype(type)
            return self
        }

        /// Add a metadata argument
        @discardableResult
        public func set(_ parameterName: String, to metadata: Metadata) -> Builder {
            arguments[parameterName] = .metadata(metadata)
            return self
        }

        /// Add a candidate argument
        @discardableResult
        public func set(_ parameterName: String, to candidate: SpecializationRequest.Candidate) -> Builder {
            arguments[parameterName] = .candidate(candidate)
            return self
        }

        /// Add a specialized type argument
        @discardableResult
        public func set(_ parameterName: String, to specialized: SpecializationResult) -> Builder {
            arguments[parameterName] = .specialized(specialized)
            return self
        }

        /// Bind a generic candidate to a nested selection. Equivalent to
        /// constructing `Argument.boundGeneric(baseCandidate:innerArguments:)`
        /// inline; the specializer expands `innerArguments` into a recursive
        /// `SpecializationRequest` substitution on the candidate's descriptor.
        @discardableResult
        public func set(
            _ parameterName: String,
            to candidate: SpecializationRequest.Candidate,
            boundTo innerArguments: [String: Argument]
        ) -> Builder {
            arguments[parameterName] = .boundGeneric(
                baseCandidate: candidate,
                innerArguments: innerArguments
            )
            return self
        }

        /// Remove an argument
        @discardableResult
        public func remove(_ parameterName: String) -> Builder {
            arguments.removeValue(forKey: parameterName)
            return self
        }

        /// Build the selection
        public func build() -> SpecializationSelection {
            SpecializationSelection(arguments: arguments)
        }
    }

    /// Create a new builder
    public static func builder() -> Builder {
        Builder()
    }
}

// MARK: - ExpressibleByDictionaryLiteral

extension SpecializationSelection: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Argument)...) {
        self.arguments = Dictionary(uniqueKeysWithValues: elements)
    }
}
