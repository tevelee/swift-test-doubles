import CTestDoublesTrampoline
import Echo
import EchoRuntimeReflection
import TestDoublesRuntimeMetadata

package func directFunctionDiscriminator(
    for function: FunctionTypeInfo
) -> UInt16? {
    guard let spelling = pointerAuthFunctionSpelling(function) else {
        return nil
    }
    let bytes = Array(spelling.utf8)
    return bytes.withUnsafeBufferPointer {
        td_function_discriminator($0.baseAddress, $0.count)
    }
}

private func pointerAuthFunctionSpelling(
    _ function: FunctionTypeInfo
) -> String? {
    let parameters = function.parameters.compactMap { parameter in
        if parameter.rawOwnership == 1 {
            return "-indirect"
        }
        return pointerAuthTypeSpelling(
            loweredFunctionParameterType(parameter)
        )
    }
    guard parameters.count == function.parameters.count else { return nil }
    var spelling = "function:\(function.parameters.count):"
    if function.effects.isNonisolatedNonsending {
        spelling += "-:"
    }
    for parameter in parameters {
        spelling += "\(parameter):"
    }
    if function.resultType == Void.self {
        spelling += "0:"
    } else {
        guard let result = pointerAuthTypeSpelling(function.resultType) else {
            return nil
        }
        spelling += "1:\(result):"
    }
    return spelling
}

private func loweredFunctionParameterType(
    _ parameter: FunctionTypeInfo.Parameter
) -> Any.Type {
    guard parameter.isVariadic else { return parameter.type }
    func arrayType<Element>(of type: Element.Type) -> Any.Type {
        [Element].self
    }
    return _openExistential(parameter.type, do: arrayType)
}

package func pointerAuthTypeSpelling(_ type: Any.Type) -> String? {
    let metadata = reflect(type)
    switch metadata.kind {
        case .class, .foreignClass, .objcClassWrapper:
            return "-class"
        case .metatype, .existentialMetatype:
            return "-metatype"
        case .tuple:
            return "-"
        case .function:
            guard let function = FunctionTypeInfo(reflecting: type),
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
