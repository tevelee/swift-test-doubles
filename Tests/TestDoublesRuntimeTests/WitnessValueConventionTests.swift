import Testing
@testable import TestDoublesRuntime

@Suite struct WitnessValueConventionTests {
    @Test func dynamicSelfClassificationCoversEverySupportedShape() {
        let dynamicSelfConventions: [WitnessValueConvention] = [
            .selfType,
            .optionalSelf,
            .nestedOptionalSelf,
            .arraySelf,
            .optionalArraySelf,
            .inoutSelf
        ]
        let independentConventions: [WitnessValueConvention] = [
            .concrete,
            .associatedType(name: "Value"),
            .methodGenericParameter(index: 0),
            .classMethodGenericParameter(index: 0),
            .optionalMethodGenericParameter(index: 0),
            .methodGenericParameterPack(index: 0)
        ]

        #expect(dynamicSelfConventions.allSatisfy { $0.containsDynamicSelf })
        #expect(independentConventions.allSatisfy { !$0.containsDynamicSelf })
    }
}
