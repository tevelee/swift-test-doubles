import Testing
@testable import TestDoubles

@Suite struct UseCaseTests {

    @Test func repositorySearchAndCount() {
        let stub = RuntimeStub<any UserRepository>()
        stub.when { $0.find(id: 1) }.returns("Alice")
        stub.when { $0.find(id: any()) }.returns("Unknown")
        stub.when { $0.search(query: any()) }.returns(["Alice", "Bob"])
        stub.when { $0.count }.returns(2)

        let sut: any UserRepository = stub()

        #expect(sut.find(id: 1) == "Alice")
        #expect(sut.find(id: 999) == "Unknown")
        #expect(sut.search(query: "a") == ["Alice", "Bob"])
        #expect(sut.count == 2)
    }

    @Test func throwingFileServiceHappyPath() throws {
        let stub = RuntimeStub<any ThrowingFileService>()
        stub.when { try $0.read(path: any()) }.returns("file contents")
        stub.when { try $0.write(path: any(), content: any()) }
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/mock")

        let sut: any ThrowingFileService = stub()

        #expect(try sut.read(path: "/readme.txt") == "file contents")
        #expect(throws: Never.self) { try sut.write(path: "/out.txt", content: "data") }
        #expect(sut.basePath == "/mock")
    }

    @Test func dynamicAnswers() {
        let stub = RuntimeStub<any UserRepository>()
        stub.when { $0.find(id: any()) }.then { args in
            let id = args[0] as! Int
            return "User_\(id)"
        }
        stub.when { $0.search(query: any()) }.then { args in
            let q = args[0] as! String
            return q.isEmpty ? [] : [q.uppercased()]
        }
        stub.when { $0.count }.returns(100)

        let sut: any UserRepository = stub()

        #expect(sut.find(id: 42) == "User_42")
        #expect(sut.search(query: "alice") == ["ALICE"])
        #expect(sut.search(query: "") == [])
    }

    @Test func fileServiceReadWriteVerify() throws {
        let stub = RuntimeStub<any ThrowingFileService>()
        stub.when { try $0.read(path: "/a.txt") }.returns("aaa")
        stub.when { try $0.read(path: any()) }.returns("default")
        stub.when { try $0.write(path: any(), content: any()) }
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/mock")

        let sut: any ThrowingFileService = stub()
        #expect(try sut.read(path: "/a.txt") == "aaa")
        #expect(try sut.read(path: "/c.txt") == "default")
        try sut.write(path: "/out.txt", content: "data")

        stub.verify(called: 2) { try $0.read(path: any()) }
        stub.verify(called: 1) { try $0.write(path: any(), content: any()) }
    }

    @Test func argumentInspection() {
        let stub = RuntimeStub<any UserRepository>()
        stub.when { $0.search(query: any()) }.returns([])
        stub.when { $0.count }.returns(0)

        let sut: any UserRepository = stub()
        _ = sut.search(query: "alice")
        _ = sut.search(query: "bob")

        stub.verify { $0.search(query: any()) }.withArgs { calls in
            #expect(calls.count == 2)
            #expect(calls[0][0] as! String == "alice")
            #expect(calls[1][0] as! String == "bob")
        }
    }

    @Test func orderedVerification() {
        let stub = RuntimeStub<any UserRepository>()
        stub.when { $0.find(id: any()) }.returns("X")
        stub.when { $0.search(query: any()) }.returns([])
        stub.when { $0.count }.returns(0)

        let sut: any UserRepository = stub()
        _ = sut.find(id: 1)
        _ = sut.search(query: "test")

        stub.verifyOrder {
            $0.find(id: any())
            $0.search(query: any())
        }
    }

    @Test func multipleMocks() throws {
        let repoStub = RuntimeStub<any UserRepository>()
        let fileStub = RuntimeStub<any ThrowingFileService>()

        repoStub.when { $0.find(id: any()) }.returns("Alice")
        repoStub.when { $0.count }.returns(1)

        fileStub.when { try $0.read(path: any()) }.returns("data")
        fileStub.when { $0.exists(at: any()) }.returns(true)
        fileStub.when { $0.basePath }.returns("/tmp")

        #expect(repoStub().find(id: 1) == "Alice")
        #expect(try fileStub().read(path: "/test") == "data")

        repoStub.verify(called: 1) { $0.find(id: any()) }
        fileStub.verify(called: 1) { try $0.read(path: any()) }
    }

    @Test func predicateMatching() {
        let stub = RuntimeStub<any UserRepository>()
        stub.when { $0.find(id: any(where: { $0 > 100 })) }.returns("VIP")
        stub.when { $0.find(id: any(where: { $0 <= 100 })) }.returns("Regular")
        stub.when { $0.count }.returns(0)

        let sut: any UserRepository = stub()

        #expect(sut.find(id: 101) == "VIP")
        #expect(sut.find(id: 50) == "Regular")
    }
}
