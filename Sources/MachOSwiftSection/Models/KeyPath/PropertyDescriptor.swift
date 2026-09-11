import Foundation
import MachOKit
import MachOBase

/// A property descriptor: the constant the compiler emits for every property
/// that sits on a module's ABI boundary, symbol `…vpMV`.
///
/// It is the indirection layer that makes key paths resilient. A client
/// forming `\Point.x` across a module boundary cannot know whether `x` is
/// stored (at which offset) or computed (through which getter), so it emits
/// an `external` component pointing here, and the runtime copies this
/// descriptor's content into the instantiated key path. The defining module
/// can change the property's implementation without the client rebuilding.
///
/// The descriptor's content is exactly one serialized key path component: a
/// `KeyPathComponentHeader` followed by a body whose length the header
/// decides (`KeyPathComponentHeader.propertyDescriptorBodySize`). A header
/// word of zero is the *trivial* marker — the descriptor overrides nothing,
/// and every trivial descriptor in a module is emitted once and aliased, so
/// many `…vpMV` symbols legitimately share one address.
///
/// There is no section listing property descriptors: they live in
/// `__TEXT,__const` (or `__DATA_CONST,__const` once they carry relative
/// pointers) and are reached only by symbol or by a pattern's relative
/// pointer. Get an offset first, then `PropertyDescriptor.resolve(from:in:)`.
@LocatableLayoutWrapping
public struct PropertyDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let header: KeyPathComponentHeader
    }
}

extension PropertyDescriptor {
    public var header: KeyPathComponentHeader { layout.header }

    /// Whether the descriptor overrides nothing and a client should keep the
    /// component it formed locally. Trivial descriptors have no body.
    public var isTrivial: Bool { header.isTrivialPropertyDescriptor }

    /// Length in bytes of the body following the header.
    public var bodySize: Int { header.propertyDescriptorBodySize }

    /// Total length in bytes of the descriptor, header included.
    public var size: Int { MemoryLayout<Layout>.size + bodySize }

    /// Location of the body's first byte, in the same coordinate space as
    /// `offset`.
    public var bodyOffset: Int { offset + MemoryLayout<Layout>.size }

    /// The stored field offset when the header carries it outright, `nil`
    /// when the descriptor is not a stored one or the body holds the word.
    /// Pure header arithmetic — no reader involved.
    public var inlineStoredFieldOffset: KeyPathStoredFieldOffset? {
        guard let payload = header.inlineStoredFieldOffset else { return nil }
        return .inline(payload)
    }
}

// MARK: - Body Reading

extension PropertyDescriptor {
    private func storedFieldOffset(kind: KeyPathStoredFieldOffsetKind, bodyWord: @autoclosure () throws -> UInt32) rethrows -> KeyPathStoredFieldOffset {
        switch kind {
        case .inline:
            return .inline(header.storedOffsetPayload)
        case .outOfLine:
            return .outOfLine(try bodyWord())
        case .unresolvedFieldOffset:
            return .unresolvedFieldOffset(offsetOfFieldOffset: try bodyWord())
        case .unresolvedIndirectOffset:
            return .unresolvedIndirectOffset(offsetOfFieldOffsetPointer: try bodyWord())
        }
    }

    private func computedPropertyBody(
        rawIdentifier: RelativeOffset,
        getter: RelativeOffset,
        setter: RelativeOffset?
    ) -> KeyPathComputedPropertyBody {
        .init(
            header: header,
            offset: bodyOffset,
            rawIdentifier: rawIdentifier,
            getter: .init(relativeOffset: getter),
            setter: setter.map { .init(relativeOffset: $0) }
        )
    }

    private var settableSetterFieldRelativeOffset: Int {
        MemoryLayout<RelativeOffset>.size * 2
    }

    private var getterFieldRelativeOffset: Int {
        MemoryLayout<RelativeOffset>.size
    }
}

