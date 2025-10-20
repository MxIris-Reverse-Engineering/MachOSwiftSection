// TypeBuilder protocol extensions and concrete implementations

// Requirement types
public struct Requirement<BuiltType, BuiltLayoutConstraint> {
    public let kind: RequirementKind
    public let subjectType: BuiltType
    public let constraintType: ConstraintType

    public enum ConstraintType {
        case type(BuiltType)
        case layout(BuiltLayoutConstraint)
    }

    public init(kind: RequirementKind, subjectType: BuiltType, constraintType: BuiltType) {
        self.kind = kind
        self.subjectType = subjectType
        self.constraintType = .type(constraintType)
    }

    public init(kind: RequirementKind, subjectType: BuiltType, layout: BuiltLayoutConstraint) {
        self.kind = kind
        self.subjectType = subjectType
        self.constraintType = .layout(layout)
    }
}

public struct InverseRequirement<BuiltType> {
    public let subjectType: BuiltType
    public let protocolKind: InvertibleProtocolKind

    public init(subjectType: BuiltType, protocolKind: InvertibleProtocolKind) {
        self.subjectType = subjectType
        self.protocolKind = protocolKind
    }
}

public struct Substitution<BuiltType> {
    public let genericParam: BuiltType
    public let replacement: BuiltType

    public init(genericParam: BuiltType, replacement: BuiltType) {
        self.genericParam = genericParam
        self.replacement = replacement
    }
}

public struct SILBoxField<BuiltType> {
    public let type: BuiltType
    public let isMutable: Bool

    public init(type: BuiltType, isMutable: Bool) {
        self.type = type
        self.isMutable = isMutable
    }
}

// Extension to fix the decodeRequirement method
