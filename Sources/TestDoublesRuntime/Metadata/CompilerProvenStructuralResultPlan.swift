import Echo
import InternalRuntimeContract

/// A compiler-proven decomposition of a tuple result whose members are
/// lowered independently by Swift's ABI.
package struct CompilerProvenStructuralResultPlan: @unchecked Sendable {
    package struct IndirectElement: @unchecked Sendable {
        package let type: Any.Type
        package let offset: Int
    }

    package let directLayout: ABIClass
    package let indirectElements: [IndirectElement]

    package var usesIndirectElementStorage: Bool {
        indirectElements.isEmpty == false
    }

    package init?(
        resultType: Any.Type,
        isThrowing: Bool,
        isAsync: Bool,
        evidenceCatalog: CompilerResultTransportEvidenceCatalog
    ) {
        guard reflect(resultType) is TupleMetadata else { return nil }

        var builder = Builder(
            isThrowing: isThrowing,
            isAsync: isAsync,
            evidenceCatalog: evidenceCatalog
        )
        guard builder.append(type: resultType, at: 0) else { return nil }

        let gpCount = builder.directParts.count { $0.register == .gp }
        let fpCount = builder.directParts.count { $0.register == .fp }
        // Prepared methods retain both coroutine offsets so a getter can be
        // reused by `_read` and `_modify`; reserve that bounded prefix even
        // for an ordinary method and fail construction instead of trapping.
        guard gpCount <= TrampolineABICapacity.directReturnRegisterCount,
            fpCount <= TrampolineABICapacity.directReturnRegisterCount,
            builder.indirectElements.count + 2
                <= RuntimeArchitecture.current.generalPurposeArgumentRegisterCount
        else {
            return nil
        }

        directLayout =
            builder.directParts.isEmpty
            ? .void
            : .aggregate(parts: builder.directParts)
        indirectElements = builder.indirectElements
    }

    package func indirectResultLocations(
        initialGeneralPurposeOffset: Int = 0
    ) -> [CallFrameArgumentLocation] {
        indirectElements.indices.map { index in
            CallFrameArgumentLocation(
                storage: .generalPurposeRegister(
                    initialGeneralPurposeOffset + index
                ),
                valueOffset: 0,
                byteCount: MemoryLayout<UInt>.size
            )
        }
    }

    private struct Builder {
        let isThrowing: Bool
        let isAsync: Bool
        let evidenceCatalog: CompilerResultTransportEvidenceCatalog
        var directParts: [DirectValuePart] = []
        var indirectElements: [IndirectElement] = []

        mutating func append(type: Any.Type, at baseOffset: Int) -> Bool {
            if let tuple = reflect(type) as? TupleMetadata {
                for element in tuple.elements {
                    guard
                        append(
                            type: element.type,
                            at: baseOffset + element.offset
                        )
                    else {
                        return false
                    }
                }
                return true
            }

            let layout: ABIClass
            if argumentABIClassCandidates(for: type).count > 1 {
                guard
                    let evidence = evidenceCatalog.evidence(
                        for: type,
                        isThrowing: isThrowing,
                        isAsync: isAsync
                    )
                else {
                    return false
                }
                switch evidence.transport {
                    case .direct:
                        layout = abiClass(for: type)
                    case .indirect:
                        layout = .indirect
                }
            } else {
                layout = abiClass(for: type)
            }

            switch layout {
                case .void:
                    return true
                case .floatingPoint:
                    directParts.append(
                        DirectValuePart(
                            register: .fp,
                            offset: baseOffset,
                            byteCount: reflect(type).vwt.size
                        )
                    )
                case .integer(let words):
                    let size = reflect(type).vwt.size
                    let wordSize = MemoryLayout<UInt>.size
                    for word in 0 ..< words {
                        let offset = word * wordSize
                        directParts.append(
                            DirectValuePart(
                                register: .gp,
                                offset: baseOffset + offset,
                                byteCount: min(wordSize, size - offset)
                            )
                        )
                    }
                case .aggregate(let parts):
                    directParts.append(
                        contentsOf: parts.map {
                            DirectValuePart(
                                register: $0.register,
                                offset: baseOffset + $0.offset,
                                byteCount: $0.byteCount
                            )
                        }
                    )
                case .indirect:
                    indirectElements.append(
                        IndirectElement(type: type, offset: baseOffset)
                    )
            }
            return true
        }
    }
}
