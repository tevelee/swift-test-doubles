/// Describes a protocol requirement for thunk matching (full descriptor with name).
public struct MethodDescriptor: Sendable {
    public let name: String
    public let signature: MethodSignature
    public let index: Int

    public init(name: String, signature: MethodSignature, index: Int) {
        self.name = name
        self.signature = signature
        self.index = index
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

    // MARK: - From method references (type-safe, MemoryLayout-based)

    /// Create a slot from a no-arg method reference.
    public static func from<R>(_ ref: () -> R) -> Slot {
        Slot(signature: .init(args: [], ret: abiFromSize(MemoryLayout<R>.size)))
    }

    /// Create a slot from a no-arg throwing method reference.
    public static func from<R>(_ ref: () throws -> R) -> Slot {
        Slot(signature: .init(args: [], ret: abiFromSize(MemoryLayout<R>.size)))
    }

    /// Create a slot from a getter value (e.g. `sut.count` which is `Int`).
    public static func getter<R>(_ ref: R) -> Slot {
        Slot(signature: .init(args: [], ret: abiFromSize(MemoryLayout<R>.size)))
    }

    /// Create a slot from a 1-arg method reference.
    public static func from<A, R>(_ ref: (A) -> R) -> Slot {
        Slot(signature: .init(
            args: [abiFromSize(MemoryLayout<A>.size)],
            ret: abiFromSize(MemoryLayout<R>.size)
        ))
    }

    /// Create a slot from a 1-arg throwing method reference.
    public static func from<A, R>(_ ref: (A) throws -> R) -> Slot {
        Slot(signature: .init(
            args: [abiFromSize(MemoryLayout<A>.size)],
            ret: abiFromSize(MemoryLayout<R>.size)
        ))
    }

    /// Create a slot from a 2-arg method reference.
    public static func from<A, B, R>(_ ref: (A, B) -> R) -> Slot {
        Slot(signature: .init(
            args: [abiFromSize(MemoryLayout<A>.size), abiFromSize(MemoryLayout<B>.size)],
            ret: abiFromSize(MemoryLayout<R>.size)
        ))
    }

    /// Create a slot from a 2-arg throwing method reference.
    public static func from<A, B, R>(_ ref: (A, B) throws -> R) -> Slot {
        Slot(signature: .init(
            args: [abiFromSize(MemoryLayout<A>.size), abiFromSize(MemoryLayout<B>.size)],
            ret: abiFromSize(MemoryLayout<R>.size)
        ))
    }

    /// Create a slot from a 3-arg method reference.
    public static func from<A, B, C, R>(_ ref: (A, B, C) -> R) -> Slot {
        Slot(signature: .init(
            args: [abiFromSize(MemoryLayout<A>.size), abiFromSize(MemoryLayout<B>.size), abiFromSize(MemoryLayout<C>.size)],
            ret: abiFromSize(MemoryLayout<R>.size)
        ))
    }

    /// Create a slot from a void method reference (1 arg).
    public static func from<A>(_ ref: (A) -> Void) -> Slot {
        Slot(signature: .init(args: [abiFromSize(MemoryLayout<A>.size)], ret: "V"))
    }

    /// Create a slot from a no-arg void method reference.
    public static func from(_ ref: () -> Void) -> Slot {
        Slot(signature: .init(args: [], ret: "V"))
    }

    // MARK: - Type-based (existing API, kept for compatibility)

    /// A property getter returning `T`.
    public static func getter(_ type: Any.Type) -> Slot {
        Slot(signature: .getter(abiFromType(type)))
    }

    /// A method with 1 argument.
    public static func method(_ a: Any.Type, returns: Any.Type) -> Slot {
        Slot(signature: .init(args: [abiFromType(a)], ret: abiFromType(returns)))
    }

    /// A method with 2 arguments.
    public static func method(_ a: Any.Type, _ b: Any.Type, returns: Any.Type) -> Slot {
        Slot(signature: .init(args: [abiFromType(a), abiFromType(b)], ret: abiFromType(returns)))
    }

    /// A method with 3 arguments.
    public static func method(_ a: Any.Type, _ b: Any.Type, _ c: Any.Type, returns: Any.Type) -> Slot {
        Slot(signature: .init(args: [abiFromType(a), abiFromType(b), abiFromType(c)], ret: abiFromType(returns)))
    }

    /// A void method with 1 argument.
    public static func method(_ a: Any.Type) -> Slot {
        Slot(signature: .init(args: [abiFromType(a)], ret: "V"))
    }

    /// A void method with 2 arguments.
    public static func method(_ a: Any.Type, _ b: Any.Type) -> Slot {
        Slot(signature: .init(args: [abiFromType(a), abiFromType(b)], ret: "V"))
    }

    /// A no-arg method with return value.
    public static func method(returns: Any.Type) -> Slot {
        Slot(signature: .init(args: [], ret: abiFromType(returns)))
    }

    /// A no-arg void method.
    public static var void: Slot {
        Slot(signature: .getter("V"))
    }
}

// MARK: - ABI Helpers

/// Compute ABI class from byte size.
private func abiFromSize(_ size: Int) -> String {
    switch size {
    case 0: return "V"
    case 1...8: return "W1"
    case 9...16: return "W2"
    default:
        preconditionFailure("[TestDoubles] Return type is \(size) bytes — the thunks backend only supports return types ≤ 16 bytes. Use .compiled strategy (macOS only) or provide explicit MethodDescriptors for this protocol.")
    }
}

/// Compute ABI class from a metatype.
private func abiFromType(_ type: Any.Type) -> String {
    if type == Void.self { return "V" }
    if type == String.self { return "W2" }
    // Use MemoryLayout for everything else
    // We can't call MemoryLayout<T>.size on Any.Type directly,
    // but all non-String, non-Void types that fit in 8 bytes are W1.
    return "W1"
}
