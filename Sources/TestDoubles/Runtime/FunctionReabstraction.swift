import CTestDoublesTrampoline
import Echo
import Foundation

/// Restores the concrete calling convention of function values that crossed
/// the recorder's generic `Any` boundary. Swift emits both directions of this
/// reabstraction pair in the client that performs the erased conversion, so no
/// protocol source annotation or generated forwarding body is required.
enum FunctionReabstraction {
    static func hasLinkedThunks(for type: Any.Type) -> Bool {
        guard let metadata = reflect(type) as? FunctionMetadata else {
            return false
        }
        return ReabstractionThunkRegistry.shared.hasBothDirections(for: metadata)
    }

    static func hasDirectToGenericBridge(_ metadata: FunctionMetadata) -> Bool {
        guard typedThrowingFunctionRuntimeUnsupportedReason(metadata) == nil else {
            return false
        }
        return canDynamicallyBoxFunctionArgument(metadata)
            || ReabstractionThunkRegistry.shared.directToGeneric(for: metadata) != nil
    }

    static func hasGenericToDirectBridge(_ metadata: FunctionMetadata) -> Bool {
        guard typedThrowingFunctionRuntimeUnsupportedReason(metadata) == nil else {
            return false
        }
        return canDynamicallyInitializeFunctionResult(metadata)
            || ReabstractionThunkRegistry.shared.genericToDirect(for: metadata) != nil
    }

    static func pointerAuthDiscriminators(
        for type: Any.Type
    ) -> (direct: UInt16, generic: UInt16)? {
        guard let function = reflect(type) as? FunctionMetadata,
            let direct = directFunctionDiscriminator(for: function)
        else { return nil }
        return (
            direct,
            td_generic_function_discriminator(
                UInt16(loweredParameterCount(function)),
                function.resultType != Void.self
            )
        )
    }

    static func automaticArgumentUnsupportedReason(for type: Any.Type) -> String? {
        guard let metadata = reflect(type) as? FunctionMetadata else { return nil }
        switch metadata.flags.convention {
            case .c, .block:
                return nil
            case .thin:
                return "Thin function values cannot be constructed reliably by this Swift toolchain."
            case .swift:
                break
        }
        if let reason = typedThrowingFunctionRuntimeUnsupportedReason(metadata) {
            return reason
        }
        guard directFunctionDiscriminator(for: metadata) != nil else {
            return "The closure's pointer-authentication type spelling cannot be reconstructed safely."
        }
        guard let reason = dynamicFunctionBridgeUnsupportedReason(metadata) else {
            return nil
        }
        guard ReabstractionThunkRegistry.shared.directToGeneric(for: metadata) == nil
        else {
            return nil
        }
        return "No matching compiler-emitted closure reabstraction thunk is linked. \(reason)"
    }

    static func automaticResultUnsupportedReason(for type: Any.Type) -> String? {
        guard let metadata = reflect(type) as? FunctionMetadata else { return nil }
        switch metadata.flags.convention {
            case .c, .block:
                return nil
            case .thin:
                return "Thin function values cannot be constructed reliably by this Swift toolchain."
            case .swift:
                break
        }
        if let reason = typedThrowingFunctionRuntimeUnsupportedReason(metadata) {
            return reason
        }
        guard directFunctionDiscriminator(for: metadata) != nil else {
            return "The closure's pointer-authentication type spelling cannot be reconstructed safely."
        }
        guard let reason = dynamicFunctionReturnBridgeUnsupportedReason(metadata)
        else {
            return nil
        }
        guard ReabstractionThunkRegistry.shared.genericToDirect(for: metadata) == nil
        else {
            return nil
        }
        return "No matching compiler-emitted generic-to-direct closure reabstraction thunk is linked. \(reason)"
    }

