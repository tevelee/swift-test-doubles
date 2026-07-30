#if TESTDOUBLES_STUBBABLE_MACROS
    import MacroTesting
    import Testing
    import TestDoublesStubbableMacros

    @Suite(
        .macros([
            StubbableMacro.self,
            StubbableClientMacro.self
        ]))
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
                    ┬─────
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

        @Test func generatesAClosureClientPreset() {
            assertMacro {
                """
                @StubbableClient
                struct StatusClient {
                    var status: @Sendable (Int) async throws -> String
                }
                """
            } expansion: {
                """
                struct StatusClient {
                    var status: @Sendable (Int) async throws -> String
                }

                enum StatusClientDoubles {
                    static let preset = ClientDoublePreset<StatusClient> { endpoints in
                        StatusClient(
                            _testDoubleEndpoints: endpoints
                        )
                    }
                }

                extension StatusClient {
                    fileprivate init(
                        _testDoubleEndpoints endpoints: ClientStubEndpoints<Self>
                    ) {
                        self.status = endpoints.asyncThrowingFunction(
                            "status",
                            forwarding: { live, argument0 in
                                try await live.status(argument0)
                            }
                        )
                    }
                }
                """
            }
        }

        @Test func generatesAConfiguredGenericClosureClientPreset() {
            assertMacro {
                """
                @StubbableClient
                struct CacheClient<Value: Sendable> where Value: Equatable {
                    enum Failure: Error {
                        case unavailable
                    }

                    typealias Load =
                        @Sendable (String) async throws(Failure) -> Value

                    var namespace: String
                    var load: Load
                    let identity: @Sendable (Value) -> Value = { $0 }
                }
                """
            } expansion: {
                """
                struct CacheClient<Value: Sendable> where Value: Equatable {
                    enum Failure: Error {
                        case unavailable
                    }

                    typealias Load =
                        @Sendable (String) async throws(Failure) -> Value

                    var namespace: String
                    var load: Load
                    let identity: @Sendable (Value) -> Value = { $0 }
                }

                enum CacheClientDoubles<Value: Sendable> where Value: Equatable {
                    static func preset(
                        namespace: String
                    ) -> ClientDoublePreset<CacheClient<Value>> {
                        ClientDoublePreset<CacheClient<Value>> { endpoints in
                            CacheClient<Value>(
                                _testDoubleEndpoints: endpoints,
                                namespace: namespace
                            )
                        }
                    }
                }

                extension CacheClient {
                    fileprivate init(
                        _testDoubleEndpoints endpoints: ClientStubEndpoints<Self>,
                        namespace: String
                    ) {
                        self.namespace = namespace
                        self.load = endpoints.asyncThrowingFunction(
                            "load",
                            throwing: CacheClient<Value>.Failure.self,
                            forwarding: {
                                (
                                    live: CacheClient<Value>,
                                    argument0: String
                                ) async throws(CacheClient<Value>.Failure) -> Value in
                                    try await live.load(argument0)
                            }
                        )
                    }
                }
                """
            }
        }

        @Test func generatesExternalAliasWiringForACustomInitializer() {
            assertMacro {
                """
                @StubbableClient(aliasedEndpoints: "fetch", "transform")
                struct ExternalClient<Value> {
                    var namespace: String
                    var fetch: ExternalFetch
                    var transform: ExternalTransform<Value>

                    init(seed: Value) {
                        namespace = "live"
                        fetch = { _ in "live" }
                        transform = { $0 }
                    }
                }
                """
            } expansion: {
                """
                struct ExternalClient<Value> {
                    var namespace: String
                    var fetch: ExternalFetch
                    var transform: ExternalTransform<Value>

                    init(seed: Value) {
                        namespace = "live"
                        fetch = { _ in "live" }
                        transform = { $0 }
                    }
                }

                enum ExternalClientDoubles<Value> {
                    static func preset(
                        namespace: String
                    ) -> ClientDoublePreset<ExternalClient<Value>> {
                        ClientDoublePreset<ExternalClient<Value>> { endpoints in
                            ExternalClient<Value>(
                                _testDoubleEndpoints: endpoints,
                                namespace: namespace
                            )
                        }
                    }
                }

                extension ExternalClient {
                    fileprivate init(
                        _testDoubleEndpoints endpoints: ClientStubEndpoints<Self>,
                        namespace: String
                    ) {
                        self.namespace = namespace
                        self.fetch = endpoints.endpoint(
                            "fetch",
                            as: ExternalFetch.self,
                            forwarding: { $0.fetch }
                        )
                        self.transform = endpoints.endpoint(
                            "transform",
                            as: ExternalTransform<Value>.self,
                            forwarding: { $0.transform }
                        )
                    }
                }
                """
            }
        }

        @Test func rejectsUnknownAliasedEndpoints() {
            assertMacro {
                """
                @StubbableClient(aliasedEndpoints: "missing")
                struct AliasClient {
                    var fetch: @Sendable () -> String
                }
                """
            } diagnostics: {
                """
                @StubbableClient(aliasedEndpoints: "missing")
                struct AliasClient {
                       ┬──────────
                       ╰─ 🛑 @StubbableClient could not find a stored endpoint named 'missing'.
                    var fetch: @Sendable () -> String
                }
                """
            }
        }

        @Test func rejectsNonStructClientDeclarations() {
            assertMacro {
                """
                @StubbableClient
                protocol NotAClient {}
                """
            } diagnostics: {
                """
                @StubbableClient
                ╰─ 🛑 @StubbableClient can only be applied to a struct declaration.
                protocol NotAClient {}
                """
            }
        }
    }
#endif
