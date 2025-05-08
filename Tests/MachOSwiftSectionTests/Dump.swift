//
//  Dump.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/9.
//

import MachOKit

enum Dump {
    static func dumpTypeContextDescriptors(in machOFile: MachOFile) async throws {
        guard let typeContextDescriptors = machOFile.swift.typeContextDescriptors else {
            throw Error.notFound
        }
        for typeContextDescriptor in typeContextDescriptors {
            let fieldDescriptor = try typeContextDescriptor.fieldDescriptor(in: machOFile)
            print("----------------------------------------")
            try print(typeContextDescriptor.flags.kind, typeContextDescriptor.name(in: machOFile), "{")
            let records = try fieldDescriptor.records(in: machOFile)
            for (index, record) in records.enumerated() {
                let mangledTypeName = try record.mangledTypeName(in: machOFile).stringValue()
                var demangledTypeName = mangledTypeName.demangled
                var fieldName = try record.fieldName(in: machOFile)
                let isLazy = fieldName.hasPrefix("$__lazy_storage_$_")
                let isWeak = demangledTypeName.hasPrefix("weak ")
                fieldName = fieldName.replacingOccurrences(of: "$__lazy_storage_$_", with: "")
                demangledTypeName = demangledTypeName.replacingOccurrences(of: "weak ", with: "")
                if typeContextDescriptor.flags.kind == .enum {
                    print("    ", mangledTypeName)

                    print("    ", "\(record.flags.contains(.isIndirectCase) ? "indirect " : "")case", "\(fieldName)\(demangledTypeName)")
                } else {
                    print("    ", mangledTypeName)

                    print("    ", "\(record.flags.contains(.isVariadic) ? isLazy ? "lazy var" : isWeak ? "weak var" : "var" : "let")", "\(fieldName):", demangledTypeName)
                }

                if index != records.count - 1 {
                    print("")
                }
            }
            print("}")
        }
    }
}
