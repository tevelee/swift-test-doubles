import Foundation
#if canImport(Combine)
    import Combine
#endif

/// Resolves valid temporary values for matcher and result recording.
enum RecordingPlaceholderResolver {
    /// Returns a registered, built-in, composite, or runtime-synthesized value.
    static func make<Value>(_ type: Value.Type) -> Value? {
        RecordingPlaceholderResolution().make(type)
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

        if let builtIn = BuiltInRecordingPlaceholders.make(type) {
            return builtIn
        }
        if let composite = type as? any CompositeRecordingPlaceholder.Type,
            let value = composite.make(using: self) as? Value
        {
            return value
        }
        return RuntimeStubFactory.makeRecordingPlaceholder(for: type)
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
