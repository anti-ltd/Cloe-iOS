import SwiftUI

#Preview { ChangelogView().environment(AppModel().settings) }

struct ChangelogView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CloeSheetChrome(title: "What's New", dismiss: { dismiss() }) {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Self.versions) { v in
                        ChangelogCard(version: v, isLatest: v.id == 0, theme: settings.visualTheme)
                    }
                }
                .padding()
            }
            .background(CloePalette.canvas)
        }
        .tint(settings.visualTheme.primary)
    }

    struct Version: Identifiable {
        let id: Int
        let title: String
        let bodyLines: [String]
    }

    static var versions: [Version] {
        var out: [Version] = []
        var title: String?
        var body: [String] = []
        func flush() {
            if let title { out.append(.init(id: out.count, title: title, bodyLines: body)) }
            body = []
        }
        for raw in ChangelogData.markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                flush()
                title = String(trimmed.dropFirst(3))
                    .replacingOccurrences(of: "[", with: "")
                    .replacingOccurrences(of: "]", with: "")
            } else if title != nil {
                body.append(line)
            }
        }
        flush()
        return out
    }
}

private struct ChangelogCard: View {
    let version: ChangelogView.Version
    let isLatest: Bool
    var theme: CloeTheme
    @State private var expanded: Bool

    init(version: ChangelogView.Version, isLatest: Bool, theme: CloeTheme) {
        self.version = version
        self.isLatest = isLatest
        self.theme = theme
        _expanded = State(initialValue: isLatest)
    }

    private enum Block {
        case section(String)
        case bullet(AttributedString)
        case paragraph(AttributedString)
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var buf: String?
        var bufIsBullet = false
        func flush() {
            guard let t = buf else { return }
            out.append(bufIsBullet ? .bullet(inline(t)) : .paragraph(inline(t)))
            buf = nil
        }
        for line in version.bodyLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { flush(); continue }
            if trimmed.hasPrefix("### ") {
                flush(); out.append(.section(String(trimmed.dropFirst(4)))); continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flush(); buf = String(trimmed.dropFirst(2)); bufIsBullet = true; continue
            }
            if buf != nil { buf! += " " + trimmed }
            else { buf = trimmed; bufIsBullet = false }
        }
        flush()
        return out
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(s)
    }

    private var versionParts: (number: String, date: String?) {
        let parts = version.title.components(separatedBy: " - ")
        return (parts.first ?? version.title, parts.count > 1 ? parts[1] : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(versionParts.number).font(.headline)
                    if let date = versionParts.date {
                        Text(date).font(.caption).foregroundStyle(.secondary)
                    }
                    if isLatest {
                        Text("Latest")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(theme.primary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().padding(.horizontal, 14)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .section(let s):
                            Text(s.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        case .bullet(let a):
                            Text(a).font(.callout)
                        case .paragraph(let a):
                            Text(a).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
            }
        }
        .background(CloePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
