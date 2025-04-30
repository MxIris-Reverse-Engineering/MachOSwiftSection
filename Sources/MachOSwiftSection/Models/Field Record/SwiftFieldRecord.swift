import Foundation
@_spi(Support) import MachOKit

public struct SwiftFieldRecord: LayoutWrapperWithOffset {
    public struct Layout {
        public let flags: UInt32
        public let mangledTypeName: Int32
        public let fieldName: Int32
    }

    public let offset: Int

    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}

extension SwiftFieldRecord {
    public var flags: SwiftFieldRecordFlags {
        return SwiftFieldRecordFlags(rawValue: layout.flags)
    }

    public func mangledTypeName(in machO: MachOFile) -> String? {
        let offset = offset + layoutOffset(of: \.mangledTypeName) + Int(layout.mangledTypeName)
        return machO.fileHandle.readString(offset: numericCast(offset + machO.headerStartOffset))
    }

    public func fieldName(in machO: MachOFile) -> String? {
        let offset = offset + layoutOffset(of: \.fieldName) + Int(layout.fieldName)
        return machO.fileHandle.readString(offset: numericCast(offset + machO.headerStartOffset))
    }
}

extension String {
    func isAsciiString() -> Bool {
        return range(of: ".*[^A-Za-z0-9_$ ].*", options: .regularExpression) == nil
    }

    func toPointer() -> UnsafePointer<UInt8>? {
        guard let data = data(using: String.Encoding.utf8) else { return nil }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        let stream = OutputStream(toBuffer: buffer, capacity: data.count)

        stream.open()
        data.withUnsafeBytes { (bp: UnsafeRawBufferPointer) in
            if let sp: UnsafePointer<UInt8> = bp.baseAddress?.bindMemory(to: UInt8.self, capacity: MemoryLayout<Any>.stride) {
                stream.write(sp, maxLength: data.count)
            }
        }

        stream.close()

        return UnsafePointer<UInt8>(buffer)
    }
}

extension Data {
    func rawValue() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }
}


