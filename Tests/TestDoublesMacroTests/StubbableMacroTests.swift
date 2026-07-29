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

                struct StubbableMacroServiceStubConformer: StubbableMacroService, ManualStubConformer {
                    let stub: ManualStub<Self>

                    init(stub: ManualStub<Self>) {
                        self.stub = stub
                    }

                    func fetch(_ identifier: Int) -> String {
                        stub.call(identifier)
                    }

                    var displayName: String {
                        get {
                            stub.call()
                        }
                        set {
                            stub.call(newValue)
                        }
                    }
                }

                typealias StubbableMacroServiceStub = ManualStub<StubbableMacroServiceStubConformer>
                """
            }
        }

        @Test func rejectsStaticRequirementsAtTheirDeclaration() {
            assertMacro {
                """
                @Stubbable
                protocol SharedService {
                    static func shared() -> Int
                }
                """
            } diagnostics: {
                """
                @Stubbable
                protocol SharedService {
                    static func shared() -> Int
                    ┬───────────────────────────
                    ╰─ 🛑 cannot generate manual forwarding for `static func shared() -> Int`: static requirements need shared process state and are unsafe in parallel tests
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