    static func boxDirectArgument(
        type: Any.Type,
        source: UnsafeMutableRawPointer
    ) -> Any {
        guard let function = reflect(type) as? FunctionMetadata else {
            preconditionFailure(
                "[TestDoubles] Expected function metadata for argument \(type)."
            )
        }
        switch function.flags.convention {
            case .c, .block:
                return boxValue(type: type, source: source)
            case .thin:
                preconditionFailure(
                    "[TestDoubles] Thin function arguments are not supported automatically."
                )
            case .swift:
                break
        }
        guard let code = source.load(as: UnsafeRawPointer?.self) else {
            preconditionFailure(
                "[TestDoubles] Function argument \(type) has no entry point."
            )
        }
        let context = (source + MemoryLayout<UInt>.size)
            .load(as: UnsafeRawPointer?.self)
        if canDynamicallyBoxFunctionArgument(function),
            let discriminator = directFunctionDiscriminator(for: function)
        {
            return dynamicallyBoxFunctionArgument(
                function: code,
                context: context,
                metadata: function,
                discriminator: discriminator
            )
        }
        guard
            let thunk = ReabstractionThunkRegistry.shared.directToGeneric(
                for: function
            )
        else {
            preconditionFailure(
                "[TestDoubles] No compiler-emitted reabstraction thunk is linked for function argument \(type)."
            )
        }
        let state = ReabstractionContext(
            function: code,
            context: context,
            isIsolatedAny: function.isIsolatedAny
        )
        state.validateStoredLayout()
        let discriminator = td_generic_function_discriminator(
            UInt16(loweredParameterCount(function)),
            function.resultType != Void.self
        )
        let signedThunk = td_sign_function_pointer(thunk, discriminator) ?? thunk
        func boxOpened<T>(_ type: T.Type) -> Any {
            let storage = UnsafeMutablePointer<T>.allocate(capacity: 1)
            defer { storage.deallocate() }
            let raw = UnsafeMutableRawPointer(storage)
            raw.storeBytes(of: signedThunk, as: UnsafeRawPointer.self)
            (raw + MemoryLayout<UInt>.size).storeBytes(
                of: UnsafeRawPointer(Unmanaged.passRetained(state).toOpaque()),
                as: UnsafeRawPointer.self
            )
            return storage.move()
        }
        return _openExistential(type, do: boxOpened)
    }

    static func initializeGenericSource(
        _ source: UnsafeMutableRawPointer,
        type: Any.Type,
        at destination: UnsafeMutableRawPointer
    ) {
        guard let code = source.load(as: UnsafeRawPointer?.self) else {
            reflect(type).vwt.initializeWithCopy(destination, source)
            return
        }
        let context = (source + MemoryLayout<UInt>.size)
            .load(as: UnsafeRawPointer?.self)

        guard let function = reflect(type) as? FunctionMetadata,
            let discriminator = directFunctionDiscriminator(for: function)
        else {
            preconditionFailure(
                "[TestDoubles] No compiler-emitted generic-to-direct reabstraction thunk is linked for function result \(type)."
            )
        }
        if canDynamicallyInitializeFunctionResult(function) {
            initializeDynamicFunctionResult(
                source,
                metadata: function,
                discriminator: discriminator,
                at: destination
            )
            return
        }
        guard
            let thunk = ReabstractionThunkRegistry.shared.genericToDirect(
                for: function
            )
        else {
            preconditionFailure(
                "[TestDoubles] No compiler-emitted generic-to-direct reabstraction thunk is linked for function result \(type)."
            )
        }
        let state = ReabstractionContext(
            function: code,
            context: context,
            isIsolatedAny: function.isIsolatedAny
        )
        state.validateStoredLayout()
        let signedThunk = td_sign_function_pointer(thunk, discriminator) ?? thunk
        destination.storeBytes(of: signedThunk, as: UnsafeRawPointer.self)
        (destination + MemoryLayout<UInt>.size).storeBytes(
            of: UnsafeRawPointer(Unmanaged.passRetained(state).toOpaque()),
            as: UnsafeRawPointer.self
        )
    }
}

private final class ReabstractionThunkRegistry: @unchecked Sendable {
    static let shared = ReabstractionThunkRegistry()

