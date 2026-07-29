#if TESTDOUBLES_STUBBABLE_MACROS
    import MacroTesting
    import Testing
    import TestDoublesStubbableMacros

    @Suite(.macros([StubbableMacro.self]))
    struct StubbableMacroTests {
        @Test func generatesAManualStubConformer() {
            assertMacro {
                """
                @Stubbable
                protocol StubbableMacroService {
                    func fetch(_ identifier: Int) -> String
                    var displayName: String { get set }
                }
                """
            } expansion: {
                """
                protocol StubbableMacroService {
                    func fetch(_ identifier: Int) -> String
                    var displayName: String { get set }
                }

                struct StubbableMacroServiceManualStub: StubbableMacroService, StubConformer {
                    let stub: ManualStub<Self>

                    init(stub: ManualStub<Self>) {
                        self.stub = stub
                    }

                    private static func manualStubArgumentType<Value>(of _: Value) -> Value.Type {
                        Value.self
                    }

                    func fetch(_ identifier: Int) -> String {
                        return stub.call(identifier, route: ManualRouteID(argumentTypes: Self.manualStubArgumentType(of: identifier)))
                    }

                    var displayName: String {
                        get {
                            return stub.call()
                        }
                        set {
                            stub.call(newValue, route: ManualRouteID(argumentTypes: Self.manualStubArgumentType(of: newValue)))
                        }
                    }
                }
                """
            }
        }

        @Test func rejectsNonProtocolDeclarations() {
            assertMacro {
                """
                @Stubbable
                struct NotAProtocol {}
                """
            } diagnostics: {
                """
                @Stubbable
                ╰─ 🛑 @Stubbable can only be applied to a protocol declaration.
                struct NotAProtocol {}
                """
            }
        }
    }
#endif
