#if RUNTIME_STUB
/// Describes a protocol requirement for thunk matching (full descriptor with name).
public struct MethodDescriptor: Sendable {
    public let name: String
    public let signature: MethodSignature
    public let index: Int
    public let qualifiedArgs: [String]
    public let qualifiedRet: String
    public let isThrowing: Bool
    public let isAsync: Bool
    let argumentTypes: [Any.Type]?
    let returnType: Any.Type?

    public init(
        name: String,
        signature: MethodSignature,
        index: Int,
        qualifiedArgs: [String]? = nil,
        qualifiedRet: String? = nil,
        isThrowing: Bool = false,
        isAsync: Bool = false
    ) {
        self.init(
            name: name,
            signature: signature,
            index: index,
            qualifiedArgs: qualifiedArgs,
            qualifiedRet: qualifiedRet,
            isThrowing: isThrowing,
            isAsync: isAsync,
            argumentTypes: nil,
            returnType: nil
        )
    }

    init(
        name: String,
        signature: MethodSignature,
        index: Int,
        qualifiedArgs: [String]? = nil,
        qualifiedRet: String? = nil,
        isThrowing: Bool = false,
        isAsync: Bool = false,
        argumentTypes: [Any.Type]?,
        returnType: Any.Type?
    ) {
        self.name = name
        self.signature = signature
        self.index = index
        self.qualifiedArgs = qualifiedArgs ?? signature.args
        self.qualifiedRet = qualifiedRet ?? signature.ret
        self.isThrowing = isThrowing
        self.isAsync = isAsync
        self.argumentTypes = argumentTypes
        self.returnType = returnType
    }

    public static func getter(_ name: String, type: String, at index: Int) -> MethodDescriptor {
        MethodDescriptor(name: name, signature: .getter(type), index: index)
    }

    public static func method(_ name: String, args: [String], returns ret: String, at index: Int) -> MethodDescriptor {
        MethodDescriptor(name: name, signature: .init(args: args, ret: ret), index: index)
    }
}

/// Describes a protocol requirement slot by its signature.
/// Used in the simplified `RuntimeStub` init that doesn't require method names.
///
/// Three ways to create slots:
///
/// 1. **Type-safe method references** (recommended):
/// ```swift
/// let sut: any MyProto = RealImpl()
/// RuntimeStub<any MyProto>(
///     .from(sut.search),           // (String) -> [Int]
///     .from(sut.count),            // Int (getter)
///     .from(sut.load),             // (String) throws -> String
/// )
/// ```
///
/// 2. **Type-based** (explicit types):
/// ```swift
/// RuntimeStub<any MyProto>(
///     .method(String.self, returns: Int.self),
///     .getter(Int.self),
/// )
/// ```
///
/// 3. **Void shorthand**:
/// ```swift
/// .void                // no-arg void method/getter
/// .method(String.self) // void method with 1 arg
/// ```
public struct Slot {
    public let signature: MethodSignature
    let qualifiedArgs: [String]
    let qualifiedRet: String
    let isThrowing: Bool
    let isAsync: Bool
    let argumentTypes: [Any.Type]?
    let returnType: Any.Type?

    init(
        signature: MethodSignature,
        qualifiedArgs: [String]? = nil,
        qualifiedRet: String? = nil,
        isThrowing: Bool = false,
        isAsync: Bool = false,
        argumentTypes: [Any.Type]? = nil,
        returnType: Any.Type? = nil
    ) {
        self.signature = signature
        self.qualifiedArgs = qualifiedArgs ?? signature.args
        self.qualifiedRet = qualifiedRet ?? signature.ret
        self.isThrowing = isThrowing
        self.isAsync = isAsync
        self.argumentTypes = argumentTypes
        self.returnType = returnType
    }

    // MARK: - From method references (type-safe metadata names)

    /// Create a slot from a no-arg method reference.
    public static func from<R>(_ ref: () -> R) -> Slot {
        method(returns: R.self)
    }

    /// Create a slot from a no-arg throwing method reference.
    public static func from<R>(_ ref: () throws -> R) -> Slot {
        method(returns: R.self, throws: true)
    }

    /// Create a slot from a no-arg async method reference.
    public static func from<R>(_ ref: () async -> R) -> Slot {
        method(returns: R.self, async: true)
    }

    /// Create a slot from a no-arg async throwing method reference.
    public static func from<R>(_ ref: () async throws -> R) -> Slot {
        method(returns: R.self, throws: true, async: true)
    }

    /// Create a slot from a getter value (e.g. `sut.count` which is `Int`).
    public static func getter<R>(_ ref: R) -> Slot {
        method(returns: R.self)
    }

    /// Create a slot from a 1-arg method reference.
    public static func from<A, R>(_ ref: (A) -> R) -> Slot {
        method(args: [A.self], returns: R.self)
    }

    /// Create a slot from a 1-arg throwing method reference.
    public static func from<A, R>(_ ref: (A) throws -> R) -> Slot {
        method(args: [A.self], returns: R.self, throws: true)
    }

    /// Create a slot from a 1-arg async method reference.
    public static func from<A, R>(_ ref: (A) async -> R) -> Slot {
        method(args: [A.self], returns: R.self, async: true)
    }

    /// Create a slot from a 1-arg async throwing method reference.
    public static func from<A, R>(_ ref: (A) async throws -> R) -> Slot {
        method(args: [A.self], returns: R.self, throws: true, async: true)
    }

