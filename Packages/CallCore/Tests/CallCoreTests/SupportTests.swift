import XCTest
@testable import CallCore

private protocol Greeter: AnyObject {
    func greet() -> String
}

private final class EnglishGreeter: Greeter {
    func greet() -> String { "Hello" }
}

private final class Counter {
    static var instances = 0
    init() { Counter.instances += 1 }
}

final class DependencyContainerTests: XCTestCase {

    @MainActor
    func testSingletonIsBuiltOnceAndShared() async {
        let container = DependencyContainer()
        container.register((any Greeter).self) { _ in EnglishGreeter() }

        let first = container.resolve((any Greeter).self)
        let second = container.resolve((any Greeter).self)
        XCTAssertTrue(first === second)
        XCTAssertEqual(first.greet(), "Hello")
    }

    @MainActor
    func testTransientIsBuiltOnEveryResolve() async {
        Counter.instances = 0
        let container = DependencyContainer()
        container.register(Counter.self, lifetime: .transient) { _ in Counter() }

        let first = container.resolve(Counter.self)
        let second = container.resolve(Counter.self)
        XCTAssertFalse(first === second)
        XCTAssertEqual(Counter.instances, 2)
    }

    @MainActor
    func testFactoriesCanResolveOtherDependencies() async throws {
        let container = DependencyContainer()
        container.register((any CallHistoryRepository).self) { _ in InMemoryCallHistoryStore() }
        container.register((any ContactRepository).self) { _ in SampleContactRepository() }
        container.register(String.self, lifetime: .transient) { c in
            c.isRegistered((any ContactRepository).self) ? "wired" : "missing"
        }

        XCTAssertEqual(container.resolve(String.self), "wired")
        let contacts = try await container.resolve((any ContactRepository).self).fetchContacts()
        XCTAssertEqual(contacts.count, SampleContacts.all.count)
    }

    @MainActor
    func testReRegisteringReplacesCachedSingleton() async {
        let container = DependencyContainer()
        container.register(String.self) { _ in "first" }
        XCTAssertEqual(container.resolve(String.self), "first")

        container.register(String.self) { _ in "second" }
        XCTAssertEqual(container.resolve(String.self), "second")
    }

    @MainActor
    func testUnregisteredServiceResolvesToNil() async {
        let container = DependencyContainer()
        XCTAssertNil(container.resolveIfRegistered(Int.self))
        XCTAssertFalse(container.isRegistered(Int.self))
    }
}

final class ContactTests: XCTestCase {

    func testInitials() {
        XCTAssertEqual(Contact(id: "1", name: "Ayesha Rahman", handle: "1").initials, "AR")
        XCTAssertEqual(Contact(id: "2", name: "mei", handle: "1").initials, "M")
        XCTAssertEqual(Contact(id: "3", name: "Jean-Luc Picard Smith", handle: "1").initials, "JL")
        XCTAssertEqual(Contact(id: "4", name: "", handle: "1").initials, "#")
    }

    func testSearchMatchesNameAndDigits() {
        let contact = Contact(id: "1", name: "Ayesha Rahman", handle: "+1 (555) 010-0101")
        XCTAssertTrue(contact.matches(""))
        XCTAssertTrue(contact.matches("ayesha"))
        XCTAssertTrue(contact.matches("RAHM"))
        XCTAssertTrue(contact.matches("5550100"))
        XCTAssertTrue(contact.matches("010-0101"))
        XCTAssertFalse(contact.matches("daniel"))
        XCTAssertFalse(contact.matches("999"))
    }

    func testSampleRepositorySortsByName() async throws {
        let contacts = try await SampleContactRepository().fetchContacts()
        let names = contacts.map(\.name)
        XCTAssertEqual(names, names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }
}

final class LoopbackCallProviderTests: XCTestCase {

    @MainActor
    func testRequestsAreEchoedAsActions() async throws {
        let provider = LoopbackCallProvider()
        let id = UUID()
        var iterator = provider.events.makeAsyncIterator()

        try await provider.requestStartCall(id: id, handle: "100", displayName: nil)
        try await provider.requestSetMuted(true, id: id)

        let start = await iterator.next()
        guard case let .perform(startAction) = start else { return XCTFail("expected start action") }
        XCTAssertEqual(startAction.callID, id)
        XCTAssertEqual(startAction.kind, .start(handle: "100"))

        let audio = await iterator.next()
        guard case .audioSessionActivated = audio else { return XCTFail("expected audio activation") }

        let mute = await iterator.next()
        guard case let .perform(muteAction) = mute else { return XCTFail("expected mute action") }
        XCTAssertEqual(muteAction.kind, .setMuted(true))
    }

    @MainActor
    func testReportsAreRecorded() async {
        let provider = LoopbackCallProvider()
        let id = UUID()

        provider.reportOutgoingCallStartedConnecting(id: id)
        provider.reportOutgoingCallConnected(id: id)
        provider.reportCallEnded(id: id, reason: .busy)

        XCTAssertEqual(provider.reportedConnecting, [id])
        XCTAssertEqual(provider.reportedConnected, [id])
        XCTAssertEqual(provider.reportedEnded.first?.reason, .busy)
    }

    func testProviderActionCompletionFiresOnce() {
        let box = ResultBox()
        let action = ProviderAction(callID: UUID(), kind: .answer) { box.results.append($0) }
        action.fulfill()
        XCTAssertEqual(box.results, [true])

        let failing = ProviderAction(callID: UUID(), kind: .end) { box.results.append($0) }
        failing.fail()
        XCTAssertEqual(box.results, [true, false])
    }

    private final class ResultBox: @unchecked Sendable {
        var results: [Bool] = []
    }
}
