import Foundation
import Testing
@testable import Cicada

/// 手记：不属于任何会议的待办，存在 Todos/inbox.json。
@MainActor @Suite struct TodoInboxTests {
    private func dir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-inbox-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func addedTodosAreReadBack() {
        let file = dir().appendingPathComponent("inbox.json")
        TodoInbox(file: file).add(text: "约摄影师", owner: nil, due: nil)
        let again = TodoInbox(file: file)
        #expect(again.items.count == 1)
        #expect(again.items.first?.owner == "你")
        #expect(again.items.first?.byUser == true)
    }

    @Test func changesAreSaved() {
        let file = dir().appendingPathComponent("inbox.json")
        let inbox = TodoInbox(file: file)
        inbox.add(text: "约摄影师", owner: nil, due: nil)
        inbox.change(key: inbox.items[0].key, .state(.done), now: Date())
        #expect(TodoInbox(file: file).items.first?.status == .done)
        inbox.change(key: inbox.items[0].key, .delete, now: Date())
        #expect(TodoInbox(file: file).items.isEmpty)
    }

    @Test func aBrokenFileIsSetAsideNotOverwritten() throws {
        let d = dir()
        let file = d.appendingPathComponent("inbox.json")
        try Data("not json".utf8).write(to: file)
        let inbox = TodoInbox(file: file)
        #expect(inbox.items.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: d.path)
        #expect(names.contains { $0.hasPrefix("inbox.bad-") && $0.hasSuffix(".json") })
        #expect(!names.contains("inbox.json"))
    }
}
