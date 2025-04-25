import Testing
import Foundation
@_spi(Core) @testable import MachOSwiftSection
@_spi(Support) import MachOKit

@Suite
struct MachOSwiftSectionTests {
    enum Error: Swift.Error {
        case notFound
    }

    let machOFile: MachOFile

    init() throws {
        let path = "/System/Applications/Freeform.app/Contents/MacOS/Freeform"
        let url = URL(fileURLWithPath: path)
        guard let file = try? MachOKit.loadFromFile(url: url) else {
            throw Error.notFound
        }
        switch file {
        case let .fat(fatFile):
            self.machOFile = try! fatFile.machOFiles().first(where: { $0.header.cpu.type == .x86_64 })!
        case let .machO(machO):
            self.machOFile = machO
        }
    }

    @Test func protocolsInFile() async throws {
        guard let protocols = machOFile.swift.protocols else {
            throw Error.notFound
        }
        for proto in protocols {
            print(proto.name(in: machOFile))
        }
    }

    @Test func nominalTypesInFile() async throws {
        guard let nominalTypes = machOFile.swift.nominalTypes else {
            throw Error.notFound
        }
        nominalTypesForEach: for type in nominalTypes {
            let fieldDescriptor = type.fieldDescriptor(in: machOFile)
//            print(type.name(in: machOFile))
//            print(fieldDescriptor.offset)
//            if let mangledTypeName = fieldDescriptor.mangledTypeName(in: machOFile) {
//                let hexName: String = mangledTypeName.removingPrefix("0x")
//                let dataArray: [UInt8] = hexName.hexBytes
//                var i = 0
//                while i < dataArray.count {
//                    let val = dataArray[i]
//                    if val == 0x01 {
//                        continue nominalTypesForEach
//                    } else if val == 0x02 {
//                        print(hexName)
//                        // indirectly
//                        let fromIdx: Int = i + 1 // ignore 0x02
//                        let toIdx: Int = ((i + 4) > dataArray.count) ? (i + (dataArray.count - i)) : (i + 4) // 4 bytes
//
//                        let offsetArray: [UInt8] = Array(dataArray[fromIdx ..< toIdx])
//
//                        let tmp = offsetArray.reversed().hex;
//                        
//                        let ptr = fieldDescriptor.offset + fieldDescriptor.layoutOffset(of: \.mangledTypeName) + Int(fieldDescriptor.layout.mangledTypeName) + fromIdx
//                        
//                        guard let address = Int(tmp, radix: 16) else {
//                            continue
//                        }
//                        let addrPtr: UInt64 = numericCast(Int(ptr) + address + machOFile.headerStartOffset)
//                        
//                        let bind = machOFile.resolveBind(at: addrPtr)
//
//                        guard let info = bind?.0.info else { continue nominalTypesForEach }
//
//                        print(machOFile.dyldChainedFixups?.demangledSymbolName(for: info.nameOffset))
//                        i = toIdx + 1
//                    } else {
//                        // check next
//                        i = i + 1
//                    }
//                }
//            }
            let records = fieldDescriptor.records(in: machOFile)
            for record in records {
                print(record.mangledTypeName(in: machOFile))
//                if let mangledTypeName = record.mangledTypeName(in: machOFile) {
//                    let hexName: String = mangledTypeName.removingPrefix("0x")
//                    let dataArray: [UInt8] = hexName.hexBytes
//                    var i = 0
//                    while i < dataArray.count {
//                        let val = dataArray[i]
//                        if val == 0x01 {
//                            continue nominalTypesForEach
//                        } else if val == 0x02 {
//                            let name = type.name(in: machOFile)
//                            let fieldName = record.fieldName(in: machOFile)
//                            guard let name, let fieldName else { continue nominalTypesForEach }
//                            print("-----------------------------------------------")
//                            print(name, fieldName)
//                            
//                            // indirectly
//                            let fromIdx: Int = i + 1 // ignore 0x02
//                            let toIdx: Int = ((i + 4) > dataArray.count) ? (i + (dataArray.count - i)) : (i + 4) // 4 bytes
//
//                            let offsetArray: [UInt8] = Array(dataArray[fromIdx ..< toIdx])
//
//                            let tmp = offsetArray.reversed().hex;
//                            
//                            let ptr = record.offset + record.layoutOffset(of: \.mangledTypeName) + Int(record.layout.mangledTypeName) + fromIdx
//                            
//                            guard let address = Int(tmp, radix: 16) else {
//                                continue
//                            }
//                            let addrPtr: UInt64 = numericCast(Int(ptr) + address)
//                            print(hexName, ptr, addrPtr)
//                            
//                            if let bind = machOFile.resolveBind(at: machOFile.fileOffset(of: addrPtr)), let symbolName = machOFile.dyldChainedFixups?.symbolName(for: bind.0.info.nameOffset) {
//                                print(symbolName)
//                            } else {
//                                if let rebase = machOFile.resolveRebase(at: addrPtr) {
//                                    let contextDescriptorLayout: SwiftContextDescriptor.Layout = machOFile.fileHandle.read(offset: rebase + numericCast(machOFile.headerStartOffset))
//                                    let contextDescriptor = SwiftContextDescriptor(offset: numericCast(rebase), layout: contextDescriptorLayout)
//                                    switch contextDescriptor.flags.kind {
//                                    case .class, .enum, .protocol, .struct:
//                                        let contextDescriptorLayout: SwiftTypeContextDescriptor.Layout = machOFile.fileHandle.read(offset: rebase + numericCast(machOFile.headerStartOffset))
//                                        let contextDescriptor = SwiftTypeContextDescriptor(offset: numericCast(rebase), layout: contextDescriptorLayout)
//                                        print(machOFile.fileHandle.readString(offset: numericCast(contextDescriptor.offset + contextDescriptor.layoutOffset(of: \.name) + Int(contextDescriptor.layout.name) + machOFile.headerStartOffset)) ?? "")
//                                    default:
//                                        break
//                                    }
//                                    continue nominalTypesForEach
//                                }
//                            }
//                            i = toIdx + 1
//                        } else {
//                            continue nominalTypesForEach
//                        }
//                    }
//                }
            }
        }
    }
    
