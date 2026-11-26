import AppKit
import SwiftUI

/// The local people library: voices remembered by voiceprint, plus what the user knows about the
/// person. Voiceprints are biometric data: every row can be
/// removed here, and nothing is uploaded.
struct SpeakerLibraryView: View {
    @ObservedObject var model: AppModel
    @State private var editing: UUID?
    @State private var draft = ""
    @State private var detail: SpeakerProfile?
    @Environment(\.dismiss) private var dismiss

    private var profiles: [SpeakerProfile] { model.speakerProfiles }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("人员库")).font(.fee(.title)).foregroundStyle(Palette.ink)
                    Text(L("声纹只保存在这台 Mac；可以写备注，也可以删除。"))
                        .font(.fee(.label)).foregroundStyle(Palette.tertiary)
                }
                Spacer()
                Button(L("完成")) { dismiss() }.buttonStyle(.plain)
                    .font(.fee(.body, strong: true)).foregroundStyle(Palette.accentInk)
            }

            if profiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.badge.key").font(.icon(26)).foregroundStyle(Palette.tertiary)
                    Text(L("还没有记住的人")).font(.fee(.body, strong: true)).foregroundStyle(Palette.ink)
                    Text(L("在会议里点一个说话人，选“记住这个声音”，下次就会自动认出。"))
                        .font(.fee(.label)).foregroundStyle(Palette.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    VStack(spacing: 8) { // 人和人之间空出来，不画细线
                        ForEach(profiles) { p in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 12) {
                                    // 名字首字，红铅笔圈一圈
                                    Circle().stroke(Palette.accentInk, lineWidth: 1.4).frame(width: 28, height: 28)
                                        .overlay(Text(String(p.name.prefix(1))).font(.fee(.bodySecondary, strong: true))
                                            .foregroundStyle(Palette.accentInk))
                                    VStack(alignment: .leading, spacing: 2) {
                                        if editing == p.id {
                                            TextField(L("名字"), text: $draft)
                                                .textFieldStyle(.paper)
                                                .onSubmit { save(p) }
                                        } else {
                                            Text(p.name).font(.fee(.body, strong: true)).foregroundStyle(Palette.ink)
                                        }
                                        Text(L("\(p.sampleCount) 段样本 · 最近 \(seen(p.lastSeenAt))"))
                                            .font(.fee(.label)).foregroundStyle(Palette.tertiary)
                                    }
                                    Spacer()
                                    if editing == p.id {
                                        SoftButton(L("保存"), dark: true) { save(p) }
                                        Button(L("取消")) { editing = nil }.buttonStyle(.plain)
                                            .font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                                    } else {
                                        Button(L("资料")) { detail = p }.buttonStyle(.plain)
                                            .font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                                        Button(L("改名")) { editing = p.id; draft = p.name }.buttonStyle(.plain)
                                            .font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                                        Button(L("删除")) { delete(p) }.buttonStyle(.plain)
                                            .font(.fee(.bodySecondary)).foregroundStyle(Palette.accentInk)
                                    }
                                }
                                if let notes = p.notes, !notes.isEmpty {
                                    Text(notes).font(.fee(.label)).foregroundStyle(Palette.tertiary)
                                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                        .padding(.leading, 40)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 54)
                        }
                    }
                    // 不装卡片，直接写在纸上
                }
                HStack {
                    Text(L("共 \(profiles.count) 个人")).font(.fee(.label)).foregroundStyle(Palette.tertiary)
                    Spacer()
                    Button(L("全部删除")) { deleteAll() }.buttonStyle(.plain)
                        .font(.fee(.bodySecondary, strong: true)).foregroundStyle(Palette.accentInk)
                }
            }
        }
        .padding(24)
        .frame(width: 640, height: 520)
        .background(Palette.ground)
        .decor(.medium)
        .sheet(item: $detail) { p in SpeakerProfileEditor(model: model, profile: p) }
    }

    private func save(_ p: SpeakerProfile) {
        model.renameSpeakerProfile(id: p.id, to: draft)
        editing = nil
    }

    private func delete(_ p: SpeakerProfile) {
        let a = NSAlert()
        a.messageText = L("删除“\(p.name)”的声纹？")
        a.informativeText = L("之后的会议不会再自动认出这个人；已经生成的记录保持原样。")
        a.addButton(withTitle: L("删除"))
        a.addButton(withTitle: L("取消"))
        if a.runModal() == .alertFirstButtonReturn { model.deleteSpeakerProfile(id: p.id) }
    }

    private func deleteAll() {
        let a = NSAlert()
        a.messageText = L("删除全部声纹？")
        a.informativeText = L("之后所有会议都不会再自动认出人；已有记录保持原样。")
        a.addButton(withTitle: L("全部删除"))
        a.addButton(withTitle: L("取消"))
        if a.runModal() == .alertFirstButtonReturn { model.deleteAllSpeakerProfiles() }
    }

    private func seen(_ date: Date?) -> String {
        guard let date else { return L("还没在新会议里出现") }
        let f = RelativeDateTimeFormatter()
        f.locale = uiLocale
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

/// Edit the human part of a person's profile; the voiceprint itself stays untouched.
struct SpeakerProfileEditor: View {
    @ObservedObject var model: AppModel
    let profile: SpeakerProfile
    @State private var name: String
    @State private var notes: String
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, profile: SpeakerProfile) {
        self.model = model
        self.profile = profile
        _name = State(initialValue: profile.name)
        _notes = State(initialValue: profile.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("人员资料")).font(.fee(.title))
            TextField(L("名字"), text: $name).textFieldStyle(.paper)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("备注（公司、职位、下次要记住的事）"))
                    .font(.fee(.label, strong: true)).foregroundStyle(Palette.secondary)
                TextEditor(text: $notes)
                    .font(.fee(.body))
                    .padding(7)
                    .frame(minHeight: 140)
                    // 方角白纸
                    .background(Rectangle().fill(Palette.polaroid))
                    .overlay(Rectangle().stroke(Palette.hairline, lineWidth: 1))
            }
            Spacer()
            HStack {
                Spacer()
                Button(L("取消")) { dismiss() }.buttonStyle(.plain)
                SoftButton(L("保存"), dark: true) {
                    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty { model.renameSpeakerProfile(id: profile.id, to: clean) }
                    model.saveSpeakerProfileNotes(id: profile.id, notes: notes)
                    dismiss()
                }
            }
        }
        .padding(20)
        .frame(width: 460, height: 430)
        .background(Palette.paper)
        .decor(.medium)
    }
}
