import Foundation
import Testing
import MachOKit
@_spi(Core) import MachOObjCSection
@testable import MachOTestingSupport

@Suite(.serialized, ExclusiveImageAccess(ObjCImplementationFixture.moduleName))
struct TemporaryCategoryDiagnosisTests {
    @Test func listTheFixtureCategories() throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        var lines: [String] = []
        lines.append("sections: \(machOFile.sections.map { "\($0.segmentName),\($0.sectionName)" }.filter { $0.contains("objc") })")
        let categories = machOFile.objc.categories64
        lines.append("categories64: \(categories.map { String($0.count) } ?? "nil")")
        for category in categories ?? [] {
            let resolvedClass: (MachOFile, ObjCClass64)? = category.class(in: machOFile)
            lines.append("name=\(category.name(in: machOFile) ?? "nil") className=\(category.className(in: machOFile) ?? "nil") class=\(resolvedClass.flatMap { $0.1.classROData(in: $0.0)?.name(in: $0.0) } ?? "nil") instanceMethods=\(category.instanceMethodList(in: machOFile)?.methods(in: machOFile)?.count ?? -1)")
        }
        for classObject in machOFile.objc.classes64 ?? [] {
            if let readOnlyData = classObject.classROData(in: machOFile) {
                lines.append("class \(readOnlyData.name(in: machOFile) ?? "nil"): \(readOnlyData.methodList(in: machOFile)?.methods(in: machOFile)?.map(\.name) ?? [])")
            }
        }
        Issue.record(Comment(rawValue: lines.joined(separator: "\n")))
    }
}
