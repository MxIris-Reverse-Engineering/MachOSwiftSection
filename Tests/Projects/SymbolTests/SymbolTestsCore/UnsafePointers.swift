import Foundation

public enum UnsafePointers {
    public struct UnsafePointerFieldTest {
        public var readPointer: UnsafePointer<Int>
        public var mutablePointer: UnsafeMutablePointer<Int>
        public var rawPointer: UnsafeRawPointer
        public var mutableRawPointer: UnsafeMutableRawPointer
        public var bufferPointer: UnsafeBufferPointer<Int>
        public var mutableBufferPointer: UnsafeMutableBufferPointer<Int>
        public var rawBufferPointer: UnsafeRawBufferPointer
        public var opaquePointer: OpaquePointer

        public init(
            readPointer: UnsafePointer<Int>,
            mutablePointer: UnsafeMutablePointer<Int>,
            rawPointer: UnsafeRawPointer,
            mutableRawPointer: UnsafeMutableRawPointer,
            bufferPointer: UnsafeBufferPointer<Int>,
            mutableBufferPointer: UnsafeMutableBufferPointer<Int>,
            rawBufferPointer: UnsafeRawBufferPointer,
            opaquePointer: OpaquePointer
        ) {
            self.readPointer = readPointer
            self.mutablePointer = mutablePointer
            self.rawPointer = rawPointer
            self.mutableRawPointer = mutableRawPointer
            self.bufferPointer = bufferPointer
            self.mutableBufferPointer = mutableBufferPointer
            self.rawBufferPointer = rawBufferPointer
            self.opaquePointer = opaquePointer
        }
    }

    public struct UnmanagedFieldTest {
        public var unmanagedReference: Unmanaged<AnyObject>

        public init(unmanagedReference: Unmanaged<AnyObject>) {
            self.unmanagedReference = unmanagedReference
        }
    }

    public struct AutoreleasingPointerFieldTest {
        public var autoreleasing: AutoreleasingUnsafeMutablePointer<AnyObject?>

        public init(autoreleasing: AutoreleasingUnsafeMutablePointer<AnyObject?>) {
            self.autoreleasing = autoreleasing
        }
    }

    /// A raw pointer reserves only null, so of these two empty cases only one
    /// fits the payload's single extra inhabitant — the enum must grow a tag
    /// byte (size 9, stride 16), unlike a class-reference payload which would
    /// absorb both and stay 8.
    public enum EnumOverUnsafeRawPointerTest {
        case pointer(UnsafeRawPointer)
        case first
        case second
    }

    /// Pins the *offset* consequence of the enum above: the trailing marker
    /// must land at offset 16 (after the 9-byte enum rounds up to its 8-byte
    /// alignment), which only happens when the pointer's extra-inhabitant
    /// count is exactly 1.
    public struct EnumOverUnsafeRawPointerFieldTest {
        public var pointerEnum: EnumOverUnsafeRawPointerTest
        public var trailingMarker: Int8

        public init(pointerEnum: EnumOverUnsafeRawPointerTest, trailingMarker: Int8) {
            self.pointerEnum = pointerEnum
            self.trailingMarker = trailingMarker
        }
    }
}
