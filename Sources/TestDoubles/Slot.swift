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
public struct Slot {
    public let signature: MethodSignature

    /// A property getter returning `T`.
    public static func getter(_ type: Any.Type) -> Slot {
        Slot(signature: .getter(typeName(type)))
    }

    /// A method with 1 argument.
    public static func method(_ a: Any.Type, returns: Any.Type) -> Slot {
        Slot(signature: .init(args: [typeName(a)], ret: typeName(returns)))
    }

    /// A method with 2 arguments.
    public static func method(_ a: Any.Type, _ b: Any.Type, returns: Any.Type) -> Slot {
        Slot(signature: .init(args: [typeName(a), typeName(b)], ret: typeName(returns)))
    }

    /// A method with 3 arguments.
    public static func method(_ a: Any.Type, _ b: Any.Type, _ c: Any.Type, returns: Any.Type) -> Slot {
        Slot(signature: .init(args: [typeName(a), typeName(b), typeName(c)], ret: typeName(returns)))
    }

    /// A void method with 1 argument.
    public static func method(_ a: Any.Type) -> Slot {
        Slot(signature: .init(args: [typeName(a)], ret: "Void"))
    }

    /// A void method with 2 arguments.
    public static func method(_ a: Any.Type, _ b: Any.Type) -> Slot {
        Slot(signature: .init(args: [typeName(a), typeName(b)], ret: "Void"))
    }

    /// A no-arg method with return value.
    public static func method(returns: Any.Type) -> Slot {
        Slot(signature: .init(args: [], ret: typeName(returns)))
    }

    /// A no-arg void method.
    public static var void: Slot {
        Slot(signature: .getter("Void"))
    }
}

func typeName(_ type: Any.Type) -> String {
    if type == Int.self { return "Int" }
    if type == String.self { return "String" }
    if type == Bool.self { return "Bool" }
    if type == Double.self { return "Double" }
    if type == Void.self { return "Void" }
    return String(describing: type)
}
