import CTestDoublesTrampoline
import Echo

/// Owns the retain/release contract for Swift's heap-allocated error objects.
enum SwiftErrorTransport {
    static func encode(
        _ error: any Error,
        into frame: TrampolineCallFrame
    ) {
        frame.zeroReturn()
        frame.storeReturnError(retainedPointer(to: error))
    }

    static func take(_ address: UInt) -> any Error {
        guard let errorObject = UnsafeRawPointer(bitPattern: address) else {
            preconditionFailure(
                "[TestDoubles] Dynamic closure returned an invalid error."
            )
        }
        var scratch: UnsafeMutableRawPointer?
        var extracted = TDSwiftErrorValue(
            value: nil,
            type: nil,
            witnessTable: nil
        )
        td_swift_get_error_value(errorObject, &scratch, &extracted)
        defer { td_swift_error_release(errorObject) }
        guard let value = extracted.value, let type = extracted.type else {
            preconditionFailure(
                "[TestDoubles] Swift returned an empty error object."
            )
        }
        let runtimeType = unsafeBitCast(type, to: Any.Type.self)
        let boxed = boxValue(
            type: runtimeType,
            source: UnsafeMutableRawPointer(mutating: value)
        )
        guard let error = boxed as? any Error else {
            preconditionFailure(
                "[TestDoubles] Dynamic closure error \(runtimeType) does not conform to Error."
            )
        }
        return error
    }

    static func encodeTyped(
        _ error: Any,
        expectedType: Any.Type,
        layout: ABIClass,
        destination: UnsafeMutableRawPointer?,
        usesIndirectResultSlot: Bool,
        context: String,
        missingDestinationMessage: String,
        isAsync: Bool,
        into frame: TrampolineCallFrame
    ) {
        if usesIndirectResultSlot {
            frame.zeroReturn()
            guard let destination else {
                fatalError(missingDestinationMessage)
            }
            RuntimeValueTransport.initializeDirectValue(
                error,
                expectedType: expectedType,
                to: destination
            )
        } else {
            RuntimeValueTransport.encodeReturn(
                error,
                expectedType: expectedType,
                layout: layout,
                context: context,
                isAsync: isAsync,
                into: frame
            )
        }
        frame.storeReturnError(1)
    }

    private static func retainedPointer(to error: any Error) -> UInt {
        var container = Echo.container(for: error)
        let metadata = container.metadata
        guard
            let errorProtocol = (reflect((any Error).self) as? ExistentialMetadata)?
                .protocols.first,
            let witness = swift_conformsToProtocol(
                metadata: metadata,
                protocol: errorProtocol
            )
        else {
            fatalError(
                "[TestDoubles] Cannot find Error witness table for thrown value of type \(metadata.type)."
            )
        }
        let allocated = td_swift_alloc_error(
            metadata.ptr,
            witness.ptr,
            nil,
            false
        )
        metadata.vwt.initializeWithCopy(
            allocated.value,
            UnsafeMutableRawPointer(mutating: container.projectValue())
        )
        return UInt(bitPattern: allocated.error)
    }
}
