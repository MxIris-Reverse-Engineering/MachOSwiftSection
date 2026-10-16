import Foundation
import Testing
@testable import CrossReferenceAnalysis

/// A binary built for macOS 11 or earlier binds through lazy pointers and a
/// `__stub_helper`. dyld still binds every such slot when it loads the image
/// — measured on macOS 27.2: with `RTLD_LAZY`, the slot already holds `puts`
/// before the function is first called — so the scanner reads the slot as it
/// stands. This test is the sentinel for that: if dyld ever left a slot
/// unbound, it would point at the image's own `__stub_helper`, the call would
/// resolve there, and the scanner would need to fall back to the stub's
/// imported name.
@Suite(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
struct LazyBindingTests {
    @Test func aLazilyBoundStubReachesItsTarget() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CrossReferenceAnalysisTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("LazyBinding.c")
        try "#include <stdio.h>\nvoid crossReferenceLazyBindingCall(void) { puts(\"called\"); }\n".write(to: source, atomically: true, encoding: .utf8)
        let library = directory.appendingPathComponent("libLazyBinding.dylib")

        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = [
            "clang", "-dynamiclib", "-arch", "arm64", "-O1",
            // Classic dyld info rather than chained fixups: lazy pointers and a __stub_helper.
            "-mmacosx-version-min=11.0", "-Wl,-no_fixup_chains",
            "-o", library.path, source.path,
        ]
        try compiler.run()
        compiler.waitUntilExit()
        try #require(compiler.terminationStatus == 0, "could not build the lazily bound fixture")
        _ = try #require(dlopen(library.path, RTLD_LAZY | RTLD_LOCAL))

        let analyzer = try #require(CrossReferenceAnalyzer())
        let image = try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix("/libLazyBinding.dylib") })
        let caller = try #require(analyzer.functions(inImageAt: image).first { $0.name == .symbol("_crossReferenceLazyBindingCall") })
        let call = try #require(analyzer.references(madeBy: caller).first)

        guard case .function(let location) = call.target else {
            Issue.record("the call through the lazy pointer resolved to \(call.target), not to a function")
            return
        }
        #expect(analyzer.imagePaths[location.imageIndex].hasSuffix("/libsystem_c.dylib"))
        let callee = try #require(analyzer.function(containing: location))
        #expect(callee.location == location)
        let names = (callee.name.map { [$0] } ?? []) + callee.foldedSymbolNames.map { .symbol($0) }
        #expect(names.contains(.symbol("_puts")), "callee named \(names)")
    }
}
