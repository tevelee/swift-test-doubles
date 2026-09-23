import Foundation
import Testing
import TestDoubles
@testable import ManualStubBuildPluginDependencyFixtures

private struct RenameFailure: Error, Equatable {}

/// The build plugin, attached to this test target, generates stubs for the
/// protocols its production dependency declares.
@Suite struct DependencyStubTests {
    @Test func internalProtocolsOfADependencyAreStubbed() async throws {
        let accounts = AccountServiceStub()
        await accounts.when { try await $0.tier(for: 7) }.thenReturn(.pro(seats: 3))
        accounts.when { try $0.rename(Match.any(), to: Match.equal("")) }
            .thenThrow(RenameFailure())

        let service: any AccountService = accounts()

        #expect(try await service.tier(for: 7) == .pro(seats: 3))
        #expect(throws: RenameFailure()) { try service.rename(7, to: "") }
    }

    @Test func publicProtocolsOfADependencyAreStubbed() {
        let clock = AccountClockStub()
        let now = Date(timeIntervalSinceReferenceDate: 42)
        clock.when { $0.now }.thenReturn(now)

        #expect(clock().now == now)
    }
}
