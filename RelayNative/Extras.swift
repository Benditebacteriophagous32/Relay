import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Typing indicator (animated three dots in a received-style bubble)

struct TypingDots: View {
    var body: some View {
        // TimelineView redraws every frame, so each dot is recomputed continuously — a real,
        // smooth wave (animating a derived value through .animation() never actually moves).
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    let v = max(0.0, sin(t * 6 - Double(i) * 0.9))   // staggered bounce per dot
                    Circle()
                        .fill(.secondary)
                        .frame(width: 7, height: 7)
                        .opacity(0.35 + 0.55 * v)
                        .offset(y: -4 * v)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 2)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

// MARK: - Wallpapers

/// A selectable conversation background. Built-ins are gradients; a custom one is any image
/// the user picks from disk (including macOS desktop pictures under /System/Library).
struct Wallpaper {
    struct Builtin: Identifiable {
        let id: String
        let name: String
        let colors: [Color]
        let point: (start: UnitPoint, end: UnitPoint)
        var gradient: LinearGradient {
            LinearGradient(colors: colors, startPoint: point.start, endPoint: point.end)
        }
    }

    static let builtins: [Builtin] = [
        .init(id: "aurora",   name: "Aurora",   colors: [Color(hex: "#1B2735")!, Color(hex: "#2C5364")!, Color(hex: "#0F2027")!], point: (.topLeading, .bottomTrailing)),
        .init(id: "dusk",     name: "Dusk",     colors: [Color(hex: "#41295A")!, Color(hex: "#2F0743")!], point: (.top, .bottom)),
        .init(id: "ember",    name: "Ember",    colors: [Color(hex: "#42275A")!, Color(hex: "#734B6D")!], point: (.topLeading, .bottomTrailing)),
        .init(id: "ocean",    name: "Ocean",    colors: [Color(hex: "#0F2027")!, Color(hex: "#203A43")!, Color(hex: "#2C5364")!], point: (.top, .bottom)),
        .init(id: "forest",   name: "Forest",   colors: [Color(hex: "#134E5E")!, Color(hex: "#0B3B2E")!], point: (.topLeading, .bottomTrailing)),
        .init(id: "graphite", name: "Graphite", colors: [Color(hex: "#232526")!, Color(hex: "#414345")!], point: (.top, .bottom)),
        .init(id: "rose",     name: "Rosé",     colors: [Color(hex: "#3A1C2E")!, Color(hex: "#5E2A45")!], point: (.topLeading, .bottomTrailing)),
        .init(id: "midnight", name: "Midnight", colors: [Color(hex: "#0F0C29")!, Color(hex: "#302B63")!, Color(hex: "#24243E")!], point: (.top, .bottom)),
    ]

    static func builtin(_ id: String) -> Builtin? { builtins.first { $0.id == id } }

