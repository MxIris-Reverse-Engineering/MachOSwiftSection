import ArgumentParser
import Foundation
import SwiftSectionKit

struct ReferencesCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "refs",
        abstract: "List the code that references a selector, a symbol, a class, a function, an instance variable, a string or a Swift type — or what a function references — across a dyld shared cache or a set of arm64 Mach-O files.",
        discussion: "Addresses in and out are unslid, as IDA, ipsw and dyld_info show them. Each line is a reference: the referencing instruction's address, its image, its function and the offset into it, the reference's kind and route, and what it references."
    )

    @Argument(help: "Mach-O files to analyze together, such as an app's executable and its frameworks.", completion: .file())
    var filePaths: [String] = []

    @OptionGroup var inputOptions: CrossReferenceInputOptionGroup

    @Option(help: "Every send of this selector, super sends included (makeKeyAndOrderFront:), and every other use of it: an argument of respondsToSelector: or performSelector:, a returned selector, an action.")
    var selector: String?

    @Option(help: "The callers of the function this symbol names, with its leading underscore: a C function, a Swift mangled name, _OBJC_CLASS_$_<class> or _OBJC_IVAR_$_<class>.<ivar>. A function no analyzed image defines is looked for as the imported symbol it is.")
    var symbol: String?

    @Option(name: .customLong("class"), help: "Every reference to the Objective-C class with this runtime name (NSWindow, _TtC7SwiftUI20FilePresenterWrapper).")
    var className: String?

    @Option(help: "The callers of the function holding this unslid address (0x… or decimal).")
    var function: String?

    @Option(name: .customLong("function-image"), help: "The image --function's address is in, by path or file name: needed only when several of the files hold a function there.")
    var functionImage: String?

    @Flag(help: "With --function: list what the function references instead of its callers.")
    var callees: Bool = false

    @Option(name: .customLong("ivar"), help: "Every load of the offset of this Objective-C instance variable, written <class>.<ivar>.")
    var instanceVariable: String?

    @Option(help: "Every reference to a C string or constant CFString literal with these characters.")
    var string: String?

    @Option(name: .customLong("type"), help: "Every reference to the Swift struct, enum or class with this mangling (7SwiftUI4TextV), or to the one a $s…Mn, $s…Ma or $s…N symbol names: its metadata accessor called or its address taken, its metadata, a mangled name spelling it.")
    var swiftType: String?

    @Option(name: .customLong("type-image"), help: "The image that defines --type's type, by path or file name: needed in a dyld shared cache for a type no image exports.")
    var swiftTypeImage: String?

    @Option(help: "Report at most this many references, the first in image and address order.")
    var limit: Int?

    @Flag(help: "Print one JSON document; its addresses are hexadecimal strings.")
    var json: Bool = false

    func validate() throws {
        let queryCount = [selector, symbol, className, function, instanceVariable, string, swiftType].compactMap { $0 }.count
        guard queryCount == 1 else {
            throw ValidationError("Name exactly one of --selector, --symbol, --class, --function, --ivar, --string and --type.")
        }
        if swiftTypeImage != nil, swiftType == nil { throw ValidationError("--type-image names the image that defines --type's type; it needs --type.") }
        if callees, function == nil { throw ValidationError("--callees lists a function's references; it needs --function.") }
        if functionImage != nil, function == nil { throw ValidationError("--function-image names the image of --function's address; it needs --function.") }
        if let instanceVariable, !Self.isQualifiedInstanceVariableName(instanceVariable) {
            throw ValidationError("--ivar takes <class>.<ivar>, as in NSWindow._frame.")
        }
        if let limit, limit < 1 { throw ValidationError("--limit takes a positive number.") }
        if let function { _ = try parseAddress(function) }
        _ = try inputOptions.input(filePaths: filePaths)
    }

    private static func isQualifiedInstanceVariableName(_ text: String) -> Bool {
        guard let dot = text.lastIndex(of: ".") else { return false }
        return dot != text.startIndex && text.index(after: dot) != text.endIndex
    }

    /// The library request these flags describe.
    func makeRequest() throws -> ReferencesRequest {
        let subject: CrossReferenceSubject
        if let selector {
            subject = .selector(selector)
        } else if let symbol {
            subject = .symbol(symbol)
        } else if let className {
            subject = .objectiveCClass(className)
        } else if let function {
            subject = .function(address: try parseAddress(function), imageName: functionImage)
        } else if let instanceVariable, let dot = instanceVariable.lastIndex(of: ".") {
            subject = .instanceVariable(className: String(instanceVariable[..<dot]), name: String(instanceVariable[instanceVariable.index(after: dot)...]))
        } else if let string {
            subject = .string(string)
        } else if let swiftType {
            subject = .swiftType(swiftType, imageName: swiftTypeImage)
        } else {
            throw ValidationError("Name exactly one of --selector, --symbol, --class, --function, --ivar, --string and --type.")
        }
        return ReferencesRequest(
            input: try inputOptions.input(filePaths: filePaths),
            subject: subject,
            direction: callees ? .callees : .callers,
            imageNames: inputOptions.imageNames,
            limit: limit,
            format: json ? .json : .text
        )
    }

    func run() async throws {
        let request = try makeRequest()
        do {
            try await request.run(output: StandardStreamOutput())
        } catch {
            throw CommandLineErrorTranslation.translated(error)
        }
    }
}
