import Testing
import TestDoubles
import TestDoublesFixtures

// MARK: - Production code under test
//
// Nothing below this line knows TestDoubles exists. Dependencies arrive as
// protocol values, get unboxed into `some` generics at call boundaries, and
// every requirement call goes through ordinary witness dispatch.
// Internal, not private: the conformers double as automatic-discovery
// fixtures, whose conformance records must stay reachable in release builds.

protocol PriceCatalog {
    func price(of sku: String) throws -> Int
    var currency: String { get }
}

struct RealPriceCatalog: PriceCatalog {
    func price(of sku: String) throws -> Int { 0 }
    var currency: String { "USD" }
}

extension PriceCatalog {
    /// A protocol-extension convenience that calls back into requirements.
    func formattedPrice(of sku: String) throws -> String {
        "\(try price(of: sku)) \(currency)"
    }
}

/// A free function generic over the catalog. Passing an `any PriceCatalog`
/// unboxes it into the `some` parameter at the call site.
private func subtotal(of skus: [String], using catalog: some PriceCatalog) throws -> Int {
    try skus.reduce(0) { total, sku in total + (try catalog.price(of: sku)) }
}

/// A component that stores its dependency as a generic, the way production
/// code avoids repeated existential unboxing. An `any` value must be unboxed
/// at a function boundary before this type can be built on it.
private struct Checkout<Catalog: PriceCatalog> {
    let catalog: Catalog

    func receipt(for skus: [String]) throws -> String {
        "\(try subtotal(of: skus, using: catalog)) \(catalog.currency)"
    }
}

/// The production entry point: unboxes whatever catalog it is handed and runs
/// the checkout flow on the opened type.
private func checkoutReceipt(
    for skus: [String],
    using catalog: some PriceCatalog
) throws -> String {
    try Checkout(catalog: catalog).receipt(for: skus)
}

/// An async component driven through a stored generic dependency.
private struct Headlines<Loader: AsyncDataLoader> {
    let loader: Loader

    func today() async throws -> [String] {
        try await loader.load(url: "https://news.example/today")
            .split(separator: "\n")
            .map(String.init)
    }
}

private func todaysHeadlines(using loader: some AsyncDataLoader) async throws -> [String] {
    try await Headlines(loader: loader).today()
}

// MARK: - Tests

@Suite struct ProductionUsageTests {
    private func makeCatalogStub() throws -> Stub<any PriceCatalog> {
        let stub = try Stub<any PriceCatalog>()
        stub.when { try $0.price(of: equal("apple")) }.thenReturn(3)
        stub.when { try $0.price(of: equal("pear")) }.thenReturn(4)
        stub.when { $0.currency }.thenReturn("EUR")
        return stub
    }

    @Test func genericFunctionsUnboxTheStubbedExistential() throws {
        let stub = try makeCatalogStub()
        let catalog: any PriceCatalog = stub()

        let total = try subtotal(of: ["apple", "pear", "apple"], using: catalog)

        #expect(total == 10)
        stub.verify(.exactly(3)) { try $0.price(of: any()) }
    }

    @Test func genericComponentsStoreAndDriveTheStubbedDependency() throws {
        let stub = try makeCatalogStub()
        let catalog: any PriceCatalog = stub()

        let receipt = try checkoutReceipt(for: ["apple", "pear"], using: catalog)

        #expect(receipt == "7 EUR")
        stub.verify(.exactly(1)) { try $0.price(of: equal("apple")) }
        stub.verify(.exactly(1)) { try $0.price(of: equal("pear")) }
        stub.verify(.exactly(1)) { $0.currency }
    }

    @Test func protocolExtensionMethodsDispatchBackThroughTheStub() throws {
        let stub = try makeCatalogStub()
        let catalog: any PriceCatalog = stub()

        #expect(try catalog.formattedPrice(of: "pear") == "4 EUR")
        stub.verifyInOrder {
            _ = try $0.price(of: equal("pear"))
            _ = $0.currency
        }
    }

    @Test func productionErrorsSurfaceUnchangedThroughGenericCallers() throws {
        struct DiscontinuedSKU: Error, Equatable { let sku: String }

        let stub = try Stub<any PriceCatalog>()
        stub.when { try $0.price(of: any()) }.then { (sku: String) throws -> Int in
            throw DiscontinuedSKU(sku: sku)
        }
        stub.when { $0.currency }.thenReturn("EUR")
        let catalog: any PriceCatalog = stub()

        let error = #expect(throws: DiscontinuedSKU.self) {
            _ = try checkoutReceipt(for: ["floppy-disk"], using: catalog)
        }
        #expect(error?.sku == "floppy-disk")
    }

    @Test func asyncComponentsConsumeTheStubThroughStoredGenerics() async throws {
        let stub = try Stub<any AsyncDataLoader>()
        await stub.when { try await $0.load(url: any()) }.thenReturn("first\nsecond")
        let loader: any AsyncDataLoader = stub()

        let headlines = try await todaysHeadlines(using: loader)

        #expect(headlines == ["first", "second"])
        await stub.verify(.exactly(1)) {
            try await $0.load(url: equal("https://news.example/today"))
        }
    }
}
