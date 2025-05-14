//
//  Dump.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/9.
//

import MachOKit
import MachOSwiftSection

enum Dump {
    static func dumpTypeContextDescriptors(in machOFile: MachOFile) async throws {
        guard let typeContextDescriptors = machOFile.swift.typeContextDescriptors else {
            throw Error.notFound
        }
        for typeContextDescriptor in typeContextDescriptors {
            let fieldDescriptor = try typeContextDescriptor.fieldDescriptor(in: machOFile)
            print("----------------------------------------")
            do {
                try print(typeContextDescriptor.flags.kind, typeContextDescriptor.fullname(in: machOFile), "{")
                let records = try fieldDescriptor.records(in: machOFile)
                for (index, record) in records.enumerated() {
                    do {
                        let mangledTypeName = try record.mangledTypeName(in: machOFile)
                        print(mangledTypeName.description.components(separatedBy: "\n").map { "    " + $0 }.joined(separator: "\n"))
                        var fieldName = try record.fieldName(in: machOFile)
                        var demangledTypeName = ""
                        if !mangledTypeName.isEmpty {
                            demangledTypeName = (try? MetadataReader.demangle(for: mangledTypeName, in: machOFile)) ?? mangledTypeName.symbolStringValue()
                        }
                        let isLazy = fieldName.hasPrefix("$__lazy_storage_$_")
                        let isWeak = demangledTypeName.hasPrefix("weak ")
                        fieldName = fieldName.replacingOccurrences(of: "$__lazy_storage_$_", with: "")
                        demangledTypeName = demangledTypeName.replacingOccurrences(of: "weak ", with: "")
                        if typeContextDescriptor.flags.kind == .enum {
                            if !demangledTypeName.isEmpty, !demangledTypeName.starts(with: "(") {
                                demangledTypeName = "(" + demangledTypeName + ")"
                            }
                            print("    ", "\(record.flags.contains(.isIndirectCase) ? "indirect " : "")case", "\(fieldName)\(demangledTypeName)")
                        } else {
                            print("    ", "\(record.flags.contains(.isVariadic) ? isLazy ? "lazy var" : isWeak ? "weak var" : "var" : "let")", "\(fieldName):", demangledTypeName)
                        }

                        if index != records.count - 1 {
                            print("")
                        }
                    } catch {
                        print(error)
                    }
                }
                print("}")
            } catch {
                print(error)
            }
        }
    }
}
