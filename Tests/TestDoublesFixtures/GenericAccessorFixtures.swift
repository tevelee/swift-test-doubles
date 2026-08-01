public protocol ExternalFirstGenericConstraint {}
public protocol ExternalSecondGenericConstraint {}

public enum ExternalNestedProtocolNamespace {
    public protocol Constraint {}
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
