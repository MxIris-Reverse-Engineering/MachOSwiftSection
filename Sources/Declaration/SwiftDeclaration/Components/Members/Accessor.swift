import MemberwiseInit
import MachOSymbols
import MachOSwiftSection
import SwiftInspection

public protocol AccessorRepresentable: Sendable {
    var accessors: [Accessor] { get }

    /// The ObjC method the member implements, recovered from the class's ObjC
    /// method table (evolution proposals `objc-ancestor-override-recovery` and
    /// `objc-member-selector-recovery`). An override of an ObjC-inherited
    /// member has a NEW vtable entry rather than an override-table one, so
    /// only the ObjC side proves it.
    var objcMember: ObjCMember? { get }
}

extension AccessorRepresentable {
    public var isStored: Bool { accessors.contains { $0.kind == .none } }
    /// Counts only JOINED ObjC evidence. A tie made from the member's name
    /// alone is recorded on `objcMember` but acted on by the consumer that
    /// asked for it — `resolvedObjCMemberFacts(trustingSelectorNameEvidence:)`.
    public var isOverride: Bool {
        (objcMember?.isJoinedOverride ?? false) || hasVTableOverrideAccessor
    }
    /// Whether any accessor's vtable method descriptor marks it an override.
    public var hasVTableOverrideAccessor: Bool {
        accessors.contains { ($0.methodDescriptor?.isMethodOverride ?? false) || ($0.methodDescriptor?.isMethodDefaultOverride ?? false) }
    }
    public var hasSetter: Bool { accessors.contains { $0.kind == .setter } }
    public var hasModifyAccessor: Bool { accessors.contains { $0.kind == .modifyAccessor } }
    public var hasVTableAccessor: Bool { accessors.contains { $0.methodDescriptor != nil } }
}

@MemberwiseInit(.public)
public struct Accessor: Sendable {
    public let kind: AccessorKind
    public let symbol: DemangledSymbol
    public let methodDescriptor: MethodDescriptorWrapper?
    public let offset: Int?
    public let vtableOffset: Int?
}
