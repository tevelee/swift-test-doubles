import Foundation

/// Stable temporary values for common Foundation types, including values whose
/// private storage reflection cannot initialize portably.
enum BuiltInRecordingPlaceholders {
    static func make<Value>(_ type: Value.Type) -> Value? {
        make(type as Any.Type) as? Value
    }

    private static func make(_ type: Any.Type) -> Any? {
        if let value = foundationValue(for: type) {
            return value
        }
        guard
            let optionalType = type as? any BuiltInOptionalPlaceholder.Type,
            let wrapped = make(optionalType.wrappedType)
        else {
            return nil
        }
        return optionalType.wrapping(wrapped)
    }

    private static func foundationValue(for type: Any.Type) -> Any? {
        switch type {
            case is URL.Type:
                URL(filePath: "/test-doubles-placeholder")
            case is Data.Type:
                Data([0x54, 0x44])
            case is Date.Type:
                Date(timeIntervalSinceReferenceDate: 1)
            case is UUID.Type:
                UUID(uuidString: "54455354-444F-5542-4C45-530000000001")
            case is Calendar.Type:
                Calendar(identifier: .gregorian)
            case is Locale.Type:
                Locale(identifier: "en_US_POSIX")
            case is TimeZone.Type:
                TimeZone(secondsFromGMT: 0)
            case is IndexPath.Type:
                IndexPath(index: 0)
            case is IndexSet.Type:
                IndexSet(integer: 0)
            case is DateInterval.Type:
                DateInterval(
                    start: Date(timeIntervalSinceReferenceDate: 1),
                    duration: 1
                )
            case is CharacterSet.Type:
                CharacterSet(charactersIn: "A")
            case is Decimal.Type:
                Decimal(1)
            default:
                nil
        }
    }
}

private protocol BuiltInOptionalPlaceholder {
    static var wrappedType: Any.Type { get }
    static func wrapping(_ value: Any) -> Any?
}

extension Optional: BuiltInOptionalPlaceholder {
    fileprivate static var wrappedType: Any.Type { Wrapped.self }

    fileprivate static func wrapping(_ value: Any) -> Any? {
        guard let value = value as? Wrapped else { return nil }
        return Self.some(value) as Any
    }
}
