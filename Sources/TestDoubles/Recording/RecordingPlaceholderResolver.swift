import Foundation
#if canImport(Combine)
    import Combine
#endif

/// Resolves valid temporary values for matcher and result recording.
enum RecordingPlaceholderResolver {
    /// Returns a registered, built-in, composite, or runtime-synthesized value.
    ///
    /// Structural synthesis falls back to dummy-grade values, such as the first
    /// constructible case of a payload-only enum or a fail-on-use function.
    /// Recording only passes a placeholder to the requirement being described
    /// and discards whatever the recording closure returns, so neither value
    /// is ever used as real input or output.
    static func make<Value>(_ type: Value.Type) -> Value? {
        RecordingPlaceholderResolution().make(type)
    }

    /// Returns a registered, built-in, or composite value for `type` without
    /// structural synthesis, for runtime recording to use at any depth.
    static func leafValue(for type: Any.Type) -> Any? {
        RecordingPlaceholderResolution().nestedLeafValue(type)
    }

    /// Returns a dummy-grade value, consulting registered and built-in
    /// placeholders for any type structural synthesis cannot initialize.
    static func makeDummy<Value>(_ type: Value.Type) -> Value? {
        RecordingPlaceholderResolution().makeDummy(type)
    }
}

/// Owns one recursive resolution attempt and prevents composite cycles.
private final class RecordingPlaceholderResolution {
    private var resolving: Set<ObjectIdentifier> = []

    /// Resolves one value while preserving placeholder precedence at every depth.
    func make<Value>(_ type: Value.Type) -> Value? {
        if let registered = Match.Placeholders.make(type) {
            return registered
        }

        let identifier = ObjectIdentifier(type)
        guard resolving.insert(identifier).inserted else { return nil }
        defer { resolving.remove(identifier) }

        if let leaf = leafValue(type) {
            return leaf
        }
        let leafValue: (Any.Type) -> Any? = { [unowned self] nested in
            self.nestedLeafValue(nested)
        }
        return RuntimeStubFactory.makeRecordingPlaceholder(for: type, leafValue: leafValue)
            ?? RuntimeStubFactory.makeDummyValue(for: type, leafValue: leafValue)
    }

    func makeDummy<Value>(_ type: Value.Type) -> Value? {
        RuntimeStubFactory.makeDummyValue(for: type) { [unowned self] nested in
            self.nestedLeafValue(nested)
        }
    }

    /// Returns a built-in or composite value without structural synthesis.
    private func leafValue<Value>(_ type: Value.Type) -> Value? {
        if let builtIn = BuiltInRecordingPlaceholders.make(type) {
            return builtIn
        }
        if let composite = type as? any CompositeRecordingPlaceholder.Type,
            let value = composite.make(using: self) as? Value
        {
            return value
        }
        return nil
    }

    /// Supplies a nested value that structural synthesis could not initialize.
    func nestedLeafValue(_ type: Any.Type) -> Any? {
        func open<Value>(_: Value.Type) -> Any? {
            if let registered = Match.Placeholders.make(Value.self) {
                return registered
            }
            let identifier = ObjectIdentifier(Value.self)
            guard resolving.insert(identifier).inserted else { return nil }
            defer { resolving.remove(identifier) }
            return leafValue(Value.self)
        }
        return _openExistential(type, do: open)
    }
}

/// Constructs a generic wrapper from recursively resolved payload values.
private protocol CompositeRecordingPlaceholder {
    static func make(using resolver: RecordingPlaceholderResolution) -> Any?
}

extension Optional: CompositeRecordingPlaceholder {
    fileprivate static func make(
        using resolver: RecordingPlaceholderResolution
    ) -> Any? {
        guard let wrapped = resolver.make(Wrapped.self) else { return nil }
        return Self.some(wrapped) as Any
    }
}

extension Result: CompositeRecordingPlaceholder {
    fileprivate static func make(
        using resolver: RecordingPlaceholderResolution
    ) -> Any? {
        if let success = resolver.make(Success.self) {
            return Self.success(success) as Any
        }
        if let failure = resolver.make(Failure.self) {
            return Self.failure(failure) as Any
        }
        return nil
    }
}

extension ArraySlice: CompositeRecordingPlaceholder {
    fileprivate static func make(
        using _: RecordingPlaceholderResolution
    ) -> Any? {
        Self() as Any
    }
}

extension ContiguousArray: CompositeRecordingPlaceholder {
    fileprivate static func make(
        using _: RecordingPlaceholderResolution
    ) -> Any? {
        Self() as Any
    }
}

extension AnySequence: CompositeRecordingPlaceholder {
    fileprivate static func make(
        using _: RecordingPlaceholderResolution
    ) -> Any? {
        Self(EmptyCollection<Element>()) as Any
    }
}

extension AnyIterator: CompositeRecordingPlaceholder {
    fileprivate static func make(
        using _: RecordingPlaceholderResolution
    ) -> Any? {
        Self { nil } as Any
    }
}

extension AnyCollection: CompositeRecordingPlaceholder {
    fileprivate static func make(
        using _: RecordingPlaceholderResolution
    ) -> Any? {
        Self(EmptyCollection<Element>()) as Any
    }
}

extension AnyBidirectionalCollection: CompositeRecordingPlaceholder {
    fileprivate static func make(
        using _: RecordingPlaceholderResolution
    ) -> Any? {
        Self(EmptyCollection<Element>()) as Any
    }
}

extension AnyRandomAccessCollection: CompositeRecordingPlaceholder {
    fileprivate static func make(
        using _: RecordingPlaceholderResolution
    ) -> Any? {
        Self(EmptyCollection<Element>()) as Any
    }
}

extension AsyncStream: CompositeRecordingPlaceholder {
    fileprivate static func make(
        using _: RecordingPlaceholderResolution
    ) -> Any? {
        Self { $0.finish() } as Any
    }
}

extension AsyncThrowingStream: CompositeRecordingPlaceholder where Failure == any Error {
    fileprivate static func make(
        using _: RecordingPlaceholderResolution
    ) -> Any? {
        Self { $0.finish() } as Any
    }
}

extension Measurement: CompositeRecordingPlaceholder {
    fileprivate static func make(
        using resolver: RecordingPlaceholderResolution
    ) -> Any? {
        guard let unit = resolver.make(UnitType.self) else { return nil }
        return Self(value: 0, unit: unit) as Any
    }
}

#if canImport(Combine)
    extension AnyPublisher: CompositeRecordingPlaceholder {
        fileprivate static func make(
            using _: RecordingPlaceholderResolution
        ) -> Any? {
            Empty<Output, Failure>().eraseToAnyPublisher() as Any
        }
    }

    extension AnySubscriber: CompositeRecordingPlaceholder {
        fileprivate static func make(
            using _: RecordingPlaceholderResolution
        ) -> Any? {
            Self(
                receiveSubscription: { _ in },
                receiveValue: { _ in .none },
                receiveCompletion: { _ in }
            ) as Any
        }
    }

    extension PassthroughSubject: CompositeRecordingPlaceholder {
        fileprivate static func make(
            using _: RecordingPlaceholderResolution
        ) -> Any? {
            Self() as Any
        }
    }

    extension CurrentValueSubject: CompositeRecordingPlaceholder {
        fileprivate static func make(
            using resolver: RecordingPlaceholderResolution
        ) -> Any? {
            guard let output = resolver.make(Output.self) else { return nil }
            return Self(output) as Any
        }
    }
#endif
