import Testing
import Foundation
@_spi(Core) @testable import MachOSwiftSection
@_spi(Support) import MachOKit
import MachOObjCSection

@Suite
struct MachOFileSwiftSectionTests {
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
                var mangledName = ""
                if let mangledTypeName = record.mangledTypeName(in: machOFile) {
                    if mangledTypeName.starts(with: "0x") {
                        let hexName: String = mangledTypeName.removingPrefix("0x")
                        var dataArray: [UInt8] = hexName.hexBytes
                        var i = 0
                        while i < dataArray.count {
                            let value = dataArray[i]
                            guard let (kind, directness) = SwiftSymbolicReference.symbolicReference(for: value) else {
                                mangledName = mangledName + String(format: "%c", value)
                                i = i + 1
                                continue
                            }
                            switch kind {
                            case .context:
                                switch directness {
                                case .direct:
                                    // find
                                    let fromIndex: Int = i + 1 // ignore 0x01
                                    let toIndex: Int = i + 5 // 4 bytes

                                    if toIndex > dataArray.count {
                                        dataArray.append(contentsOf: [UInt8](repeating: 0, count: toIndex - dataArray.count))
                                    }
                                    let offsetArray: [UInt8] = Array(dataArray[fromIndex ..< toIndex])

                                    let ptr = record.offset(of: \.mangledTypeName) + Int(record.layout.mangledTypeName) + fromIndex

                                    let offset = offsetArray.withUnsafeBytes { rawBufferPointer in
                                        return rawBufferPointer.load(as: Int32.self)
                                    }

                                    let addrPtr: UInt64 = numericCast(Int(ptr) + Int(offset))

                                    if let name = machOFile.swift._readTypeContextDescriptor(from: addrPtr, in: machOFile)?.name(in: machOFile) {
                                        mangledName += name
                                        if i == 0, toIndex >= dataArray.count {
                                            mangledName = mangledName + name
                                        } else {
                                            mangledName = mangledName + makeDemangledTypeName(name, header: mangledName)
                                        }
                                    }
                                    i = i + 5
                                case .indirect:
                                    let fromIndex: Int = i + 1 // ignore 0x02
                                    let toIndex: Int = i + 5

                                    if toIndex > dataArray.count {
                                        dataArray.append(contentsOf: [UInt8](repeating: 0, count: toIndex - dataArray.count))
                                    }

                                    let offsetArray: [UInt8] = Array(dataArray[fromIndex ..< toIndex])

                                    let ptr = record.offset(of: \.mangledTypeName) + Int(record.layout.mangledTypeName) + fromIndex

                                    let offset = offsetArray.withUnsafeBytes { rawBufferPointer in
                                        return rawBufferPointer.load(as: Int32.self)
                                    }
                                    let addrPtr: UInt64 = numericCast(Int(ptr) + Int(offset))

                                    if let bind = machOFile.resolveBind(at: machOFile.fileOffset(of: addrPtr)), let symbolName = machOFile.dyldChainedFixups?.symbolName(for: bind.0.info.nameOffset) {
                                        if i == 0, toIndex >= dataArray.count {
                                            mangledName = mangledName + symbolName
                                        } else {
                                            mangledName = mangledName + makeDemangledTypeName(symbolName, header: mangledName)
                                        }
                                    } else if let rebase = machOFile.resolveRebase(at: addrPtr), let name = machOFile.swift._readTypeContextDescriptor(from: rebase, in: machOFile)?.name(in: machOFile) {
                                        if i == 0, toIndex >= dataArray.count {
                                            mangledName = mangledName + name
                                        } else {
                                            mangledName = mangledName + makeDemangledTypeName(name, header: mangledName)
                                        }
                                    }

                                    i = i + 5
                                }
                            case .accessorFunctionReference:
                                break
                            case .uniqueExtendedExistentialTypeShape:
                                break
                            case .nonUniqueExtendedExistentialTypeShape:
                                break
                            case .objectiveCProtocol:
                                let fromIdx: Int = i + 1 // ignore 0x01
                                let toIdx: Int = i + 5 // 4 bytes
                                if toIdx > dataArray.count {
                                    dataArray.append(contentsOf: [UInt8](repeating: 0, count: toIdx - dataArray.count))
                                }
                                let offsetArray: [UInt8] = Array(dataArray[fromIdx ..< toIdx])

                                let ptr = record.offset + record.layoutOffset(of: \.mangledTypeName) + Int(record.layout.mangledTypeName) + fromIdx

                                let offset = offsetArray.withUnsafeBytes { rawBufferPointer in
                                    return rawBufferPointer.load(as: Int32.self)
                                }
                                let addrPtr: UInt64 = numericCast(Int(ptr) + Int(offset))
                                let offset2: Int32 = machOFile.fileHandle.read(offset: addrPtr + 4)
                                print(offset2, Int(addrPtr + 4) + Int(offset2), Int(ptr) + Int(offset2))
                                
//                                i = i + 5
                                continue nominalTypesForEach
                            }
                        }
                    } else {
                        mangledName = mangledTypeName
                    }
                }

                print(record.mangledTypeName(in: machOFile) as Any, Optional(mangledName) as Any, record.fieldName(in: machOFile) as Any)

                let result: String = getTypeFromMangledName(mangledName)
                if result == mangledName {
                    if mangledName.contains("$s") {
                        if let s = swift_demangle(mangledName) {
                            print("Demangled: \(s)")
                        }
                    } else {
                        if let s = swift_demangle("$s" + mangledName) {
                            print("Demangled: \(s)")
                        }
                    }
                } else {
                    print("Demangled: \(result)")
                }
            }
        }
    }

    @Test func rebase() async throws {
        guard let rebase = machOFile.resolveRebase(at: 22524756) else { return }
        print(rebase)
        let bind = machOFile.resolveBind(at: rebase)

        guard let info = bind?.0.info else { return }

        print(machOFile.dyldChainedFixups?.symbolName(for: info.nameOffset) ?? "")
    }

    @Test func bind() async throws {
//        print(machOFile.fileOffset(of: 0x143b71d08))
        let bind = machOFile.resolveBind(at: 22524756)

        guard let info = bind?.0.info else { return }

        print(machOFile.dyldChainedFixups?.symbolName(for: info.nameOffset) ?? "")
    }

    @Test func contextDescriptor() async throws {
        let offset = 22524756 + machOFile.headerStartOffset
        let contextDescriptorLayout: SwiftContextDescriptor.Layout = machOFile.fileHandle.read(offset: numericCast(offset))
        let contextDescriptor = SwiftContextDescriptor(offset: numericCast(offset), layout: contextDescriptorLayout)
        print(contextDescriptor.flags.kind.description)
    }

    @Test func read() async throws {
        machOFile.objc.protocols64?.forEach { proto in
            print(proto.offset)
            proto.protocolList(in: machOFile).map { list in
                print(list.offset)
                list.protocols(in: machOFile).map { protos in
                    print(proto.offset)
                    print(proto.mangledName(in: machOFile))
                }
            }
        }
//        print(machOFile.fileOffset(of: 22524756))
//        print(machOFile.headerStartOffset)
//        print(machOFile.fileHandle.readString(offset: 22524756 + numericCast(machOFile.headerStartOffset)))
//        machOFile.swift.protocols?.forEach {
//            print($0.offset)
//        }
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