    @Test func rebase() async throws {
        guard let rebase = machOFile.resolveRebase(at: 20380072) else { return }
        print(rebase)
        let bind = machOFile.resolveBind(at: rebase)

        guard let info = bind?.0.info else { return }

        print(machOFile.dyldChainedFixups?.symbolName(for: info.nameOffset) ?? "")
    }
    
    @Test func bind() async throws {
//        print(machOFile.fileOffset(of: 0x143b71d08))
        let bind = machOFile.resolveBind(at: 20380072)

        guard let info = bind?.0.info else { return }

        print(machOFile.dyldChainedFixups?.symbolName(for: info.nameOffset) ?? "")
    }
    
    @Test func contextDescriptor() async throws {
        let offset = 19566808 + machOFile.headerStartOffset
        let contextDescriptorLayout: SwiftContextDescriptor.Layout = machOFile.fileHandle.read(offset: numericCast(offset))
        let contextDescriptor = SwiftContextDescriptor(offset: numericCast(offset), layout: contextDescriptorLayout)
        print(contextDescriptor.flags.kind.description)
    }
    
    @Test func read() async throws {
        let offset = 20342168
//        print(machOFile.fileHandle.readString(offset: numericCast(offset)))
        print(machOFile.resolveRebase(at: numericCast(offset)))
    }
}

extension Array where Element == UInt8 {
    var hex: String {
        let tmp = reduce("") { (result, val: UInt8) -> String in
            return result + String(format: "%02x", val)
        }
        return tmp
    }
}

extension String {
    func isAsciiStr() -> Bool {
        return range(of: ".*[^A-Za-z0-9_$ ].*", options: .regularExpression) == nil
    }

    var hexData: Data { .init(hexa) }

    var hexBytes: [UInt8] { .init(hexa) }

    private var hexa: UnfoldSequence<UInt8, Index> {
        sequence(state: startIndex) { startIndex in
            guard startIndex < self.endIndex else { return nil }
            let endIndex = self.index(startIndex, offsetBy: 2, limitedBy: self.endIndex) ?? self.endIndex
            defer { startIndex = endIndex }
            return UInt8(self[startIndex ..< endIndex], radix: 16)
        }
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

    func toCharPointer() -> UnsafePointer<Int8> {
        let strPtr: UnsafePointer<Int8> = withCString { (ptr: UnsafePointer<Int8>) -> UnsafePointer<Int8> in
            return ptr
        }
        return strPtr
    }

    public func removingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else { return self }
        return String(dropFirst(prefix.count))
    }

    public func removingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count))
    }
}

extension Int64 {
    var hex: String {
        return String(format: "0x%llx", self)
    }
}

extension UInt64 {
    var hex: String {
        return String(format: "0x%llx", self)
    }
}

extension Int {
    var hex: String {
        return String(format: "0x%llx", self)
    }
}

extension Int32 {
    var hex: String {
        return String(format: "0x%llx", self)
    }
}

extension UInt32 {
    var hex: String {
        return String(format: "0x%llx", self)
    }
}