    private let lock = NSLock()
    private var directToGenericThunks: [DirectToGenericThunk] = []
    private var genericToDirectThunks: [DirectToGenericThunk] = []
    private var directAddresses: Set<UInt> = []
    private var genericAddresses: Set<UInt> = []

    private init() {
        refresh()
    }

    private func refresh() {
        let collector = ReabstractionThunkCollector()
        td_visit_local_symbols(
            collectReabstractionThunk,
            Unmanaged.passUnretained(collector).toOpaque()
        )
        let direct = collector.thunksByDemangledName.flatMap { name, thunks in
            guard let pair = reabstractionPair(in: name), pair.sourceIsGeneric == false else {
                return [DirectToGenericThunk]()
            }
            return thunks.map {
                DirectToGenericThunk(
                    directSignature: pair.source,
                    genericSignature: pair.target,
                    thunk: $0
                )
            }
        }
        let generic = collector.thunksByDemangledName.flatMap { name, thunks in
            guard let pair = reabstractionPair(in: name), pair.sourceIsGeneric else {
                return [DirectToGenericThunk]()
            }
            return thunks.map {
                DirectToGenericThunk(
                    directSignature: pair.target,
                    genericSignature: pair.source,
                    thunk: $0
                )
            }
        }
        lock.lock()
        for thunk in direct {
            let address = UInt(bitPattern: thunk.thunk.address)
            if directAddresses.insert(address).inserted {
                directToGenericThunks.append(thunk)
            }
        }
        for thunk in generic {
            let address = UInt(bitPattern: thunk.thunk.address)
            if genericAddresses.insert(address).inserted {
                genericToDirectThunks.append(thunk)
            }
        }
        lock.unlock()
    }

    func directToGeneric(for metadata: FunctionMetadata) -> UnsafeRawPointer? {
        if let match = directToGenericSnapshot().first(where: {
            $0.thunk.isAsyncDescriptor == metadata.flags.isAsync
                && loweredSignature($0.directSignature, matches: metadata)
                && loweredGenericSignature(
                    $0.genericSignature,
                    matches: metadata
                )
        }) {
            return match.thunk.address
        }
        refresh()
        return directToGenericSnapshot().first {
            $0.thunk.isAsyncDescriptor == metadata.flags.isAsync
                && loweredSignature($0.directSignature, matches: metadata)
                && loweredGenericSignature($0.genericSignature, matches: metadata)
        }?.thunk.address
    }

    func hasBothDirections(for metadata: FunctionMetadata) -> Bool {
        directToGeneric(for: metadata) != nil && genericToDirect(for: metadata) != nil
    }

    func genericToDirect(for metadata: FunctionMetadata) -> UnsafeRawPointer? {
        if let match = genericToDirectSnapshot().first(where: {
            $0.thunk.isAsyncDescriptor == metadata.flags.isAsync
                && loweredSignature($0.directSignature, matches: metadata)
                && loweredGenericSignature(
                    $0.genericSignature,
                    matches: metadata
                )
        }) {
            return match.thunk.address
        }
        refresh()
        return genericToDirectSnapshot().first {
            $0.thunk.isAsyncDescriptor == metadata.flags.isAsync
                && loweredSignature($0.directSignature, matches: metadata)
                && loweredGenericSignature($0.genericSignature, matches: metadata)
        }?.thunk.address
    }

    private func directToGenericSnapshot() -> [DirectToGenericThunk] {
        lock.lock()
        defer { lock.unlock() }
        return directToGenericThunks
    }

    private func genericToDirectSnapshot() -> [DirectToGenericThunk] {
        lock.lock()
        defer { lock.unlock() }
        return genericToDirectThunks
    }
}

private struct ReabstractionThunk {
    let address: UnsafeRawPointer
    let isAsyncDescriptor: Bool
}

private struct DirectToGenericThunk {
    let directSignature: LoweredFunctionSyntax
    let genericSignature: LoweredFunctionSyntax
    let thunk: ReabstractionThunk
}

