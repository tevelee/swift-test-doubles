import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct TestDoublesPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        MockableMacro.self,
    ]
}
