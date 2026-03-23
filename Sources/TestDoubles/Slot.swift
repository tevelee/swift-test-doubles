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
}

func typeName(_ type: Any.Type) -> String {
    if type == Int.self { return "Int" }
    if type == String.self { return "String" }
    if type == Bool.self { return "Bool" }
    if type == Double.self { return "Double" }
    if type == Void.self { return "Void" }
    return String(describing: type)
}
