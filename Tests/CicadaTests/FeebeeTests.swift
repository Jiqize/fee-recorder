import Foundation
import Testing
@testable import Cicada

/// 页边栏和页眉里的菲比画哪一张（DESIGN.md › 原创角色）。
@Suite struct FeebeeTests {
    @Test func liveFailureShowsTheError() {
        #expect(FeebeeMood.of(live: true, notesState: .failed, hasNotes: true, final: false) == .error)
        #expect(FeebeeMood.of(live: true, notesState: .noKey, hasNotes: false, final: false) == .error)
    }

    @Test func writingWinsWhileNotesUpdate() {
        #expect(FeebeeMood.of(live: true, notesState: .updating, hasNotes: false, final: false) == .writing)
        #expect(FeebeeMood.of(live: false, notesState: .updating, hasNotes: true, final: true) == .writing)
    }

    @Test func listeningWhileLive() {
        #expect(FeebeeMood.of(live: true, notesState: .idle, hasNotes: false, final: false) == .listening)
    }

    @Test func doneOnceTheNotesAreFinal() {
        #expect(FeebeeMood.of(live: false, notesState: .idle, hasNotes: true, final: true) == .done)
    }

    @Test func otherwiseNapping() {
        #expect(FeebeeMood.of(live: false, notesState: .failed, hasNotes: false, final: false) == .idle)
        #expect(FeebeeMood.of(live: false, notesState: .noKey, hasNotes: true, final: true) == .done)
        #expect(FeebeeMood.of(live: false, notesState: .idle, hasNotes: true, final: false) == .idle)
    }

    @Test func everyMoodHasItsPictures() {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/illustrations")
        for mood in FeebeeMood.allCases {
            #expect(mood.imageName == "feebee-\(mood.rawValue)")
            for suffix in ["", "@2x"] {
                let f = dir.appendingPathComponent("\(mood.imageName)\(suffix).png").path
                #expect(FileManager.default.fileExists(atPath: f), "\(f)")
            }
        }
    }
}