extension PropertyDescriptor {
    /// The stored property's field offset, reading the body word when the
    /// header only carried a sentinel. `nil` when the descriptor is trivial
    /// or its component is not a stored one.
    public func storedFieldOffset<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> KeyPathStoredFieldOffset? {
        guard !isTrivial, let kind = header.storedFieldOffsetKind else { return nil }
        return try storedFieldOffset(kind: kind, bodyWord: try UInt32.resolve(from: bodyOffset, in: machO))
    }

    /// The computed component's identifier, getter and setter. `nil` when the
    /// descriptor is trivial or its component is not a computed one.
    public func computedPropertyBody<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> KeyPathComputedPropertyBody? {
        guard !isTrivial, header.kind == .computed else { return nil }
        let rawIdentifier: RelativeOffset = try RelativeOffset.resolve(from: bodyOffset, in: machO)
        let getter: RelativeOffset = try RelativeOffset.resolve(from: bodyOffset + getterFieldRelativeOffset, in: machO)
        var setter: RelativeOffset?
        if header.isComputedSettable {
            setter = try RelativeOffset.resolve(from: bodyOffset + settableSetterFieldRelativeOffset, in: machO)
        }
        return computedPropertyBody(rawIdentifier: rawIdentifier, getter: getter, setter: setter)
    }
}

// MARK: - In-Process Support

extension PropertyDescriptor {
    public func storedFieldOffset() throws -> KeyPathStoredFieldOffset? {
        guard !isTrivial, let kind = header.storedFieldOffsetKind else { return nil }
        let bodyPointer = try asPointer.advanced(by: MemoryLayout<Layout>.size)
        return try storedFieldOffset(kind: kind, bodyWord: try UInt32.resolve(from: bodyPointer))
    }

    public func computedPropertyBody() throws -> KeyPathComputedPropertyBody? {
        guard !isTrivial, header.kind == .computed else { return nil }
        let bodyPointer = try asPointer.advanced(by: MemoryLayout<Layout>.size)
        let rawIdentifier: RelativeOffset = try RelativeOffset.resolve(from: bodyPointer)
        let getter: RelativeOffset = try RelativeOffset.resolve(from: bodyPointer.advanced(by: getterFieldRelativeOffset))
        var setter: RelativeOffset?
        if header.isComputedSettable {
            setter = try RelativeOffset.resolve(from: bodyPointer.advanced(by: settableSetterFieldRelativeOffset))
        }
        return computedPropertyBody(rawIdentifier: rawIdentifier, getter: getter, setter: setter)
    }
}

// MARK: - ReadingContext Support

extension PropertyDescriptor {
    public func storedFieldOffset<Context: ReadingContext>(in context: Context) throws -> KeyPathStoredFieldOffset? {
        guard !isTrivial, let kind = header.storedFieldOffsetKind else { return nil }
        let bodyAddress = try context.addressFromOffset(bodyOffset)
        return try storedFieldOffset(kind: kind, bodyWord: try UInt32.resolve(at: bodyAddress, in: context))
    }

    public func computedPropertyBody<Context: ReadingContext>(in context: Context) throws -> KeyPathComputedPropertyBody? {
        guard !isTrivial, header.kind == .computed else { return nil }
        let bodyAddress = try context.addressFromOffset(bodyOffset)
        let getterAddress = context.advanceAddress(bodyAddress, by: getterFieldRelativeOffset)
        let rawIdentifier: RelativeOffset = try RelativeOffset.resolve(at: bodyAddress, in: context)
        let getter: RelativeOffset = try RelativeOffset.resolve(at: getterAddress, in: context)
        var setter: RelativeOffset?
        if header.isComputedSettable {
            let setterAddress = context.advanceAddress(bodyAddress, by: settableSetterFieldRelativeOffset)
            setter = try RelativeOffset.resolve(at: setterAddress, in: context)
        }
        return computedPropertyBody(rawIdentifier: rawIdentifier, getter: getter, setter: setter)
    }
}
