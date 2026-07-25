import Echo

/// One direct value fragment carried by a general-purpose or vector register.
///
/// `byteCount` records the occupied width independently of the register bank.
/// The current supported boundary uses at most one scalar word per fragment;
/// preserving the width here lets later ABI work reason about wider vector
/// lanes without changing argument-location bookkeeping.
package struct CallFrameValuePiece: Equatable, Sendable {
    package let register: DirectValueRegister
    package let valueOffset: Int
    package let byteCount: Int
}

package struct CallFrameArgumentShape: Sendable {
    package let pieces: [CallFrameValuePiece]

    package init(type: Any.Type, layout: ABIClass) {
        let valueByteCount = reflect(type).vwt.size
        pieces =
            switch layout {
                case .void:
                    []
                case .floatingPoint:
                    [
                        CallFrameValuePiece(
                            register: .fp,
                            valueOffset: 0,
                            byteCount: valueByteCount
                        )
                    ]
                case .integer(let words):
                    (0 ..< words).map { word in
                        let offset = word * MemoryLayout<UInt>.size
                        return CallFrameValuePiece(
                            register: .gp,
                            valueOffset: offset,
                            byteCount: min(
                                MemoryLayout<UInt>.size,
                                max(valueByteCount - offset, 0)
                            )
                        )
                    }
                case .aggregate(let parts):
                    parts.map {
                        CallFrameValuePiece(
                            register: $0.register,
                            valueOffset: $0.offset,
                            byteCount: $0.byteCount
                        )
                    }
                case .indirect:
                    [
                        CallFrameValuePiece(
                            register: .gp,
                            valueOffset: 0,
                            byteCount: MemoryLayout<UInt>.size
                        )
                    ]
            }
    }
}

package struct CallFrameArgumentLocation: Equatable, Sendable {
    package enum Storage: Equatable, Sendable {
        case generalPurposeRegister(Int)
        case vectorRegister(Int)
        case stack(byteOffset: Int)
    }

    package let storage: Storage
    package let valueOffset: Int
    package let byteCount: Int

    package init(storage: Storage, valueOffset: Int, byteCount: Int) {
        self.storage = storage
        self.valueOffset = valueOffset
        self.byteCount = byteCount
    }
}

/// Assigns argument fragments to the captured call frame without reading it.
///
/// General-purpose and vector registers advance independently. Once either
/// bank is exhausted, fragments from that bank share one declaration-order
/// stack cursor, matching the decoder's existing arm64/x86_64 behavior.
package struct CallFrameArgumentLocationPlan: Sendable {
    package let arguments: [[CallFrameArgumentLocation]]
    package let trailingGeneralPurpose: [CallFrameArgumentLocation]
    package let argumentStackByteCount: Int
    package let stackByteCount: Int

    package init(
        arguments: [CallFrameArgumentShape],
        initialGeneralPurposeOffset: Int = 0,
        trailingGeneralPurposeWordCount: Int = 0,
        architecture: RuntimeArchitecture = .current
    ) {
        var cursor = Cursor(
            generalPurpose: initialGeneralPurposeOffset,
            generalPurposeLimit: architecture.generalPurposeArgumentRegisterCount,
            vectorLimit: architecture.vectorArgumentRegisterCount
        )
        self.arguments = arguments.map { shape in
            shape.pieces.map { cursor.location(for: $0) }
        }
        argumentStackByteCount = cursor.stackByteCount
        trailingGeneralPurpose = (0 ..< trailingGeneralPurposeWordCount).map {
            _ in
            cursor.location(
                for: CallFrameValuePiece(
                    register: .gp,
                    valueOffset: 0,
                    byteCount: MemoryLayout<UInt>.size
                ))
        }
        stackByteCount = cursor.stackByteCount
    }

    private struct Cursor {
        var generalPurpose: Int
        var vector = 0
        var stackByteCount = 0
        let generalPurposeLimit: Int
        let vectorLimit: Int

        mutating func location(
            for piece: CallFrameValuePiece
        ) -> CallFrameArgumentLocation {
            let storage: CallFrameArgumentLocation.Storage
            switch piece.register {
                case .gp where generalPurpose < generalPurposeLimit:
                    storage = .generalPurposeRegister(generalPurpose)
                    generalPurpose += 1
                case .fp where vector < vectorLimit:
                    storage = .vectorRegister(vector)
                    vector += 1
                case .gp:
                    storage = .stack(byteOffset: stackByteCount)
                    stackByteCount += stackSlotByteCount(for: piece)
                    generalPurpose += 1
                case .fp:
                    storage = .stack(byteOffset: stackByteCount)
                    stackByteCount += stackSlotByteCount(for: piece)
                    vector += 1
            }
            return CallFrameArgumentLocation(
                storage: storage,
                valueOffset: piece.valueOffset,
                byteCount: piece.byteCount
            )
        }

        private func stackSlotByteCount(
            for piece: CallFrameValuePiece
        ) -> Int {
            let wordSize = MemoryLayout<UInt>.size
            return max(
                wordSize,
                (piece.byteCount + wordSize - 1) / wordSize * wordSize
            )
        }
    }
}
