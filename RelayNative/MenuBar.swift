import SwiftUI

// Menu-bar companion: an always-there unread count and a quick panel of conversations you
// can jump straight into, without bringing the whole window forward first.

struct MenuBarLabel: View {
    @ObservedObject var store: RelayStore
    var body: some View {
        let n = store.unreadConversationCount
        // The menu-bar item: a chat glyph, with the unread count appended when there is one.
        if n > 0 {
            Label("\(n)", systemImage: "message.fill")
        } else {
            Image(systemName: "message")
        }
    }
}

struct MenuBarPanel: View {
    @ObservedObject var store: RelayStore
    @Environment(\.openWindow) private var openWindow

    // Unread first, then the most recent — capped so the panel stays compact.
    private var rows: [ChatThread] {
        let unread = store.threads.filter { $0.unread && !$0.muted }
        if !unread.isEmpty { return Array(unread.prefix(10)) }
        return Array(store.threads.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Relay").font(.headline)
                Spacer()
                let n = store.unreadConversationCount
                if n > 0 {
                    Text("\(n) unread").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            Divider()

            if rows.isEmpty {
                Text(store.connected ? "No conversations yet." : "Connecting…")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(rows) { t in
                            MenuBarRow(thread: t) { open(t.id) }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
            }

            Divider()
            HStack {
                Button("Open Relay") { openMainWindow() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(width: 320)
    }

    private func open(_ id: String) {
        store.ensureStarted()
        store.pendingOpen = id
        openMainWindow()
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MenuBarRow: View {
    @EnvironmentObject var store: RelayStore
    let thread: ChatThread
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Avatar(url: store.threadAvatar(thread), title: store.threadTitle(thread), size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.threadTitle(thread))
                        .font(.system(size: 13, weight: thread.unread ? .semibold : .regular))
                        .lineLimit(1)
                    Text(thread.snippet).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if thread.unread, !thread.muted {
                    Circle().fill(store.accent(for: thread.id)).frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
