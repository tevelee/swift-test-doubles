import Foundation
#if canImport(FoundationNetworking) && !os(Android)
    import FoundationNetworking
#endif
#if canImport(Dispatch)
    import Dispatch
#endif
#if canImport(Combine)
    import Combine
#endif

/// Stable leaf values whose private storage reflection cannot initialize portably.
enum BuiltInRecordingPlaceholders {
    static func make<Value>(_ type: Value.Type) -> Value? {
        guard let value = value(for: type) else { return nil }
        return value as? Value
    }

    private static func value(for type: Any.Type) -> Any? {
        if ObjectIdentifier(type) == ObjectIdentifier((any Error).self) {
            return RecordingPlaceholderError()
        }
        if let value = standardLibraryValue(for: type) {
            return value
        }
        if let value = foundationValue(for: type) {
            return value
        }
        #if canImport(Dispatch)
            if let value = dispatchValue(for: type) {
                return value
            }
        #endif
        #if canImport(Combine)
            if let value = combineValue(for: type) {
                return value
            }
        #endif
        return nil
    }

    private static func standardLibraryValue(for type: Any.Type) -> Any? {
        return switch type {
            case is StaticString.Type:
                "test-doubles-placeholder" as StaticString
            case is AnyHashable.Type:
                AnyHashable(0)
            default:
                nil
        }
    }

    private static func foundationValue(for type: Any.Type) -> Any? {
        if let unit = measurementUnit(for: type) {
            return unit
        }
        return switch type {
            case is URL.Type:
                URL(filePath: "/test-doubles-placeholder")
            #if canImport(Darwin) || (canImport(FoundationNetworking) && !os(Android))
                case is URLRequest.Type:
                    URLRequest(url: URL(filePath: "/test-doubles-placeholder"))
            #endif
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
            case is Notification.Name.Type:
                Notification.Name("TestDoubles.Placeholder")
            case is Notification.Type:
                Notification(name: Notification.Name("TestDoubles.Placeholder"))
            case is AttributedString.Type:
                AttributedString("test-doubles-placeholder")
            case is PersonNameComponents.Type:
                personNameComponents()
            default:
                nil
        }
    }

    private static func measurementUnit(for type: Any.Type) -> Any? {
        switch type {
            case is UnitAcceleration.Type:
                UnitAcceleration.metersPerSecondSquared
            case is UnitAngle.Type:
                UnitAngle.degrees
            case is UnitArea.Type:
                UnitArea.squareMeters
            case is UnitConcentrationMass.Type:
                UnitConcentrationMass.gramsPerLiter
            case is UnitDispersion.Type:
                UnitDispersion.partsPerMillion
            case is UnitDuration.Type:
                UnitDuration.seconds
            case is UnitElectricCharge.Type:
                UnitElectricCharge.coulombs
            case is UnitElectricCurrent.Type:
                UnitElectricCurrent.amperes
            case is UnitElectricPotentialDifference.Type:
                UnitElectricPotentialDifference.volts
            case is UnitElectricResistance.Type:
                UnitElectricResistance.ohms
            case is UnitEnergy.Type:
                UnitEnergy.joules
            case is UnitFrequency.Type:
                UnitFrequency.hertz
            case is UnitFuelEfficiency.Type:
                UnitFuelEfficiency.litersPer100Kilometers
            case is UnitIlluminance.Type:
                UnitIlluminance.lux
            case is UnitInformationStorage.Type:
                UnitInformationStorage.bytes
            case is UnitLength.Type:
                UnitLength.meters
            case is UnitMass.Type:
                UnitMass.kilograms
            case is UnitPower.Type:
                UnitPower.watts
            case is UnitPressure.Type:
                UnitPressure.kilopascals
            case is UnitSpeed.Type:
                UnitSpeed.metersPerSecond
            case is UnitTemperature.Type:
                UnitTemperature.kelvin
            case is UnitVolume.Type:
                UnitVolume.liters
            default:
                nil
        }
    }

    private static func personNameComponents() -> PersonNameComponents {
        var components = PersonNameComponents()
        components.givenName = "Test"
        components.familyName = "Doubles"
        return components
    }

    #if canImport(Dispatch)
        private static func dispatchValue(for type: Any.Type) -> Any? {
            switch type {
                case is DispatchData.Type:
                    DispatchData.empty
                case is DispatchQueue.Type:
                    DispatchQueue.main
                default:
                    nil
            }
        }
    #endif

    #if canImport(Combine)
        private static func combineValue(for type: Any.Type) -> Any? {
            if ObjectIdentifier(type) == ObjectIdentifier((any Subscription).self) {
                return Subscriptions.empty
            }
            if type is AnyCancellable.Type {
                return AnyCancellable {}
            }
            return nil
        }
    #endif
}

/// A valid error value used only while a call-recording closure executes.
private struct RecordingPlaceholderError: Error {}