private final class ReabstractionThunkCollector {
    var thunksByDemangledName: [String: [ReabstractionThunk]] = [:]
}

private let collectReabstractionThunk: @convention(c) (UnsafePointer<CChar>?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Bool = {
    name, address, context in
    guard let name, let address, let context else { return true }
    let mangledName = String(cString: name)
    guard mangledName.hasSuffix("TQ0_") == false else { return true }
    let collector = Unmanaged<ReabstractionThunkCollector>
        .fromOpaque(context)
        .takeUnretainedValue()
    let demangled = normalizedThunkName(
        demangleReabstractionSymbol(mangledName)
    )
    collector.thunksByDemangledName[demangled, default: []].append(
        ReabstractionThunk(
            address: address,
            isAsyncDescriptor: mangledName.hasSuffix("Tu")
        )
    )
    return true
}

private struct ReabstractionPair {
    let sourceIsGeneric: Bool
    let source: LoweredFunctionSyntax
    let target: LoweredFunctionSyntax
}

private let reabstractionPrefix =
    "partial apply forwarder for reabstraction thunk helper from "

private func reabstractionPair(in demangled: String) -> ReabstractionPair? {
    guard demangled.hasPrefix(reabstractionPrefix) else { return nil }
    let body = demangled.dropFirst(reabstractionPrefix.count)
    guard let separator = body.range(of: " to ", options: .backwards) else { return nil }
    guard let source = LoweredFunctionSyntax(String(body[..<separator.lowerBound])),
        let target = LoweredFunctionSyntax(String(body[separator.upperBound...]))
    else {
        return nil
    }
    let sourceIsGeneric = source.isGeneric
    guard sourceIsGeneric != target.isGeneric else { return nil }
    return ReabstractionPair(
        sourceIsGeneric: sourceIsGeneric,
        source: source,
        target: target
    )
}

private func loweredSignature(
    _ parsed: LoweredFunctionSyntax,
    matches metadata: FunctionMetadata
) -> Bool {
    let parsedGlobalActor = parsed.globalActor.flatMap(resolveRuntimeType)
    guard parsed.isSendable == (metadata.flags.bits & 0x4000_0000 != 0),
        parsed.isEscaping == (metadata.flags.bits & 0x0400_0000 != 0),
        parsed.isIsolated == metadata.isIsolatedAny,
        parsed.globalActor == nil || parsedGlobalActor != nil,
        parsed.globalActor == nil
            || sameRuntimeType(parsedGlobalActor, metadata.globalActorType),
        parsed.isAsync == metadata.flags.isAsync,
        parsed.isThrowing == metadata.flags.throws,
        loweredThrownError(parsed.thrownError, matches: metadata),
        loweredType(parsed.result, matches: metadata.resultType)
    else {
        return false
    }
    return loweredParameters(parsed.parameters, match: metadata)
}

/// Generic reabstraction signatures can contain demangler-only `@substituted`
/// spellings that have no runtime type parser. Match their complete semantic
/// envelope after trying the stronger concrete parser, so a same-shaped
/// sync-to-async or throwing conversion thunk cannot be selected by accident.
private func loweredGenericSignature(
    _ parsed: LoweredFunctionSyntax,
    matches metadata: FunctionMetadata
) -> Bool {
    if loweredSignature(parsed, matches: metadata) { return true }
    let parsedGlobalActor = parsed.globalActor.flatMap(resolveRuntimeType)
    return parsed.isSendable
        == (metadata.flags.bits & 0x4000_0000 != 0)
        && parsed.isEscaping
            == (metadata.flags.bits & 0x0400_0000 != 0)
        && parsed.isIsolated == metadata.isIsolatedAny
        && (parsed.globalActor == nil || parsedGlobalActor != nil)
        && (parsed.globalActor == nil
            || sameRuntimeType(parsedGlobalActor, metadata.globalActorType))
        && parsed.isAsync == metadata.flags.isAsync
        && parsed.isThrowing == metadata.flags.throws
        && parsed.parameters.count == loweredParameterCount(metadata)
}

private func loweredParameterCount(_ metadata: FunctionMetadata) -> Int {
    metadata.flags.numParams + (metadata.isNonisolatedNonsending ? 1 : 0)
}

private func loweredParameters(
    _ parsed: [LoweredFunctionParameterSyntax],
    match metadata: FunctionMetadata
) -> Bool {
    var semanticParameters = parsed[...]
    if metadata.isNonisolatedNonsending {
        guard case .implicitActor? = semanticParameters.first?.type else {
            return false
        }
        semanticParameters = semanticParameters.dropFirst()
    }
    let runtimeParameterTypes = functionParameterTypes(metadata)
    guard semanticParameters.count == runtimeParameterTypes.count else {
        return false
    }
    return zip(semanticParameters, runtimeParameterTypes).enumerated().allSatisfy {
        index, pair in
        loweredType(
            pair.0.type,
            matches: loweredParameterType(
                metadata,
                type: runtimeParameterTypes[index],
                at: index
            )
        )
            && pair.0.ownership == parameterOwnership(metadata, at: index)
            && pair.0.isIsolated == parameterIsIsolated(metadata, at: index)
    }
}

private func loweredParameterType(
    _ metadata: FunctionMetadata,
    type: Any.Type,
    at index: Int
) -> Any.Type {
    guard metadata.flags.hasParamFlags,
        metadata.paramFlags[index].isVariadic
    else {
        return type
    }
    func arrayType<Element>(of type: Element.Type) -> Any.Type {
        [Element].self
    }
    return _openExistential(type, do: arrayType)
}

/// Echo's zero-parameter accessor uses an unsafe-uninitialized empty Array,
/// which writes shared empty-array bookkeeping and trips ThreadSanitizer when
/// nested `() -> T` metadata is inspected concurrently.
private func functionParameterTypes(_ metadata: FunctionMetadata) -> [Any.Type] {
    guard metadata.flags.numParams > 0 else { return [] }
    return metadata.paramTypes
}

private func parameterOwnership(
    _ metadata: FunctionMetadata,
    at index: Int
) -> UInt32 {
    guard metadata.flags.hasParamFlags else { return 0 }
    return UInt32(metadata.paramFlags[index].valueOwnership.rawValue)
}

private func parameterIsIsolated(
    _ metadata: FunctionMetadata,
    at index: Int
) -> Bool {
    guard metadata.flags.hasParamFlags else { return false }
    return metadata.paramFlags[index].bits & 0x400 != 0
}

private func sameRuntimeType(_ lhs: Any.Type?, _ rhs: Any.Type?) -> Bool {
    switch (lhs, rhs) {
        case (nil, nil): return true
        case (.some(let lhs), .some(let rhs)):
            return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
        default: return false
    }
}

private func loweredThrownError(
    _ parsed: LoweredTypeSyntax?,
    matches metadata: FunctionMetadata
) -> Bool {
    if let typed = metadata.typedThrownErrorType {
        guard let parsed else { return false }
        return loweredType(parsed, matches: typed)
    }
    guard metadata.flags.throws else { return parsed == nil }
    guard case .source(let syntax)? = parsed,
        let type = resolveRuntimeType(syntax)
    else {
        return false
    }
    return ObjectIdentifier(type) == ObjectIdentifier((any Error).self)
}

private func loweredType(
    _ parsed: LoweredTypeSyntax,
    matches runtimeType: Any.Type
) -> Bool {
    switch parsed {
        case .source(let syntax):
            guard let type = resolveRuntimeType(syntax) else { return false }
            return ObjectIdentifier(type) == ObjectIdentifier(runtimeType)
        case .function(let signature):
            guard let metadata = reflect(runtimeType) as? FunctionMetadata else {
                return false
            }
            return loweredSignature(signature, matches: metadata)
        case .implicitActor, .substituted:
            return false
    }
}

func directFunctionDiscriminator(
    for metadata: FunctionMetadata
) -> UInt16? {
    guard let spelling = pointerAuthFunctionSpelling(metadata) else {
        return nil
    }
    let bytes = Array(spelling.utf8)
    return bytes.withUnsafeBufferPointer {
        td_function_discriminator($0.baseAddress, $0.count)
    }
}

private func pointerAuthFunctionSpelling(
    _ metadata: FunctionMetadata
) -> String? {
    let runtimeParameterTypes = functionParameterTypes(metadata)
    let parameters = runtimeParameterTypes.indices.compactMap { index in
        if parameterOwnership(metadata, at: index) == 1 {
            return "-indirect"
        }
        return pointerAuthTypeSpelling(
            loweredParameterType(
                metadata,
                type: runtimeParameterTypes[index],
                at: index
            )
        )
    }
    guard parameters.count == runtimeParameterTypes.count else { return nil }
    var spelling = "function:\(loweredParameterCount(metadata)):"
    if metadata.isNonisolatedNonsending {
        spelling += "-:"
    }
    for parameter in parameters {
        spelling += "\(parameter):"
    }
    if metadata.resultType == Void.self {
        spelling += "0:"
    } else {
        guard let result = pointerAuthTypeSpelling(metadata.resultType) else {
            return nil
        }
        spelling += "1:\(result):"
    }
    return spelling
}

func pointerAuthTypeSpelling(_ type: Any.Type) -> String? {
    let metadata = reflect(type)
    switch metadata.kind {
        case .class, .foreignClass, .objcClassWrapper:
            return "-class"
        case .metatype, .existentialMetatype:
            return "-metatype"
        case .tuple:
            return "-"
        case .function:
            guard let function = metadata as? FunctionMetadata,
                let spelling = pointerAuthFunctionSpelling(function)
            else {
                return nil
            }
            return "(\(spelling))"
        case .struct:
            guard let nominal = metadata as? StructMetadata else { return nil }
            if nominal.descriptor.name == "Array" {
                return "$sSa"
            }
            if nominal.genericTypes.isEmpty {
                return _mangledTypeName(type).map { "$s\($0)" }
            }
            return pointerAuthNominalSpelling(
                descriptor: nominal.descriptor,
                boundType: type
            )
        case .enum:
            guard let nominal = metadata as? EnumMetadata else { return nil }
            if nominal.genericTypes.isEmpty {
                return _mangledTypeName(type).map { "$s\($0)" }
            }
            return pointerAuthNominalSpelling(
                descriptor: nominal.descriptor,
                boundType: type
            )
        case .optional:
            guard let optional = metadata as? EnumMetadata,
                let wrapped = optional.genericTypes.first,
                let wrappedSpelling = pointerAuthTypeSpelling(wrapped)
            else { return nil }
            switch reflect(wrapped).kind {
                case .class, .foreignClass, .objcClassWrapper,
                    .metatype, .existentialMetatype:
                    return wrappedSpelling
                default:
                    return "Optional<\(wrappedSpelling)>"
            }
        default:
            return nil
    }
}

private func pointerAuthNominalSpelling(
    descriptor: any TypeContextDescriptor,
    boundType: Any.Type
) -> String? {
    if let symbol = td_exact_symbol_name(descriptor.ptr) {
        var spelling = String(cString: symbol)
        if spelling.hasPrefix("_$s") {
            spelling.removeFirst()
        }
        if spelling.hasPrefix("$s"), spelling.hasSuffix("Mn") {
            return String(spelling.dropLast(2))
        }
    }

    // Public descriptors normally have an exact symbol. Preserve a bounded
    // fallback for stripped images: the bound-type mangling places `y` after
    // the nominal V/O/C marker and before its generic arguments.
    guard let mangled = _mangledTypeName(boundType) else { return nil }
    for marker in ["Vy", "Oy", "Cy"] {
        if let range = mangled.range(of: marker) {
            return "$s\(mangled[..<mangled.index(before: range.upperBound)])"
        }
    }
    return nil
}

extension FunctionMetadata.Flags {
    fileprivate var isAsync: Bool { bits & 0x2000_0000 != 0 }
}
