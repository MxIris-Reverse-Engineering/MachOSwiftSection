import Foundation
import Testing
import MachOKit
import CrossReferenceAnalysis
@_spi(Internals) import MachOCodeReferences
@_spi(Internals) import ObjCCodeReferences

/// Every reference of a standalone binary, read in file mode and written one
/// function at a time, to compare with a disassembler's cross references by
/// hand. Not a regression test: it runs only with
/// `CROSS_REFERENCE_STANDALONE_DUMP_INPUT=<binary>` (the arm64e slice of a
/// universal file is taken, else the arm64 one) and
/// `CROSS_REFERENCE_STANDALONE_DUMP_OUTPUT=<file>`.
@Suite(.enabled(if: StandaloneFileReferenceDumpEnvironment.inputPath != nil && StandaloneFileReferenceDumpEnvironment.outputPath != nil, "set CROSS_REFERENCE_STANDALONE_DUMP_INPUT and CROSS_REFERENCE_STANDALONE_DUMP_OUTPUT"))
struct StandaloneFileReferenceDumpTests {
    @Test func standaloneFileReferencesAreWrittenForComparison() throws {
        let inputPath = try #require(StandaloneFileReferenceDumpEnvironment.inputPath)
        let outputPath = try #require(StandaloneFileReferenceDumpEnvironment.outputPath)
        let file: MachOFile
        switch try MachOKit.loadFromFile(url: URL(fileURLWithPath: inputPath)) {
        case .machO(let machO):
            file = machO
        case .fat(let fatFile):
            let slices = try fatFile.machOFiles()
            file = try #require(
                slices.first { $0.header.cpuSubType == .arm64(.arm64e) } ?? slices.first { $0.header.cpuType == .arm64 },
                "no arm64 slice in \(inputPath)"
            )
        }
        let analyzer = try CrossReferenceAnalyzer(machOFiles: [file], recordingStringReferences: true)
        let functions = analyzer.functions(inImageAt: 0)
        let functionsByLocation = Dictionary(functions.map { ($0.location, $0) }, uniquingKeysWith: { first, _ in first })
        var lines: [String] = []
        var currentFunction: CodeLocation?
        for reference in analyzer.referenceTable(ofImageAt: 0).references {
            if reference.function != currentFunction {
                currentFunction = reference.function
                let name = functionsByLocation[reference.function].map { Self.describe($0.name) } ?? "<unnamed>"
                lines.append("function 0x\(String(reference.function.address, radix: 16)) \(name)")
            }
            lines.append("  0x\(String(reference.instructionAddress, radix: 16)) \(reference.kind) \(Self.describe(reference.target, functionsByLocation: functionsByLocation)) via \(reference.route)\(reference.isRuntimeHelperCall ? " helper" : "")")
        }
        try (lines.joined(separator: "\n") + "\n").write(toFile: outputPath, atomically: true, encoding: .utf8)
        #expect(lines.count > 100)
    }

    private static func describe(_ name: CodeFunction.Name?) -> String {
        switch name {
        case .symbol(let symbol)?: symbol
        case .objectiveCMethod(let className, let selector, let isClassMethod)?: "\(isClassMethod ? "+" : "-")[\(className) \(selector)]"
        case .swiftMetadata(let mangledName)?: mangledName
        case nil: "<unnamed>"
        }
    }

    private static func describe(_ target: CodeReferenceTarget, functionsByLocation: [CodeLocation: CodeFunction]) -> String {
        switch target {
        case .function(let location):
            "function 0x\(String(location.address, radix: 16)) \(describe(functionsByLocation[location]?.name))"
        case .importedSymbol(let name):
            "imported \(name)"
        case .messageSend(let selector, let receiver):
            "send \(selector) receiver \(receiver)"
        case .superMessageSend(let selector, let className):
            "superSend \(selector) class \(className ?? "?")"
        case .swiftType(let descriptor):
            "swiftType 0x\(String(descriptor.address, radix: 16))"
        case .swiftTypeName(let name):
            "swiftTypeName \(name)"
        case .objectiveCClass(let name, let location):
            "class \(name) 0x\(String(location.address, radix: 16))"
        case .objectiveCInstanceVariable(let className, let name):
            "ivar \(className).\(name)"
        case .selector(let selector):
            "selector \(selector)"
        case .cString(let characters):
            "cString \(characters.debugDescription)"
        case .constantString(let characters):
            "constantString \(characters.debugDescription)"
        case .indirect(let evidence):
            "indirect \(evidence)"
        case .unrecognized(let address):
            "unrecognized 0x\(String(address, radix: 16))"
        }
    }
}

enum StandaloneFileReferenceDumpEnvironment {
    static let inputPath = ProcessInfo.processInfo.environment["CROSS_REFERENCE_STANDALONE_DUMP_INPUT"]
    static let outputPath = ProcessInfo.processInfo.environment["CROSS_REFERENCE_STANDALONE_DUMP_OUTPUT"]
}
