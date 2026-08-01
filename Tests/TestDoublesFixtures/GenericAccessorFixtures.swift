public protocol ExternalFirstGenericConstraint {}
public protocol ExternalSecondGenericConstraint {}

public enum ExternalNestedProtocolNamespace {
    public protocol Constraint {}
}

public enum ExternalNestedGenericNamespace {
    public struct Box<Value> {
        public let value: Value

        public init(value: Value) {
            self.value = value
        }
    }
}

public struct ExternalGenericParent<Outer> {
    public struct Payload {
        public let outer: Outer

        public init(outer: Outer) {
            self.outer = outer
        }
    }

    public struct Box<Inner> {
        public let outer: Outer
        public let inner: Inner

        public init(outer: Outer, inner: Inner) {
            self.outer = outer
            self.inner = inner
        }
    }
}

public struct ConstrainedGenericParent<Outer: ExternalFirstGenericConstraint> {
    public struct Payload {
        public let outer: Outer

        public init(outer: Outer) {
            self.outer = outer
        }
    }
}

extension String: ExternalFirstGenericConstraint {}
extension Bool: ExternalSecondGenericConstraint {}
extension Int: ExternalFirstGenericConstraint, ExternalSecondGenericConstraint {}

public struct ExternalSixParameterBox<
    First,
    Second,
    Third,
    Fourth,
    Fifth,
    Sixth
> {
    public let first: First

    public init(_ first: First) {
        self.first = first
    }
}

public struct ExternalMultiplyConstrainedBox<
    Value: ExternalFirstGenericConstraint & ExternalSecondGenericConstraint
> {
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }
}

public struct ExternalSeveralConstrainedArguments<
    First: ExternalFirstGenericConstraint,
    Second: ExternalSecondGenericConstraint,
    Third: ExternalFirstGenericConstraint & ExternalSecondGenericConstraint
> {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }
}
