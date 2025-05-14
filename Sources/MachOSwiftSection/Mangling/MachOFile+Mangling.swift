import Foundation
import MachOKit

extension MachOFile {
    func readSymbolicMangledName(at fileOffset: Int) throws -> MangledName {
        var elements: [MangledName.Element] = []
        var currentOffset = fileOffset
        var currentString = ""
        while true {
            let value: UInt8 = try readElement(offset: currentOffset)
            if value == 0xFF {}
            else if value == 0 {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }
                currentOffset.offset(of: UInt8.self)
                break
            } else if value >= 0x01, value <= 0x17 {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }
                let reference: Int32 = try readElement(offset: currentOffset + 1)
                let offset = Int(fileOffset + (currentOffset - fileOffset))
                elements.append(.lookup(.init(offset: offset, reference: .relative(.init(kind: value, relativeOffset: reference + 1)))))
                currentOffset.offset(of: Int32.self)
            } else if value >= 0x18, value <= 0x1F {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }
                let reference: UInt64 = try readElement(offset: currentOffset + 1)
                let offset = Int(fileOffset + (currentOffset - fileOffset))
                elements.append(.lookup(.init(offset: offset, reference: .absolute(.init(kind: value, reference: reference)))))
                currentOffset.offset(of: UInt64.self)
            } else {
                currentString.append(String(format: "%c", value))
            }
            currentOffset.offset(of: UInt8.self)
        }

        return .init(elements: elements, startOffset: fileOffset, endOffset: currentOffset)
    }
}
