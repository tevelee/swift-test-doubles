import Echo

extension FunctionReabstraction {
    static func canInitializeDirectValue(of type: Any.Type) -> Bool {
        canReabstract(type, direction: .genericToDirect, visited: [])
    }

    static func canBoxDirectResult(of type: Any.Type) -> Bool {
        canReabstract(type, direction: .directToGeneric, visited: [])
    }

    static func boxDirectValue(
        type: Any.Type,
        source: UnsafeMutableRawPointer
    ) -> Any {
        if reflect(type) is FunctionMetadata {
            return boxDirectArgument(type: type, source: source)
        }
        guard requiresStructuralReabstraction(type) else {
            return boxValue(type: type, source: source)
        }

        let metadata = reflect(type)
        let temporary = metadata.allocateValueBuffer()
        initializeGenericValue(source, type: type, at: temporary)
        let value = boxValue(type: type, source: temporary)
        metadata.vwt.destroy(temporary)
        temporary.deallocate()
        return value
    }

    static func initializeDirectReturn(
        _ value: Any,
        expectedType: Any.Type,
        at destination: UnsafeMutableRawPointer
    ) -> Bool {
        let metadata = reflect(expectedType)
        let isNativeFunction =
            (metadata as? FunctionMetadata)?.flags.convention == .swift
        guard isNativeFunction || requiresStructuralReabstraction(expectedType) else {
            return false
        }

        var initialized = false
        func initializeOpened<T>(_ type: T.Type) {
            guard var typed = value as? T else { return }
            withUnsafeMutablePointer(to: &typed) { source in
                initializeDirectValue(
                    UnsafeMutableRawPointer(source),
                    type: expectedType,
                    at: destination
                )
            }
            initialized = true
        }
        _openExistential(expectedType, do: initializeOpened)
        return initialized
    }

    static func requiresStructuralReabstraction(_ type: Any.Type) -> Bool {
        requiresStructuralReabstraction(type, visited: [])
    }
}

extension FunctionReabstraction {
    fileprivate enum ReabstractionDirection {
        case directToGeneric
        case genericToDirect
    }

    fileprivate struct EnumPayload {
        let type: Any.Type
        let isIndirect: Bool
    }

    fileprivate static func requiresStructuralReabstraction(
        _ type: Any.Type,
        visited: Set<ObjectIdentifier>
    ) -> Bool {
        let metadata = reflect(type)
        if let function = metadata as? FunctionMetadata {
            return function.flags.convention == .swift
        }
        if let tuple = metadata as? TupleMetadata {
            return tuple.safelyInitializedElements.contains {
                requiresStructuralReabstraction($0.type, visited: visited)
            }
        }
        if metadata.kind == .optional,
            let optional = metadata as? EnumMetadata,
            let wrapped = optional.genericTypes.first
        {
            return requiresStructuralReabstraction(wrapped, visited: visited)
        }
        return false
    }

    fileprivate static func canReabstract(
        _ type: Any.Type,
        direction: ReabstractionDirection,
        visited: Set<ObjectIdentifier>
    ) -> Bool {
        let metadata = reflect(type)
        if let function = metadata as? FunctionMetadata {
            switch function.flags.convention {
                case .c, .block:
                    return true
                case .thin:
                    return false
                case .swift:
                    guard directFunctionDiscriminator(for: function) != nil else {
                        return false
                    }
                    switch direction {
                        case .directToGeneric:
                            return hasDirectToGenericBridge(function)
                        case .genericToDirect:
                            return hasGenericToDirectBridge(function)
                    }
            }
        }
        if let tuple = metadata as? TupleMetadata {
            return tuple.safelyInitializedElements.allSatisfy {
                canReabstract(
                    $0.type,
                    direction: direction,
                    visited: visited
                )
            }
        }
        if metadata.kind == .optional,
            let optional = metadata as? EnumMetadata,
            let wrapped = optional.genericTypes.first
        {
            return canReabstract(
                wrapped,
                direction: direction,
                visited: visited
            )
        }
        return true
    }

    fileprivate static func initializeDirectValue(
        _ source: UnsafeMutableRawPointer,
        type: Any.Type,
        at destination: UnsafeMutableRawPointer
    ) {
        initializeReabstractedValue(
            source,
            type: type,
            direction: .genericToDirect,
            at: destination
        )
    }

    fileprivate static func initializeGenericValue(
        _ source: UnsafeMutableRawPointer,
        type: Any.Type,
        at destination: UnsafeMutableRawPointer
    ) {
        initializeReabstractedValue(
            source,
            type: type,
            direction: .directToGeneric,
            at: destination
        )
    }

