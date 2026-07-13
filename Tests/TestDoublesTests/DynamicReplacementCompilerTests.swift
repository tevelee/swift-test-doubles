#if DYNAMIC_REPLACEMENT && os(macOS)
import Darwin
import Foundation
import Testing
@testable import TestDoubles

@Suite struct DynamicReplacementCompilerTests {
    @Test func loadedReplacementPatchesImplicitDynamicFunction() throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let moduleName = "DynamicSubject\(suffix)"
        let cSymbol = "td_dynamic_number_\(suffix)"
        let subject = try DynamicReplacementCompiler.compileDynamicModule(
            moduleName: moduleName,
            source: """
            public func dynamicNumber() -> Int32 { 1 }

            @_cdecl("\(cSymbol)")
            public func dynamicNumberBridge() -> Int32 {
                dynamicNumber()
            }
            """
        )

        guard let subjectHandle = dlopen(subject.libraryPath, RTLD_NOW | RTLD_GLOBAL),
              let symbol = dlsym(subjectHandle, cSymbol) else {
            Issue.record("Expected subject dylib to load and export \(cSymbol)")
            return
        }

        typealias DynamicNumber = @convention(c) () -> Int32
        let dynamicNumber = unsafeBitCast(symbol, to: DynamicNumber.self)
        #expect(dynamicNumber() == 1)

        try DynamicReplacementCompiler.loadReplacement(
            moduleName: "DynamicReplacement\(suffix)",
            source: """
            import \(moduleName)

            @_dynamicReplacement(for: dynamicNumber())
            public func replacement_dynamicNumber() -> Int32 {
                42
            }
            """,
            importPaths: [subject.directory],
            libraryPaths: [subject.directory],
            linkedLibraries: [moduleName]
        )

        #expect(dynamicNumber() == 42)
    }
}
#endif // DYNAMIC_REPLACEMENT && os(macOS)
