import CTestDoublesTrampoline
import Echo

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
    let runtimeParameterTypes = safeFunctionParameterTypes(metadata)
    let parameters = runtimeParameterTypes.indices.compactMap { index in
        if functionParameterOwnership(metadata, at: index) == 1 {
            return "-indirect"
        }
        return pointerAuthTypeSpelling(
            loweredFunctionParameterType(
                metadata,
                type: runtimeParameterTypes[index],
                at: index
            )
        )
    }
    guard parameters.count == runtimeParameterTypes.count else { return nil }
    var spelling = "function:\(functionLoweredParameterCount(metadata)):"
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
            else {
                return nil
            }
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