    fileprivate static func initializeReabstractedValue(
        _ source: UnsafeMutableRawPointer,
        type: Any.Type,
        direction: ReabstractionDirection,
        at destination: UnsafeMutableRawPointer
    ) {
        let metadata = reflect(type)
        if let function = metadata as? FunctionMetadata,
            function.flags.convention == .swift
        {
            switch direction {
                case .directToGeneric:
                    initializeBoxedDirectFunction(
                        source,
                        type: type,
                        at: destination
                    )
                case .genericToDirect:
                    initializeGenericSource(
                        source,
                        type: type,
                        at: destination
                    )
            }
            return
        }
        if let tuple = metadata as? TupleMetadata {
            zero(metadata, at: destination)
            for element in tuple.safelyInitializedElements {
                initializeReabstractedValue(
                    source + element.offset,
                    type: element.type,
                    direction: direction,
                    at: destination + element.offset
                )
            }
            return
        }
        if metadata.kind == .optional,
            let optional = metadata as? EnumMetadata,
            initializeEnum(
                source,
                metadata: optional,
                direction: direction,
                at: destination
            )
        {
            return
        }
        metadata.vwt.initializeWithCopy(destination, source)
    }

    fileprivate static func initializeBoxedDirectFunction(
        _ source: UnsafeMutableRawPointer,
        type: Any.Type,
        at destination: UnsafeMutableRawPointer
    ) {
        let value = boxDirectArgument(type: type, source: source)
        func initializeOpened<T>(_ type: T.Type) {
            guard var typed = value as? T else {
                preconditionFailure(
                    "[TestDoubles] Cannot open reabstracted function value as \(type)."
                )
            }
            withUnsafeMutablePointer(to: &typed) {
                reflect(type).vwt.initializeWithCopy(
                    destination,
                    UnsafeMutableRawPointer($0)
                )
            }
        }
        _openExistential(type, do: initializeOpened)
    }

    fileprivate static func initializeEnum(
        _ source: UnsafeMutableRawPointer,
        metadata: EnumMetadata,
        direction: ReabstractionDirection,
        at destination: UnsafeMutableRawPointer
    ) -> Bool {
        let tag = metadata.enumVwt.getEnumTag(for: source)
        guard tag < UInt32(metadata.descriptor.numPayloadCases),
            let payloads = enumPayloads(metadata),
            payloads.indices.contains(Int(tag))
        else {
            return false
        }
        let payload = payloads[Int(tag)]
        guard requiresStructuralReabstraction(payload.type) else {
            return false
        }
        guard payload.isIndirect == false else {
            preconditionFailure(
                "[TestDoubles] Indirect enum payloads containing function values require compiler reabstraction."
            )
        }

        zero(metadata, at: destination)
        withProjectedPayload(source, metadata: metadata) { projected in
            initializeReabstractedValue(
                projected,
                type: payload.type,
                direction: direction,
                at: destination
            )
        }
        metadata.enumVwt.destructiveInjectEnumTag(
            for: destination,
            tag: tag
        )
        return true
    }

    fileprivate static func enumPayloads(_ metadata: EnumMetadata) -> [EnumPayload]? {
        guard metadata.descriptor.isReflectable else { return nil }
        let count = metadata.descriptor.numPayloadCases
        let records = metadata.descriptor.fields.records
        guard records.count >= count else { return nil }
        var payloads: [EnumPayload] = []
        for record in records.prefix(count) {
            guard record.hasMangledTypeName,
                let type = metadata.type(of: record.mangledTypeName)
            else {
                return nil
            }
            payloads.append(
                EnumPayload(
                    type: type,
                    isIndirect: record.flags.isIndirectCase
                )
            )
        }
        return payloads
    }

    fileprivate static func withProjectedPayload(
        _ source: UnsafeMutableRawPointer,
        metadata: EnumMetadata,
        _ body: (UnsafeMutableRawPointer) -> Void
    ) {
        let scratch = metadata.allocateValueBuffer()
        scratch.copyMemory(
            from: source,
            byteCount: metadata.valueBufferByteCount()
        )
        metadata.enumVwt.destructiveProjectEnumData(for: scratch)
        body(scratch)
        // The scratch bytes alias the source's ownership. Projection does not
        // create an owned value, so deallocate without running its VWT.
        scratch.deallocate()
    }

    fileprivate static func zero(_ metadata: Metadata, at destination: UnsafeMutableRawPointer) {
        destination.initializeMemory(
            as: UInt8.self,
            repeating: 0,
            count: metadata.valueBufferByteCount()
        )
    }
}