    /// Whether an id refers to a user-picked image file ("file:<path>").
    static func filePath(_ id: String?) -> String? {
        guard let id, id.hasPrefix("file:") else { return nil }
        return String(id.dropFirst("file:".count))
    }
}

/// Caches decoded wallpaper images by path so ThreadView's body doesn't hit disk each render.
enum WallpaperImageCache {
    private static var images: [String: NSImage] = [:]
    static func image(_ path: String) -> NSImage? {
        if let i = images[path] { return i }
        guard let i = NSImage(contentsOfFile: path) else { return nil }
        images[path] = i
        return i
    }
}

/// The background that sits behind a conversation's messages.
struct ConversationBackground: View {
    let wallpaper: String?
    var body: some View {
        Group {
            if let path = Wallpaper.filePath(wallpaper), let img = WallpaperImageCache.image(path) {
                Image(nsImage: img).resizable().scaledToFill()
                    .overlay(Color.black.opacity(0.22))   // scrim keeps bubbles legible
            } else if let id = wallpaper, let b = Wallpaper.builtin(id) {
                b.gradient
            } else {
                Color.black.opacity(0.04)   // default: barely-there tint over the window glass
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - Emoji picker (with GIFs nested in a second tab)

enum EmojiData {
    static let categories: [(name: String, symbol: String, emoji: [String])] = [
        ("Smileys", "face.smiling", "😀 😃 😄 😁 😆 😅 😂 🤣 🥲 ☺️ 😊 😇 🙂 🙃 😉 😌 😍 🥰 😘 😗 😙 😚 😋 😛 😝 😜 🤪 🤨 🧐 🤓 😎 🥸 🤩 🥳 😏 😒 😞 😔 😟 😕 🙁 ☹️ 😣 😖 😫 😩 🥺 😢 😭 😤 😠 😡 🤬 🤯 😳 🥵 🥶 😱 😨 😰 😥 😓 🤗 🤔 🤭 🤫 🫡 🫠 😶 😐 😑 😬 🙄 😯 😦 😧 😮 😲 🥱 😴 🤤 😪 😵 🤐 🥴 🤢 🤮 🤧 😷 🤒 🤕".split(separator: " ").map(String.init)),
        ("Gestures", "hand.raised", "👋 🤚 🖐 ✋ 🖖 👌 🤌 🤏 ✌️ 🤞 🫰 🤟 🤘 🤙 👈 👉 👆 👇 ☝️ 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 🫶 👐 🤲 🙏 ✍️ 💅 🤳 💪 🦾 🦵 🦶 👂 👃 🧠 🫀 🫁 🦷 👀 👁 👅 👄".split(separator: " ").map(String.init)),
        ("Hearts", "heart", "❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟 ♥️ 💋 💯 💢 💥 💫 💦 💨 🕳 💬 🗯 💭 💤".split(separator: " ").map(String.init)),
        ("Animals", "pawprint", "🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐻‍❄️ 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🙈 🙉 🙊 🐔 🐧 🐦 🐤 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🐝 🪱 🐛 🦋 🐌 🐞 🐜 🪰 🐢 🐍 🦖 🐙 🦑 🦀 🐠 🐟 🐬 🐳 🐋 🦈".split(separator: " ").map(String.init)),
        ("Food", "fork.knife", "🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🥦 🥬 🥒 🌶 🌽 🥕 🧄 🧅 🥔 🍠 🥐 🍞 🥖 🧀 🥚 🍳 🥞 🧇 🥓 🍔 🍟 🍕 🌭 🥪 🌮 🌯 🍜 🍝 🍣 🍦 🍩 🍪 🎂 🍰 🍫 🍬 🍭 ☕️ 🍵 🍺 🍷 🥂 🍸".split(separator: " ").map(String.init)),
        ("Activities", "figure.run", "⚽️ 🏀 🏈 ⚾️ 🥎 🎾 🏐 🏉 🎱 🏓 🏸 🥅 🏒 🏑 🥍 🏏 ⛳️ 🏹 🎣 🥊 🥋 🎽 🛹 🛼 🛷 ⛸ 🥌 🎿 ⛷ 🏂 🪂 🏋️ 🤼 🤸 ⛹️ 🤺 🤾 🏌️ 🏇 🧘 🏄 🏊 🚴 🎮 🎯 🎲 🎰 🎳".split(separator: " ").map(String.init)),
        ("Travel", "airplane", "🚗 🚕 🚙 🚌 🚎 🏎 🚓 🚑 🚒 🚐 🚚 🚛 🚜 🛵 🏍 🚲 🛴 ✈️ 🚀 🛸 🚁 ⛵️ 🚤 🛥 🚢 🚂 🚆 🚇 🗺 🗽 🗼 🏰 🏯 🎡 🎢 🎠 ⛲️ 🏖 🏝 🏔 🌋 🗻 🏕 ⛺️ 🌃 🌉 🌁".split(separator: " ").map(String.init)),
        ("Objects", "lightbulb", "⌚️ 📱 💻 ⌨️ 🖥 🖨 🖱 💽 💾 📷 📸 🎥 📺 📻 🎙 ⏰ 🔋 💡 🔦 📚 📖 💰 💳 💎 🔧 🔨 🧰 🧲 🔒 🔑 🚪 🛋 🛏 🚽 🚿 🛁 🧴 🧼 🧽 🛒 🎁 🎈 🎉 🎊 🪄 🔮".split(separator: " ").map(String.init)),
        ("Symbols", "number", "✅ ❌ ⭕️ ❓ ❗️ ‼️ ⚠️ 🔔 🚫 💲 ➕ ➖ ➗ ✖️ ♻️ ✔️ ☑️ 🔁 🔂 🔄 ▶️ ⏸ ⏯ ⏹ 🔼 🔽 ⏫ ⏬ 🆗 🆕 🆒 🆓 🔥 ⭐️ 🌟 ✨ ⚡️ 🎵 🎶 ➰ 〽️ 🔱 ♾ 💠 🔰".split(separator: " ").map(String.init)),
    ]
}

/// Emoji + GIF picker shown in a popover from the composer. Picking emoji inserts into the
/// draft (popover stays open so several can be added); the GIF tab embeds the GIF browser.
struct EmojiGifPicker: View {
    let onEmoji: (String) -> Void
    let onGif: (_ mp4URL: String, _ gifURL: String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var tab = 0   // 0 = emoji, 1 = gif
    @State private var category = 0
    @AppStorage("recentEmoji") private var recentRaw = ""

    private var recents: [String] {
        recentRaw.split(separator: " ").map(String.init)
    }
    private func remember(_ e: String) {
        var list = recents.filter { $0 != e }
        list.insert(e, at: 0)
        recentRaw = list.prefix(24).joined(separator: " ")
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 8)

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Emoji").tag(0)
                Text("GIF").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)

            if tab == 0 { emojiTab } else {
                GifPicker(onPick: onGif).frame(width: 360, height: 380)
            }
        }
        .frame(width: 360)
    }

    private var emojiTab: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    if !recents.isEmpty && category == 0 {
                        Section {
                            ForEach(recents, id: \.self) { e in emojiCell(e) }
                        } header: { gridHeader("Recent") }
                    }
                    Section {
                        ForEach(EmojiData.categories[category].emoji, id: \.self) { e in emojiCell(e) }
                    } header: { gridHeader(EmojiData.categories[category].name) }
                }
                .padding(.horizontal, 10).padding(.bottom, 8)
            }
            .frame(height: 300)
            Divider()
            // Category bar.
            HStack(spacing: 0) {
                ForEach(Array(EmojiData.categories.enumerated()), id: \.offset) { i, cat in
                    Button { category = i } label: {
                        Image(systemName: cat.symbol)
                            .font(.system(size: 13))
                            .foregroundStyle(category == i ? Color.accentColor : .secondary)
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
        }
    }

    private func gridHeader(_ s: String) -> some View {
        HStack {
            Text(s.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.top, 8).padding(.bottom, 2)
    }

    private func emojiCell(_ e: String) -> some View {
        Button {
            onEmoji(e); remember(e)
        } label: {
            Text(e).font(.system(size: 24)).frame(width: 38, height: 38).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Export conversation

/// Choose a time range and export a plain-text transcript to a file.
struct ExportConversationSheet: View {
    @EnvironmentObject var store: RelayStore
    @Environment(\.dismiss) private var dismiss
    let thread: ChatThread

    enum Range: String, CaseIterable, Identifiable {
        case all = "Entire conversation"
        case last7 = "Last 7 days"
        case last30 = "Last 30 days"
        case custom = "Custom range"
        var id: String { rawValue }
    }
    @State private var range: Range = .all
    @State private var from = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var history: [Message] = []   // full thread, loaded once from the DB

    private var bounds: (Date?, Date?) {
        switch range {
        case .all:    return (nil, nil)
        case .last7:  return (Calendar.current.date(byAdding: .day, value: -7, to: Date()), nil)
        case .last30: return (Calendar.current.date(byAdding: .day, value: -30, to: Date()), nil)
        case .custom: return (Calendar.current.startOfDay(for: from),
                              Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: to))
        }
    }

    private var messageCount: Int {
        let (lo, hi) = bounds
        let l = (lo?.timeIntervalSince1970 ?? 0) * 1000
        let h = (hi?.timeIntervalSince1970 ?? Date.distantFuture.timeIntervalSince1970) * 1000
        return history.filter {
            $0.ts >= l && $0.ts <= h && !$0.id.hasPrefix("local-") && !$0.system
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Export conversation").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            Text("Save the text of your chat with \(store.threadTitle(thread)) to a file. Photos and other media are listed as placeholders — text only.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            Picker("Range", selection: $range) {
                ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.radioGroup)

            if range == .custom {
                HStack(spacing: 12) {
                    DatePicker("From", selection: $from, in: ...to, displayedComponents: .date)
                    DatePicker("To", selection: $to, in: from...Date(), displayedComponents: .date)
                }
                .datePickerStyle(.field).labelsHidden()
                .font(.system(size: 12))
            }

            HStack {
                Text("\(messageCount) message\(messageCount == 1 ? "" : "s") in range")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    export()
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(messageCount == 0)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { history = store.fullHistory(thread.id) }
    }

    private func export() {
        let (lo, hi) = bounds
        let text = store.transcript(for: thread, from: lo, to: hi)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let safeTitle = store.threadTitle(thread).replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "Relay — \(safeTitle).txt"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? text.data(using: .utf8)?.write(to: url, options: .atomic)
        }
        dismiss()
    }
}

// MARK: - Nickname editor

/// Set or clear a person's per-conversation nickname.
struct NicknameSheet: View {
    @EnvironmentObject var store: RelayStore
    @Environment(\.dismiss) private var dismiss
    let thread: String
    let contactID: String
    let realName: String

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set nickname").font(.headline)
            Text("Only you see this. It replaces \(realName)'s name in this conversation.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField(realName, text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { save() }
            HStack {
                if store.nickname(for: contactID, in: thread) != nil {
                    Button("Remove", role: .destructive) {
                        store.setNickname(nil, for: contactID, in: thread); dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { draft = store.nickname(for: contactID, in: thread) ?? "" }
    }

    private func save() {
        store.setNickname(draft, for: contactID, in: thread)
        dismiss()
    }
}

// MARK: - Wallpaper picker section (used in ThreadInfoView)

struct WallpaperSection: View {
    @EnvironmentObject var store: RelayStore
    let threadID: String

    private var current: String? { store.wallpaper(for: threadID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Wallpaper").font(.system(size: 13, weight: .semibold))
                Spacer()
                if current != nil {
                    Button("Reset") { withAnimation(.snappy(duration: 0.2)) { store.setWallpaper(nil, for: threadID) } }
                        .font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    defaultTile
                    ForEach(Wallpaper.builtins) { b in tile(b) }
                    customTile
                }
                .padding(.horizontal, 1).padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 4)
    }

    private func selectedRing(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(on ? Color.accentColor : .white.opacity(0.15), lineWidth: on ? 2.5 : 0.5)
    }

    private var defaultTile: some View {
        Button { withAnimation(.snappy(duration: 0.2)) { store.setWallpaper(nil, for: threadID) } } label: {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Image(systemName: "slash.circle").foregroundStyle(.secondary))
                .frame(width: 52, height: 78)
                .overlay(selectedRing(current == nil))
        }
        .buttonStyle(.plain).help("No wallpaper")
    }

    private func tile(_ b: Wallpaper.Builtin) -> some View {
        Button { withAnimation(.snappy(duration: 0.2)) { store.setWallpaper(b.id, for: threadID) } } label: {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(b.gradient)
                .frame(width: 52, height: 78)
                .overlay(selectedRing(current == b.id))
        }
        .buttonStyle(.plain).help(b.name)
    }

    private var customTile: some View {
        Button { pickImage() } label: {
            ZStack {
                if let path = Wallpaper.filePath(current), let img = WallpaperImageCache.image(path) {
                    Image(nsImage: img).resizable().scaledToFill().frame(width: 52, height: 78)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(Image(systemName: "photo.on.rectangle").foregroundStyle(.secondary))
                        .frame(width: 52, height: 78)
                }
            }
            .overlay(selectedRing(Wallpaper.filePath(current) != nil))
        }
        .buttonStyle(.plain).help("Choose an image…")
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // Jump straight to the macOS desktop pictures so they're easy to choose.
        panel.directoryURL = URL(fileURLWithPath: "/System/Library/Desktop Pictures")
        if panel.runModal() == .OK, let url = panel.url {
            withAnimation(.snappy(duration: 0.2)) { store.setWallpaper("file:\(url.path)", for: threadID) }
        }
    }
}
