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
import Testing
@testable import TestDoubles

struct CommonRecordingPlaceholderTests {
    @Test func standardLibraryLeavesAreValid() throws {
        let string = try #require(
            RecordingPlaceholderResolver.make(StaticString.self)
        )
        let hashable = try #require(
            RecordingPlaceholderResolver.make(AnyHashable.self)
        )
        let error = try #require(
            RecordingPlaceholderResolver.make((any Error).self)
        )

        #expect(string.description == "test-doubles-placeholder")
        #expect(hashable == AnyHashable(0))
        _ = error
    }

    @Test func emptyStandardLibraryWrappersNeedNoElementValue() throws {
        let slice = try #require(
            RecordingPlaceholderResolver.make(ArraySlice<Never>.self)
        )
        let contiguous = try #require(
            RecordingPlaceholderResolver.make(ContiguousArray<Never>.self)
        )
        let sequence = try #require(
            RecordingPlaceholderResolver.make(AnySequence<Never>.self)
        )
        let iterator = try #require(
            RecordingPlaceholderResolver.make(AnyIterator<Never>.self)
        )
        let collection = try #require(
            RecordingPlaceholderResolver.make(AnyCollection<Never>.self)
        )
        let bidirectional = try #require(
            RecordingPlaceholderResolver.make(
                AnyBidirectionalCollection<Never>.self
            )
        )
        let randomAccess = try #require(
            RecordingPlaceholderResolver.make(
                AnyRandomAccessCollection<Never>.self
            )
        )

        #expect(slice.isEmpty)
        #expect(contiguous.isEmpty)
        #expect(Array(sequence).isEmpty)
        #expect(iterator.next() == nil)
        #expect(collection.isEmpty)
        #expect(bidirectional.isEmpty)
        #expect(randomAccess.isEmpty)
    }

    @Test func commonFoundationValuesAreValid() throws {
        let name = try #require(
            RecordingPlaceholderResolver.make(Notification.Name.self)
        )
        let notification = try #require(
            RecordingPlaceholderResolver.make(Notification.self)
        )
        let attributed = try #require(
            RecordingPlaceholderResolver.make(AttributedString.self)
        )
        let person = try #require(
            RecordingPlaceholderResolver.make(PersonNameComponents.self)
        )

        #expect(name.rawValue == "TestDoubles.Placeholder")
        #expect(notification.name == name)
        #expect(String(attributed.characters) == "test-doubles-placeholder")
        #expect(person.givenName == "Test")
        #expect(person.familyName == "Doubles")
    }

    #if canImport(Darwin) || (canImport(FoundationNetworking) && !os(Android))
        @Test func urlRequestUsesTheBuiltInURL() throws {
            let request = try #require(
                RecordingPlaceholderResolver.make(URLRequest.self)
            )

            #expect(request.url?.path() == "/test-doubles-placeholder")
        }
    #endif

    @Test func measurementsRecursivelyResolveACommonUnit() throws {
        let measurement = try #require(
            RecordingPlaceholderResolver.make(
                Measurement<UnitLength>.self
            )
        )

        #expect(measurement.value == 0)
        #expect(measurement.unit == UnitLength.meters)

        try requireMeasurementUnit(UnitAcceleration.self)
        try requireMeasurementUnit(UnitAngle.self)
        try requireMeasurementUnit(UnitArea.self)
        try requireMeasurementUnit(UnitConcentrationMass.self)
        try requireMeasurementUnit(UnitDispersion.self)
        try requireMeasurementUnit(UnitDuration.self)
        try requireMeasurementUnit(UnitElectricCharge.self)
        try requireMeasurementUnit(UnitElectricCurrent.self)
        try requireMeasurementUnit(UnitElectricPotentialDifference.self)
        try requireMeasurementUnit(UnitElectricResistance.self)
        try requireMeasurementUnit(UnitEnergy.self)
        try requireMeasurementUnit(UnitFrequency.self)
        try requireMeasurementUnit(UnitFuelEfficiency.self)
        try requireMeasurementUnit(UnitIlluminance.self)
        try requireMeasurementUnit(UnitInformationStorage.self)
        try requireMeasurementUnit(UnitMass.self)
        try requireMeasurementUnit(UnitPower.self)
        try requireMeasurementUnit(UnitPressure.self)
        try requireMeasurementUnit(UnitSpeed.self)
        try requireMeasurementUnit(UnitTemperature.self)
        try requireMeasurementUnit(UnitVolume.self)
    }

    #if canImport(Dispatch)
        @Test func dispatchValuesUseSafeSharedPlaceholders() throws {
            let data = try #require(
                RecordingPlaceholderResolver.make(DispatchData.self)
            )
            let queue = try #require(
                RecordingPlaceholderResolver.make(DispatchQueue.self)
            )

            #expect(data.isEmpty)
            #expect(queue.label == DispatchQueue.main.label)
        }
    #endif

    #if canImport(Combine)
        @Test func combineTypeErasersAndSubjectsAreValid() throws {
            let subscription = try #require(
                RecordingPlaceholderResolver.make((any Subscription).self)
            )
            let publisher = try #require(
                RecordingPlaceholderResolver.make(
                    AnyPublisher<Int, Never>.self
                )
            )
            let subscriber = try #require(
                RecordingPlaceholderResolver.make(
                    AnySubscriber<Int, Never>.self
                )
            )
            let cancellable = try #require(
                RecordingPlaceholderResolver.make(AnyCancellable.self)
            )
            let passthrough = try #require(
                RecordingPlaceholderResolver.make(
                    PassthroughSubject<Int, Never>.self
                )
            )
            let current = try #require(
                RecordingPlaceholderResolver.make(
                    CurrentValueSubject<URL, Never>.self
                )
            )

            _ = subscription
            _ = publisher
            _ = subscriber
            _ = cancellable
            _ = passthrough
            #expect(current.value.path() == "/test-doubles-placeholder")
        }
    #endif
}

private func requireMeasurementUnit<UnitType: Dimension>(
    _ type: UnitType.Type
) throws {
    _ = try #require(
        RecordingPlaceholderResolver.make(Measurement<UnitType>.self),
        "Expected a placeholder for Measurement<\(type)>"
    )
}