    /// Create a slot from a 2-arg method reference.
    public static func from<A, B, R>(_ ref: (A, B) -> R) -> Slot {
        method(args: [A.self, B.self], returns: R.self)
    }

    /// Create a slot from a 2-arg throwing method reference.
    public static func from<A, B, R>(_ ref: (A, B) throws -> R) -> Slot {
        method(args: [A.self, B.self], returns: R.self, throws: true)
    }

    /// Create a slot from a 2-arg async method reference.
    public static func from<A, B, R>(_ ref: (A, B) async -> R) -> Slot {
        method(args: [A.self, B.self], returns: R.self, async: true)
    }

    /// Create a slot from a 2-arg async throwing method reference.
    public static func from<A, B, R>(_ ref: (A, B) async throws -> R) -> Slot {
        method(args: [A.self, B.self], returns: R.self, throws: true, async: true)
    }

    /// Create a slot from a 3-arg method reference.
    public static func from<A, B, C, R>(_ ref: (A, B, C) -> R) -> Slot {
        method(args: [A.self, B.self, C.self], returns: R.self)
    }

    /// Create a slot from a 3-arg throwing method reference.
    public static func from<A, B, C, R>(_ ref: (A, B, C) throws -> R) -> Slot {
        method(args: [A.self, B.self, C.self], returns: R.self, throws: true)
    }

    /// Create a slot from a 3-arg async method reference.
    public static func from<A, B, C, R>(_ ref: (A, B, C) async -> R) -> Slot {
        method(args: [A.self, B.self, C.self], returns: R.self, async: true)
    }

    /// Create a slot from a 3-arg async throwing method reference.
    public static func from<A, B, C, R>(_ ref: (A, B, C) async throws -> R) -> Slot {
        method(args: [A.self, B.self, C.self], returns: R.self, throws: true, async: true)
    }

    /// Create a slot from a void method reference (1 arg).
    public static func from<A>(_ ref: (A) -> Void) -> Slot {
        method(args: [A.self], returns: Void.self)
    }

    /// Create a slot from a no-arg void method reference.
    public static func from(_ ref: () -> Void) -> Slot {
        method(returns: Void.self)
    }

    /// Create a slot from a no-arg async void method reference.
    public static func from(_ ref: () async -> Void) -> Slot {
        method(returns: Void.self, async: true)
    }

    /// Create a slot from a 1-arg async void method reference.
    public static func from<A>(_ ref: (A) async -> Void) -> Slot {
        method(args: [A.self], returns: Void.self, async: true)
    }

    // MARK: - Type-based (existing API, kept for compatibility)

    /// A property getter returning `T`.
    public static func getter(_ type: Any.Type) -> Slot {
        Slot(
            signature: .getter(runtimeTypeName(type)),
            argumentTypes: [],
            returnType: type
        )
    }

    /// A method with 1 argument.
    public static func method(_ a: Any.Type, returns: Any.Type, throws isThrowing: Bool = false, `async` isAsync: Bool = false) -> Slot {
        method(args: [a], returns: returns, throws: isThrowing, async: isAsync)
    }

    /// A method with 2 arguments.
    public static func method(_ a: Any.Type, _ b: Any.Type, returns: Any.Type, throws isThrowing: Bool = false, `async` isAsync: Bool = false) -> Slot {
        method(args: [a, b], returns: returns, throws: isThrowing, async: isAsync)
    }

    /// A method with 3 arguments.
    public static func method(_ a: Any.Type, _ b: Any.Type, _ c: Any.Type, returns: Any.Type, throws isThrowing: Bool = false, `async` isAsync: Bool = false) -> Slot {
        method(args: [a, b, c], returns: returns, throws: isThrowing, async: isAsync)
    }

    /// A method with arbitrary arity.
    public static func method(args: [Any.Type], returns: Any.Type, throws isThrowing: Bool = false, `async` isAsync: Bool = false) -> Slot {
        let argNames = args.map(runtimeTypeName)
        let retName = runtimeTypeName(returns)
        return Slot(
            signature: .init(args: argNames, ret: retName),
            qualifiedArgs: argNames,
            qualifiedRet: retName,
            isThrowing: isThrowing,
            isAsync: isAsync,
            argumentTypes: args,
            returnType: returns
        )
    }

    /// A void method with 1 argument.
    public static func method(_ a: Any.Type, throws isThrowing: Bool = false, `async` isAsync: Bool = false) -> Slot {
        method(args: [a], returns: Void.self, throws: isThrowing, async: isAsync)
    }

    /// A void method with 2 arguments.
    public static func method(_ a: Any.Type, _ b: Any.Type, throws isThrowing: Bool = false, `async` isAsync: Bool = false) -> Slot {
        method(args: [a, b], returns: Void.self, throws: isThrowing, async: isAsync)
    }

    /// A no-arg method with return value.
    public static func method(returns: Any.Type, throws isThrowing: Bool = false, `async` isAsync: Bool = false) -> Slot {
        method(args: [], returns: returns, throws: isThrowing, async: isAsync)
    }

    /// A no-arg void method.
    public static var void: Slot {
        Slot(signature: .getter("Swift.Void"), argumentTypes: [], returnType: Void.self)
    }
}

// MARK: - Type names

private func runtimeTypeName<T>(_ type: T.Type) -> String {
    runtimeTypeName(type as Any.Type)
}

private func runtimeTypeName(_ type: Any.Type) -> String {
    if type == Void.self { return "Swift.Void" }
    return String(reflecting: type)
}
#endif
