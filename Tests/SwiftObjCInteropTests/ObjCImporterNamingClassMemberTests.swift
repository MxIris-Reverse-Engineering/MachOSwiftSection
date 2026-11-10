import Foundation
import Testing
@_spi(Internals) @testable import SwiftInspection
@_spi(Internals) @testable import SwiftObjCInterop

/// `ObjCImporterNaming` for the members of an Objective-C class (evolution
/// proposal `objc-imported-declarations`): factory methods imported as
/// initializers, the error convention told apart from other `^@` parameters,
/// and property names.
///
/// The selectors and encodings are AppKit's, as macOS 27.2's method and
/// property lists record them; the expected names are the macOS 27.2 SDK's
/// (its symbol graph), which the proposal's measurement compared against.
/// Where a method list's encoding loses the class name the SDK's naming
/// depends on, the extended encoding a protocol would carry is used instead,
/// so each case tests the rule and not the missing information.
@Suite
struct ObjCImporterNamingClassMemberTests {
    private static func spelling(of name: ObjCImporterNaming.ImportedName) -> String {
        let labels = name.argumentLabels.map { ($0.isEmpty ? "_" : $0) + ":" }.joined()
        return "\(name.baseName)(\(labels))"
    }

    private static func importedName(_ selector: String, _ encoding: String, in className: String, isClassMethod: Bool = false) throws -> ObjCImporterNaming.ImportedName {
        let methodType = try #require(ObjCTypeEncodingParser.methodType(from: encoding), "\(encoding)")
        return ObjCImporterNaming.importedName(
            selector: selector,
            isClassMethod: isClassMethod,
            methodType: methodType,
            contextTypeName: className,
            undoesSwiftInsertedWith: false,
            factoryInitializerClassName: className
        )
    }

    // MARK: - Factory methods

    @Test func aClassMethodRestatingItsClassNameIsAnInitializer() throws {
        let color = try Self.importedName("colorWithRed:green:blue:alpha:", "@48@0:8d16d24d32d40", in: "NSColor", isClassMethod: true)
        #expect(color.kind == .factoryInitializer)
        #expect(Self.spelling(of: color) == "init(red:green:blue:alpha:)")

        let image = try Self.importedName("imageNamed:", "@24@0:8@16", in: "NSImage", isClassMethod: true)
        #expect(image.kind == .factoryInitializer)
        #expect(Self.spelling(of: image) == "init(named:)")

        let font = try Self.importedName("fontWithName:size:", "@32@0:8@16d24", in: "NSFont", isClassMethod: true)
        #expect(Self.spelling(of: font) == "init(name:size:)")

        // With no argument, the first piece has to restate the name whole.
        let date = try Self.importedName("date", "@16@0:8", in: "NSDate", isClassMethod: true)
        #expect(date.kind == .factoryInitializer)
        #expect(Self.spelling(of: date) == "init()")
    }

    @Test func aClassMethodThatIsNoFactoryStaysAMethod() throws {
        // The first piece does not restate the class name.
        let event = try Self.importedName("mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:", "@92@0:8Q16{CGPoint=dd}24Q40d48q56@64q72q80f88", in: "NSEvent", isClassMethod: true)
        #expect(event.kind == .method)
        // It does, but leaves words behind with no argument to label.
        #expect(try Self.importedName("colorSpaceName", "@16@0:8", in: "NSColor", isClassMethod: true).kind == .method)
        // It returns another class.
        #expect(try Self.importedName("colorWithName:", #"@"NSString"24@0:8@16"#, in: "NSColor", isClassMethod: true).kind == .method)
        // It returns no object.
        #expect(try Self.importedName("colorCount", "q16@0:8", in: "NSColor", isClassMethod: true).kind == .method)
        // An instance method never is one.
        #expect(try Self.importedName("colorWithAlphaComponent:", "@24@0:8d16", in: "NSColor").kind == .method)
        // Nor is a class method the caller asked about for no class.
        let methodType = try #require(ObjCTypeEncodingParser.methodType(from: "@48@0:8d16d24d32d40"))
        let withoutClass = ObjCImporterNaming.importedName(selector: "colorWithRed:green:blue:alpha:", isClassMethod: true, methodType: methodType, contextTypeName: "NSColor", undoesSwiftInsertedWith: false)
        #expect(withoutClass.kind == .method)
    }

    // MARK: - The error convention

    @Test func onlyAParameterNamedForTheErrorFollowsTheErrorConvention() throws {
        // `NSDictionary **` encodes as `^@` like `NSError **` does.
        let rtf = try Self.importedName("initWithRTF:documentAttributes:", "@32@0:8@16^@24", in: "NSAttributedString")
        #expect(rtf.errorConvention == nil)
        #expect(Self.spelling(of: rtf) == "init(rtf:documentAttributes:)")

        let write = try Self.importedName("writeToURL:options:error:", #"B40@0:8@"NSURL"16Q24^@32"#, in: "NSData")
        #expect(write.errorConvention == .booleanResult)
        #expect(Self.spelling(of: write) == "write(to:options:)")

        let read = try Self.importedName("checkResourceIsReachableAndReturnError:", "B24@0:8^@16", in: "NSURL")
        #expect(read.errorConvention == .booleanResult)
        #expect(Self.spelling(of: read) == "checkResourceIsReachable()")
    }

    // MARK: - Property names

    @Test(arguments: [
        // A `BOOL` goes by its getter.
        ("NSView", "hidden", "TB,N,GisHidden", "isHidden"),
        ("NSView", "flipped", "TB,R,N,GisFlipped", "isFlipped"),
        ("NSView", "wantsLayer", "TB,N", "wantsLayer"),
        // A leading initialism is lowercased.
        ("NSBezierPath", "CGPath", "T^{CGPath=},N", "cgPath"),
        ("NSBitmapImageRep", "TIFFRepresentation", #"T@"NSData",R,C"#, "tiffRepresentation"),
        ("NSCursor", "IBeamCursorForVerticalLayout", #"T@"NSCursor",R"#, "iBeamCursorForVerticalLayout"),
        // A result of the context's own type drops its name.
        ("NSColor", "blackColor", #"T@"NSColor",R"#, "black"),
        ("NSAppearance", "currentAppearance", #"T@"NSAppearance",&,N"#, "current"),
        // A result of another type keeps it.
        ("NSWindow", "backgroundColor", #"T@"NSColor",C,N"#, "backgroundColor"),
    ])
    func propertyNamesMatchTheSDK(className: String, propertyName: String, attributes: String, swiftName: String) {
        #expect(ObjCImporterNaming.importedPropertyName(propertyName, attributes: attributes, contextTypeName: className) == swiftName)
    }
}
