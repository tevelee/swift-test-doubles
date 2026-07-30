import TestDoublesFixtures
import Testing
@testable import TestDoubles

@Suite struct RealWorldServiceProtocolTests {
    @Test func repositoryShapesWorkTogetherEndToEnd() async throws {
        _ = RealExternalUserRepository()
        let id = ExternalUserID(rawValue: 42)
        let profile = ExternalUserProfile(
            id: id,
            name: "Taylor",
            age: 35,
            isActive: true
        )
        let stub = try Stub<any ExternalUserRepository>()
        stub.when { $0.cachedUserCount }.thenReturn(1)
        stub.when {
            $0.cachedUser(id: Match.any(using: id))
        }.thenReturn(profile)
        stub.when {
            try $0.remove(
                id: Match.any(using: id),
                force: Match.any()
            )
        }.thenReturn(true)
        await stub.when {
            try await $0.save(Match.any(using: profile))
        }.thenDoNothing()
        await stub.when {
            try await $0.search(
                query: Match.any(),
                page: Match.any(),
                pageSize: Match.any(),
                includeInactive: Match.any()
            )
        }.thenReturn([profile])

        let repository: any ExternalUserRepository = stub()

        #expect(repository.cachedUserCount == 1)
        #expect(repository.cachedUser(id: id) == profile)
        #expect(try repository.remove(id: id, force: true))
        try await repository.save(profile)
        #expect(
            try await repository.search(
                query: "tay",
                page: 1,
                pageSize: 20,
                includeInactive: false
            ) == [profile]
        )
        await stub.verify {
            try await $0.search(
                query: Match.any(),
                page: Match.equal(1),
                pageSize: Match.equal(20),
                includeInactive: Match.equal(false)
            )
        }
    }

    @Test func repositoryErrorsPreserveThrowingEffects() async throws {
        _ = RealExternalUserRepository()
        let id = ExternalUserID(rawValue: 42)
        let profile = ExternalUserProfile(
            id: id,
            name: "Taylor",
            age: 35,
            isActive: true
        )
        let stub = try Stub<any ExternalUserRepository>()
        stub.when { $0.cachedUserCount }.thenReturn(0)
        stub.when {
            $0.cachedUser(id: Match.any(using: id))
        }.thenReturn(nil)
        stub.when {
            try $0.remove(
                id: Match.any(using: id),
                force: Match.any()
            )
        }.thenThrow(ExternalRepositoryError.unavailable)
        await stub.when {
            try await $0.save(Match.any(using: profile))
        }.thenThrow(ExternalRepositoryError.unavailable)
        await stub.when {
            try await $0.search(
                query: Match.any(),
                page: Match.any(),
                pageSize: Match.any(),
                includeInactive: Match.any()
            )
        }.thenThrow(ExternalRepositoryError.unavailable)

        let repository: any ExternalUserRepository = stub()

        #expect(throws: ExternalRepositoryError.unavailable) {
            try repository.remove(id: id, force: false)
        }
        await #expect(throws: ExternalRepositoryError.unavailable) {
            try await repository.save(profile)
        }
        await #expect(throws: ExternalRepositoryError.unavailable) {
            try await repository.search(
                query: "tay",
                page: 1,
                pageSize: 20,
                includeInactive: false
            )
        }
    }
}
