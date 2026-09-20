import MemberwiseInit
import MachOSymbols
import MachOSwiftSection
import SwiftInspection

public protocol AccessorRepresentable: Sendable {
    var accessors: [Accessor] { get }

    /// The `override` fact the ObjC side supplies when the Swift side cannot
    /// (evolution proposal `objc-ancestor-override-recovery`): an override of
    /// a member inherited from an ObjC class gets a NEW vtable entry, not an
    /// override-table one, so only the member's `To` thunk sitting at an IMP
    /// whose selector an ObjC ancestor also implements proves it.
    var objcAncestorOverride: ObjCAncestorOverride? { get }
}

extension AccessorRepresentable {
    public var isStored: Bool { accessors.contains { $0.kind == .none } }
    public var isOverride: Bool {
        objcAncestorOverride != nil || accessors.contains(where: { ($0.methodDescriptor?.isMethodOverride ?? false) || ($0.methodDescriptor?.isMethodDefaultOverride ?? false) })
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
