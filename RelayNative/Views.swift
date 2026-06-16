import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Progressive blur at a scroll edge: content blurs out as it nears the top/bottom, so it
// dissolves under the floating glass chrome instead of overlapping it harshly. The material
// blurs whatever scrolls behind it; the gradient mask fades that blur away from the edge.
struct EdgeBlur: View {
    enum Side { case top, bottom }
    let side: Side
    var height: CGFloat = 96

    var body: some View {
        // A pure edge→clear ramp with NO opaque plateau: the blur is strongest right
        // at the very edge and tapers off smoothly, so it dissolves rather than reading
        // as a frosted "box". The squared ramp keeps the falloff gentle.
        Rectangle()
            .fill(.ultraThinMaterial)
            .frame(height: height)
            .mask(
                LinearGradient(
                    stops: side == .top
                        ? [.init(color: .black,          location: 0.0),
                           .init(color: .black.opacity(0.5), location: 0.5),
                           .init(color: .clear,          location: 1.0)]
                        : [.init(color: .clear,          location: 0.0),
                           .init(color: .black.opacity(0.5), location: 0.5),
                           .init(color: .black,          location: 1.0)],
                    startPoint: .top, endPoint: .bottom)
            )
            .allowsHitTesting(false)
    }
}

// MARK: - Sidebar (conversation list)

struct SidebarView: View {
    @EnvironmentObject var store: RelayStore
    @ObservedObject private var updater = UpdaterModel.shared
    @Binding var selected: String?
    @State private var query = ""
    @State private var showNewGroup = false
    @State private var showSaved = false
    @FocusState private var searchFocused: Bool

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack(alignment: .top) {
            // Conversations scroll BEHIND the floating chrome and refract through the
            // glass search bar.
            Group {
                if searching {
                    SearchResults(query: query, selected: $selected)
                        .padding(.top, 116)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6, pinnedViews: [.sectionHeaders]) {
                            folder("Messages", "inbox")
                            folder("Snoozed", "snoozed")
                            folder("Requests", "requests")
                            folder("Spam", "spam")
                            folder("Archived", "archived")
                        }
                        .padding(.horizontal, 10).padding(.top, 116).padding(.bottom, 12)
                    }
                }
            }

            EdgeBlur(side: .top, height: 116).frame(maxHeight: .infinity, alignment: .top)
            EdgeBlur(side: .bottom, height: 44).frame(maxHeight: .infinity, alignment: .bottom)

            // Floating chrome: title row + a real-glass search bar.
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text("Relay").font(.title2.weight(.bold))
                    Spacer()
                    // A new version is out — one click installs it (shows the changelog first).
                    // Only appears when the silent probe finds a newer build.
                    if updater.updateAvailable {
                        Button { updater.checkForUpdates() } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle.fill").font(.system(size: 11, weight: .bold))
                                Text("Update").font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(updater.latestVersion.map { "Relay \($0) is available — click to install" } ?? "A new version is available — click to install")
                        .transition(.scale.combined(with: .opacity))
                    }
                    Button { showSaved = true } label: {
                        Image(systemName: "bookmark").font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("Saved messages")
                    Button { showNewGroup = true } label: {
                        Image(systemName: "square.and.pencil").font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("New group")
                    Circle().fill(store.connected ? .green : .orange)
                        .frame(width: 8, height: 8)
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: updater.updateAvailable)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                    TextField("Search messages", text: $query)
                        .textFieldStyle(.plain).font(.system(size: 13))
                        .focused($searchFocused)
                    if searching {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(.secondary)
                                .frame(width: 22, height: 22).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .relayGlass(in: Capsule())
                .contentShape(Capsule())
                .onTapGesture { searchFocused = true }   // click anywhere in the bar to type
            }
            .padding(.horizontal, 14).padding(.top, 34)   // clears the traffic lights above
        }
        .background(.ultraThinMaterial)
        .ignoresSafeArea(.container, edges: .top)   // frosted material fills under the titlebar — no band
        .sheet(isPresented: $showNewGroup) { NewGroupSheet() }
        .sheet(isPresented: $showSaved) { SavedMessagesView(selected: $selected) }
    }

    // A folder section — only rendered when it has threads. The inbox shows no header;
    // the filtered folders get a sticky labelled header with a count.
    @ViewBuilder private func folder(_ title: String, _ key: String) -> some View {
        let items = store.threads(in: key)
        if !items.isEmpty {
            Section {
                ForEach(items) { thread in
                    ThreadRow(thread: thread, isSelected: selected == thread.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selected = thread.id
                            }
                        }
                }
            } header: {
                if key != "inbox" {
                    HStack(spacing: 6) {
                        Text(title.uppercased()).font(.system(size: 11, weight: .bold))
                        Text("\(items.count)").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}

private struct ThreadRow: View {
    @EnvironmentObject var store: RelayStore
    let thread: ChatThread
    let isSelected: Bool
    @State private var hovering = false
    @AppStorage("showSeenIndicators") private var showSeen = true

    private var showsUnreadDot: Bool { thread.unread && !thread.muted }

    // The trailing read-status glyph for my last message (mirrors Messenger).
    @ViewBuilder private func seenIndicator(_ status: String) -> some View {
        switch status {
        case "Seen":
            if store.isGroup(thread) {
                // A group has many possible viewers and only one watermark, so we can't
                // attribute it to one face — show a filled accent check instead.
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(store.accent(for: thread.id))
            } else {
                Avatar(url: store.avatarURL(forContact: thread.contactID),
                       title: store.threadTitle(thread), size: 16)
            }
        case "Delivered":
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        default: // Sent
            Image(systemName: "checkmark.circle")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Avatar(url: store.threadAvatar(thread), title: store.threadTitle(thread),
                   online: store.isOnline(thread))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if thread.pinned {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Text(store.threadTitle(thread))
                        .font(.system(size: 14, weight: thread.unread ? .bold : .semibold))
                        .lineLimit(1)
                }
                Text(thread.snippet)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                if showsUnreadDot {
                    let n = store.unreadCount(thread)
                    let tint = store.accent(for: thread.id)
                    if n > 0 {
                        Text(n > 99 ? "99+" : "\(n)")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 18)
                            .background(Capsule().fill(tint))
                    } else {
                        Circle().fill(tint).frame(width: 9, height: 9)
                    }
                } else if showSeen, let status = store.lastOutgoingStatus(thread) {
                    // Messenger-style: my last message's status — their tiny avatar once seen,
                    // a filled check when delivered, an outline check when just sent.
                    seenIndicator(status)
                }
                if thread.muted {
                    Image(systemName: "bell.slash.fill").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 9).padding(.horizontal, 10)
        .background {
            let accent = store.accent(for: thread.id)
            // Selected = tinted accent; hovered (but not selected) = a soft lift, so the row
            // visibly responds to the cursor instead of feeling dead.
            let fill: AnyShapeStyle = isSelected ? AnyShapeStyle(accent.opacity(0.18))
                : (hovering ? AnyShapeStyle(Color.primary.opacity(0.07)) : AnyShapeStyle(Color.clear))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(isSelected ? 0.12 : (hovering ? 0.06 : 0)), lineWidth: 0.5)
                )
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.14)) { hovering = h } }
        .contextMenu {
            Button { store.togglePin(thread.id) } label: {
                Label(thread.pinned ? "Unpin" : "Pin to top", systemImage: thread.pinned ? "pin.slash" : "pin")
            }
            Button { store.mute(thread.id, !thread.muted) } label: {
                Label(thread.muted ? "Unmute" : "Mute", systemImage: thread.muted ? "bell" : "bell.slash")
            }
            if thread.unread {
                Button { store.markRead(thread.id) } label: { Label("Mark as read", systemImage: "envelope.open") }
            } else {
                Button { store.markUnread(thread.id) } label: { Label("Mark as unread", systemImage: "envelope.badge") }
            }
            Divider()
            if store.isSnoozed(thread.id) {
                Button { store.unsnooze(thread.id) } label: { Label("Unsnooze", systemImage: "bell") }
            } else {
                Menu {
                    Button("For 1 hour") { store.snooze(thread.id, until: Date().addingTimeInterval(3600)) }
                    Button("Until this evening") { store.snooze(thread.id, until: Self.todayAt(18)) }
                    Button("Until tomorrow") { store.snooze(thread.id, until: Self.tomorrowAt(9)) }
                    Button("Until next week") { store.snooze(thread.id, until: Date().addingTimeInterval(7 * 86400)) }
                } label: { Label("Snooze", systemImage: "moon.zzz") }
            }
            Divider()
            Button(role: .destructive) { store.deleteConversation(thread.id) } label: {
                Label("Delete conversation", systemImage: "trash")
            }
        }
    }

    // Helpers for snooze presets.
    static func todayAt(_ hour: Int) -> Date {
        let cal = Calendar.current
        let d = cal.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return d > Date() ? d : d.addingTimeInterval(86400)   // if past, roll to tomorrow
    }
    static func tomorrowAt(_ hour: Int) -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

// MARK: - Search results (global, over all history)

private struct SearchResults: View {
    @EnvironmentObject var store: RelayStore
    let query: String
    @Binding var selected: String?
    @State private var messageHits: [Message] = []

    private var threadHits: [ChatThread] {
        store.threads.filter { $0.folder != "hidden"
            && store.threadTitle($0).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if !threadHits.isEmpty {
                    header("Conversations")
                    ForEach(threadHits) { t in
                        Button { open(t.id, message: nil) } label: {
                            HStack(spacing: 10) {
                                Avatar(url: store.threadAvatar(t), title: store.threadTitle(t), size: 30)
                                Text(store.threadTitle(t)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 5).padding(.horizontal, 8).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !messageHits.isEmpty {
                    header("Messages")
                    ForEach(messageHits) { m in
                        Button { open(m.thread, message: m.id) } label: { MessageHitRow(message: m) }
                            .buttonStyle(.plain)
                    }
                }
                if threadHits.isEmpty && messageHits.isEmpty {
                    Text("No results for “\(query)”")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 36)
                }
            }
            .padding(.horizontal, 10).padding(.bottom, 12)
        }
        .onAppear { messageHits = store.search(query) }
        .onChangeCompat(of: query) { _, q in messageHits = store.search(q) }
    }

    private func open(_ thread: String, message: String?) {
        store.scrollTarget = message
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selected = thread }
    }

    private func header(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 2)
    }

    private struct MessageHitRow: View {
        @EnvironmentObject var store: RelayStore
        let message: Message
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(store.threadTitle(forID: message.thread))
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text(RelayFmt.cluster(message.ts)).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Text((message.sender == store.selfID ? "You: " : "") + message.text)
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6).padding(.horizontal, 8).contentShape(Rectangle())
        }
    }
}

// MARK: - Thread (messages + composer)

struct ThreadView: View {
    @EnvironmentObject var store: RelayStore
    let thread: ChatThread
    @State private var draft = ""
    @State private var savedDraft = ""        // stashed draft while editing a sent message
    @State private var showInfo = false
    @State private var viewerMessage: Message?
    @State private var forwarding: Message?
    @State private var replyingTo: Message?
    @State private var editing: Message?
    @State private var appeared = false        // drives the per-bubble entrance cascade
    @State private var dropTargeted = false    // a file is being dragged over the conversation
    @State private var atBottom = true         // is the scroll view pinned to the latest message?
    @State private var newWhileAway = 0        // messages that arrived while scrolled up
    @State private var inChatSearch = false     // in-conversation search bar shown
    @State private var chatQuery = ""
    @State private var matches: [Message] = []  // search hits, newest first
    @State private var matchIdx = 0
    @FocusState private var chatSearchFocused: Bool

    private var messages: [Message] { store.messagesByThread[thread.id] ?? [] }
    // Memoized row model. Rebuilt ONLY when the thread's messages actually change (via the
    // store's cheap revision signal) — not on every unrelated re-render (hover, typing,
    // presence). Recomputing this over the whole array each render was the long-chat stutter.
    @State private var rows: [ChatRow] = []
    private func rebuildRows() { rows = ChatRow.build(messages) }

    // Receipts only on my TRAILING block of messages (the ones after their last message).
    // Once they reply, that reply already implies "seen", so older blocks show nothing.
    // Within the trailing block, show the label only where the status changes — so
    // 4 seen + 1 delivered shows "Seen" under #4 and "Delivered" under #5.
    private var receiptByMessage: [String: String] {
        let msgs = messages
        let start = (msgs.lastIndex { $0.sender != store.selfID && !$0.system } ?? -1) + 1
        guard start < msgs.count else { return [:] }   // they sent last → no receipts at all
        let trailing = msgs[start...].filter { $0.sender == store.selfID && !$0.system }
        var out: [String: String] = [:]
        for (i, m) in trailing.enumerated() {
            let status = store.receiptStatus(for: m, in: thread.id)
            let next = i + 1 < trailing.count ? trailing[i + 1] : nil
            let sameAhead = next.map { store.receiptStatus(for: $0, in: thread.id) == status } ?? false
            if !sameAhead { out[m.id] = status }
        }
        return out
    }

    // Entrance direction per row: my bubbles glide in from the right, theirs from the left.
    private func rowDx(_ row: ChatRow) -> CGFloat {
        if case .message(let m, _, _) = row, !m.system { return m.sender == store.selfID ? 46 : -46 }
        return 0
    }

    @ViewBuilder private func rowView(_ row: ChatRow) -> some View {
        switch row {
        case .time(let label, _):
            TimeSeparator(label: label)
        case .message(let msg, let first, let last):
            if msg.system {
                Text(msg.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .trailing, spacing: 1) {
                    Bubble(message: msg, isMine: msg.sender == store.selfID,
                           senderName: store.displayName(msg.sender, in: thread.id),
                           showSender: store.isGroup(thread), first: first, last: last,
                           onOpenMedia: {
                               if msg.isInlineImage { viewerMessage = msg }
                               else { store.openMediaFile(msg) }
                           },
                           onForward: { forwarding = msg },
                           onReply: { withAnimation(.smooth(duration: 0.25)) { replyingTo = msg } },
                           onEdit: { editing = msg; savedDraft = draft; draft = msg.text })
                    if let status = receiptByMessage[msg.id] {
                        Text(status)
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                            .padding(.trailing, 6)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                // Extra air before the first bubble of a new cluster; tight within a cluster.
                .padding(.top, first ? 6 : 0)
            }
        }
    }

    private var subtitle: String {
        if store.isGroup(thread) { return "\(store.members(of: thread).count) members" }
        return store.statusLine(thread) ?? "Tap to open profile"
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie, .audio, .pdf, .data, .item]
        panel.allowsMultipleSelection = true   // attach several at once
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            store.stageImages(panel.urls)   // stage them so a caption can be added before sending
        }
    }

    // Scroll to the latest message and clear the away/unread state.
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if !store.atLiveEdge.contains(thread.id) { store.reloadWindow(thread.id) }
        withAnimation(RelayStore.sendSpring) { proxy.scrollTo("bottomSpacer", anchor: .bottom) }
        atBottom = true
        newWhileAway = 0
    }

    // The floating jump-to-bottom button (with a "N new" badge when messages arrived
    // while scrolled up). Extracted so ThreadView's body stays cheap to type-check.
    @ViewBuilder private func jumpPill(_ proxy: ScrollViewProxy) -> some View {
        if !atBottom {
            let unread = newWhileAway > 0
            Button { scrollToBottom(proxy) } label: {
                HStack(spacing: 6) {
                    if unread {
                        Text(newWhileAway > 99 ? "99+" : "\(newWhileAway) new")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(unread ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .padding(.horizontal, unread ? 13 : 10).frame(minHeight: 32)
                .background(jumpPillBackground(unread))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 84)   // float just above the composer
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }

    @ViewBuilder private func jumpPillBackground(_ unread: Bool) -> some View {
        if unread {
            Capsule().fill(store.accent(for: thread.id))
        } else {
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    // Jump to a specific message (when opened from search), then clear the target.
    private func jumpToTarget(_ proxy: ScrollViewProxy) {
        guard let target = store.scrollTarget, messages.contains(where: { $0.id == target }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(target, anchor: .center) }
            store.scrollTarget = nil
        }
    }


    var body: some View {
        // Header + composer both float as glass; messages scroll behind them and refract.
        ScrollViewReader { proxy in
              ScrollView {
                LazyVStack(spacing: 2) {
                    if !messages.isEmpty {
                        Button { store.loadEarlier(thread.id) } label: {
                            Label("Load earlier messages", systemImage: "arrow.up")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 6).padding(.horizontal, 14)
                                .background(Capsule().fill(.ultraThinMaterial))
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        rowView(row)
                            .id(row.id)
                            // Staggered entrance: the bottom-most (visible) rows lead, each
                            // springing in from its side with a small delay → a fluid cascade.
                            .modifier(CascadeIn(appeared: appeared,
                                                delay: Double(min(rows.count - 1 - idx, 12)) * 0.03,
                                                dx: rowDx(row)))
                            // A single newly sent/received bubble glides up from its sender's
                            // side, scaling and fading in — the fluid live insertion.
                            .transition(.asymmetric(
                                insertion: .modifier(
                                    active: BubbleInsert(dx: rowDx(row), active: true),
                                    identity: BubbleInsert(dx: rowDx(row), active: false)),
                                removal: .opacity.combined(with: .scale(scale: 0.9))))
                    }
                    // Live typing indicator, sitting just under the last message.
                    if store.typingByThread[thread.id] == true {
                        TypingDots().padding(.top, 2)
                    }
                    // Clearance below the last message so it rests ABOVE the floating
                    // composer (we scroll to this, not the message, so it never hides behind it).
                    // Reaching the bottom of a slid-up window reloads the live (latest) window.
                    Color.clear.frame(height: 86).id("bottomSpacer")
                        .onAppear {
                            if !store.atLiveEdge.contains(thread.id) {
                                store.reloadWindow(thread.id)
                                DispatchQueue.main.async {
                                    withAnimation(.none) { proxy.scrollTo("bottomSpacer", anchor: .bottom) }
                                }
                            }
                        }
                }
                // Only a new bottom message (last id changes) animates its insertion;
                // prepending older history (last id unchanged) stays still. Same spring as
                // the scroll below, so the bubble and the scroll move as one motion.
                .animation(RelayStore.sendSpring, value: rows.last?.id)
                .padding(.horizontal, 16).padding(.top, 76)
              }
              .defaultBottomAnchorCompat()
              // Track how far the latest message is from the visible bottom, so we know
              // whether to auto-follow new messages or show the jump-to-bottom pill.
              // (macOS 15+; on Ventura atBottom stays true and the pill is simply absent.)
              .onScrollAtBottomChange { nowAtBottom in
                  if nowAtBottom != atBottom { atBottom = nowAtBottom }
                  if nowAtBottom, newWhileAway != 0 { newWhileAway = 0 }
              }
              .onAppear {
                  // On macOS 14+ defaultScrollAnchor(.bottom) handles the initial position;
                  // on Ventura we scroll to the latest message ourselves.
                  if store.scrollTarget != nil { jumpToTarget(proxy) }
                  else { DispatchQueue.main.async { proxy.scrollTo("bottomSpacer", anchor: .bottom) } }
              }
              .onChangeCompat(of: store.scrollTarget) { _, _ in jumpToTarget(proxy) }
              // A newly sent/received message → follow it ONLY if we're already at the bottom
              // (or it's my own send); otherwise count it for the jump-to-bottom pill so the
              // user reading older messages isn't yanked away.
              .onChangeCompat(of: messages.last?.id) { _, last in
                  guard last != nil else { return }
                  let mine = messages.last?.sender == store.selfID
                  if atBottom || mine {
                      DispatchQueue.main.async { scrollToBottom(proxy) }
                  } else if messages.last?.system == false {
                      newWhileAway += 1
                  }
              }
              // Jump-to-bottom pill: appears when scrolled up, badges unread arrivals.
              // Animations are scoped to the pill so a transient atBottom flip during an
              // insertion can't ripple a spring through the whole message list.
              .overlay(alignment: .bottom) {
                  jumpPill(proxy)
                      .animation(.spring(response: 0.3, dampingFraction: 0.8), value: atBottom)
                      .animation(.spring(response: 0.3, dampingFraction: 0.8), value: newWhileAway)
              }
            }
        // Progressive blur at both edges (under the chrome) so messages dissolve into it.
        .overlay(alignment: .top) { EdgeBlur(side: .top, height: 92) }
        .overlay(alignment: .bottom) { EdgeBlur(side: .bottom, height: 70) }
        .overlay(alignment: .top) { header }
        // The composer floats over the messages, so they scroll behind its glass.
        .overlay(alignment: .bottom) {
            Composer(draft: $draft, replyingTo: $replyingTo, editing: $editing, onSend: {
                if let e = editing {
                    store.editMessage(e, newText: draft)
                    editing = nil
                    draft = savedDraft
                } else if !store.stagedImages.isEmpty {
                    store.sendStaged(thread: thread.id, caption: draft)
                    draft = ""
                } else {
                    store.send(thread: thread.id, text: draft, replyTo: replyingTo)
                    draft = ""
                }
                replyingTo = nil
            }, onAttach: { pickImage() }, onVoice: { url in
                store.sendMedia(thread: thread.id, fileURL: url, caption: "")
            }, onCancelEdit: {
                editing = nil
                draft = savedDraft
            }, thread: thread.id)
        }
        .onAppear {
            draft = store.draftsByThread[thread.id] ?? ""
            rebuildRows()     // build the row model once for this thread
            appeared = true   // kick off the entrance cascade
        }
        // Rebuild rows only when messages truly change (O(1) signal) — not on every render.
        // An invisible id-swap (optimistic → real) rebuilds WITHOUT animation, so a freshly
        // sent bubble doesn't glide in a second time when the send is acked.
        .onChangeCompat(of: store.messagesRevision) { _, _ in
            if store.silentSwap {
                store.silentSwap = false
                var tx = Transaction(); tx.disablesAnimations = true
                withTransaction(tx) { rebuildRows() }
            } else {
                rebuildRows()
            }
        }
        .onChangeCompat(of: draft) { _, v in if editing == nil { store.updateDraft(v, for: thread.id) } }
        .background(ConversationBackground(wallpaper: store.wallpaper(for: thread.id)).ignoresSafeArea())
        // Drag any file onto the conversation to send it.
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { store.sendMedia(thread: thread.id, fileURL: url) }
                }
            }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .background(Color.accentColor.opacity(0.06))
                    .overlay {
                        Label("Drop to send", systemImage: "paperplane.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(10).allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: dropTargeted)
        .sheet(isPresented: $showInfo) { ThreadInfoView(thread: thread) }
        .sheet(item: $forwarding) { msg in ForwardPicker(message: msg) }
        // Click a picture to view it full-size.
        .overlay {
            if let m = viewerMessage {
                MediaViewer(message: m) { viewerMessage = nil }
            }
        }
    }

    private var header: some View {
        Group {
            if inChatSearch { searchBar } else { normalHeader }
        }
        .padding(.horizontal, 14).padding(.top, 12)   // sits below the titlebar safe area
    }

    private var normalHeader: some View {
        HStack(spacing: 8) {
            Button {
                if store.isGroup(thread) { showInfo = true } else { store.openFacebookProfile(thread.contactID) }
            } label: {
                HStack(spacing: 9) {
                    Avatar(url: store.threadAvatar(thread), title: store.threadTitle(thread),
                           size: 30, online: store.isOnline(thread))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.threadTitle(thread)).font(.system(size: 13.5, weight: .semibold))
                        Text(subtitle).font(.system(size: 10))
                            .foregroundStyle(store.statusLine(thread) == "typing…" ? Color.accentColor : .secondary)
                    }
                }
                .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 6)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .relayGlass(in: Capsule(), interactive: true)

            Spacer()

            Button { openChatSearch() } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                    .frame(width: 38, height: 38).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .relayGlass(in: Circle(), interactive: true)
            .help("Search this conversation")

            Button { showInfo = true } label: {
                Image(systemName: "info")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())   // whole circle is clickable, not just the glyph
            }
            .buttonStyle(.plain)
            .relayGlass(in: Circle(), interactive: true)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(.secondary)
            TextField("Search this conversation", text: $chatQuery)
                .textFieldStyle(.plain).font(.system(size: 13))
                .focused($chatSearchFocused)
                .onChangeCompat(of: chatQuery) { _, _ in runChatSearch() }
                .onSubmit { stepMatch(1) }
            if !chatQuery.isEmpty {
                Text(matches.isEmpty ? "0" : "\(matchIdx + 1)/\(matches.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button { stepMatch(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(matches.isEmpty)
            Button { stepMatch(1) } label: { Image(systemName: "chevron.down") }
                .disabled(matches.isEmpty)
            Button("Done") { closeChatSearch() }
        }
        .buttonStyle(.plain).font(.system(size: 13))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .relayGlass(in: Capsule())
    }

    private func openChatSearch() {
        withAnimation(.smooth(duration: 0.2)) { inChatSearch = true }
        chatSearchFocused = true
    }
    private func closeChatSearch() {
        withAnimation(.smooth(duration: 0.2)) { inChatSearch = false }
        chatQuery = ""; matches = []; matchIdx = 0
        store.searchHighlight = nil
        store.reloadWindow(thread.id)   // drop any old context windows search paged in
    }
    private func runChatSearch() {
        let q = chatQuery.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { matches = []; return }
        matches = store.searchInThread(thread.id, q)
        matchIdx = 0
        if let m = matches.first { store.focusMessage(m) }
    }
    private func stepMatch(_ d: Int) {
        guard !matches.isEmpty else { return }
        matchIdx = (matchIdx + d + matches.count) % matches.count
        store.focusMessage(matches[matchIdx])
    }
}

// Staggered entrance for message rows: spring in from the side + rise + fade. Inert for
// rows added after the view has appeared (live messages), which keep their own transition.
private struct CascadeIn: ViewModifier {
    let appeared: Bool
    let delay: Double
    let dx: CGFloat
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(x: appeared ? 0 : dx, y: appeared ? 0 : 14)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay), value: appeared)
    }
}

// Live-insertion transition for a single new bubble: it rises from below, scales up from
// its sender's side, and fades in — paired with the scroll spring it reads as one fluid glide.
private struct BubbleInsert: ViewModifier {
    let dx: CGFloat
    let active: Bool
    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            // Grow up from the composer: small + low, scaling open from its bottom edge so it
            // reads as launching out of the input rather than just fading into place.
            .scaleEffect(active ? 0.7 : 1, anchor: .bottom)
            .offset(x: active ? dx * 0.32 : 0, y: active ? 34 : 0)
    }
}

private struct TimeSeparator: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Capsule().fill(.ultraThinMaterial))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

// Clean bubble surfaces (no gloss): sent = flat accent, received = a quiet frosted
// material with a hairline edge. The real Liquid Glass lives on the composer.
private struct BubbleBG: ViewModifier {
    let isMine: Bool
    var accent: Color = .accentColor
    var first: Bool = true
    var last: Bool = true
    func body(content: Content) -> some View {
        // Within a same-sender cluster, square the corners that touch a neighbouring bubble
        // (on the sender's own side) so the run reads as one connected block, Messenger-style.
        let big: CGFloat = 18, small: CGFloat = 5
        let shape: UnevenRoundedRectangle
        if isMine {
            shape = UnevenRoundedRectangle(
                topLeadingRadius: big, bottomLeadingRadius: big,
                bottomTrailingRadius: last ? big : small, topTrailingRadius: first ? big : small,
                style: .continuous)
        } else {
            shape = UnevenRoundedRectangle(
                topLeadingRadius: first ? big : small, bottomLeadingRadius: last ? big : small,
                bottomTrailingRadius: big, topTrailingRadius: big,
                style: .continuous)
        }
        return content.background {
            shape.fill(isMine ? AnyShapeStyle(accent) : AnyShapeStyle(.ultraThinMaterial))
                .overlay(shape.strokeBorder(.white.opacity(isMine ? 0 : 0.10), lineWidth: 0.5))
        }
    }
}

private struct Bubble: View {
    @EnvironmentObject var store: RelayStore
    let message: Message
    let isMine: Bool
    let senderName: String
    let showSender: Bool
    var first: Bool = true     // first bubble of a same-sender cluster
    var last: Bool = true      // last bubble of a same-sender cluster
    var onOpenMedia: () -> Void = {}
    var onForward: () -> Void = {}
    var onReply: () -> Void = {}
    var onEdit: () -> Void = {}

    @State private var picking = false       // the emoji row is expanded
    @State private var hideWork: DispatchWorkItem?

    static let quickReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    // Only ONE message shows its pill at a time (tracked in the store), so the affordance
    // can never bleed onto a neighbouring message. A grace delay bridges the gap between
    // the bubble and the floating pill so it never flickers while the cursor is on either.
    // Stay visible while the emoji bar is open, even if the cursor briefly strays over a
    // neighbouring row on its way to the floating bar — that stray used to steal the global
    // hover and make the picker flicker shut. `picking` pins it open until you pick, toggle
    // it closed, or leave for the (longer) grace below.
    private var showActions: Bool { store.hoverMessage == message.id || picking }

    private func keepOpen() {
        hideWork?.cancel()
        if store.hoverMessage != message.id {
            withAnimation(.smooth(duration: 0.16)) { store.hoverMessage = message.id }
        }
    }
    private func scheduleHide() {
        hideWork?.cancel()
        let id = message.id
        // While actively picking a reaction, give a long grace so the bar doesn't vanish
        // mid-travel as the cursor leaves the bubble to reach the floating emoji row.
        let delay = picking ? 0.9 : 0.22
        let w = DispatchWorkItem {
            if store.hoverMessage == id { withAnimation(.smooth(duration: 0.16)) { store.hoverMessage = nil } }
            withAnimation(.smooth(duration: 0.16)) { picking = false }
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    // A real caption to show under a picture (vs. the bare "📷 Photo" placeholder).
    private var caption: String? {
        guard message.hasMedia else { return nil }
        let t = message.text
        return (t.isEmpty || t == "📷 Photo") ? nil : t
    }

    /// Reactions grouped by emoji with a count, ordered most-reacted first (stable —
    /// dictionary iteration order is otherwise nondeterministic and would flicker).
    private var myReactions: [(emoji: String, count: Int)] {
        guard let r = store.reactions[message.id], !r.isEmpty else { return [] }
        return Dictionary(grouping: r.values, by: { $0 })
            .map { (emoji: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.emoji < $1.emoji }
    }

    // This chat's accent (custom color or the app default) — tints my replies.
    private var accent: Color { store.accent(for: message.thread) }

    var body: some View {
        HStack(spacing: 0) {
            if isMine { Spacer(minLength: 70) }
            bubbleColumn
                // The pill is an OVERLAY in the gutter → it never takes width from the
                // bubble, so a one-line message can't reflow to two lines on hover.
                .overlay(alignment: isMine ? .leading : .trailing) { affordance }
                // Flash a highlight when this is the active in-chat search hit.
                .overlay {
                    if store.searchHighlight == message.id {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.yellow.opacity(0.9), lineWidth: 2).padding(-3)
                            .transition(.opacity)
                    }
                }
                .zIndex(showActions ? 1 : 0)   // float above neighbouring rows while open
            if !isMine { Spacer(minLength: 70) }
        }
        .contentShape(Rectangle())
        .onHover { h in if h { keepOpen() } else { scheduleHide() } }
        // Double-click anywhere on the row to reply (Messenger-style), without opening menus.
        .onTapGesture(count: 2) { onReply() }
    }

    private var bubbleColumn: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
            if showSender && !isMine && first {
                Text(senderName).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary).padding(.leading, 6)
            }
            if let q = message.replyToText, !q.isEmpty {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(.secondary).frame(width: 3, height: 24)
                    Text(q).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial))
                .padding(isMine ? .trailing : .leading, 4)
            }
            content
            HStack(spacing: 5) {
                if store.isStarred(message.id) {
                    Image(systemName: "bookmark.fill").font(.system(size: 9)).foregroundStyle(.orange)
                }
                if store.editedMessages.contains(message.id) {
                    Text("edited").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            .padding(isMine ? .trailing : .leading, 6)
            if !myReactions.isEmpty {
                Text(myReactions.map { $0.count > 1 ? "\($0.emoji) \($0.count)" : $0.emoji }.joined(separator: " "))
                    .font(.system(size: 12))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5)))
                    .padding(isMine ? .trailing : .leading, 4)
            }
        }
    }

    // The whole affordance is ONE object: a VStack of the (optional) emoji row above the
    // [😊][•••] pill, bottom-anchored so revealing the emojis grows it UPWARD and the pill
    // never moves out from under the cursor. A single hover region covers the entire thing,
    // so the gap between the buttons can't drop the hover. It floats in the gutter (offset
    // out of the bubble) as an overlay, so it never reflows the message.
    @ViewBuilder private var affordance: some View {
        if showActions {
            // The PILL is the layout anchor (sized to itself, vertically centered on the
            // bubble by the outer overlay). The wide emoji bar is an OVERLAY that floats just
            // above the pill and grows toward the screen centre — rightward for received,
            // leftward for mine — so it can never push the pill or bleed off the window edge
            // (the old edge-anchored bar ran off the left wall on received messages).
            pill
                .overlay(alignment: isMine ? .bottomTrailing : .bottomLeading) {
                    if picking {
                        emojiRow
                            .offset(y: -34)   // clear the pill + a small gap
                            .onHover { h in if h { keepOpen() } else { scheduleHide() } }
                    }
                }
                .offset(x: isMine ? -58 : 58)
                .onHover { h in if h { keepOpen() } else { scheduleHide() } }
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
        }
    }

    private var pill: some View {
        HStack(spacing: 0) {
            Button { withAnimation(.smooth(duration: 0.28)) { picking.toggle() } } label: {
                Image(systemName: "face.smiling").font(.system(size: 14)).frame(width: 30, height: 28)
            }
            .buttonStyle(.plain)
            Menu {
                Button { onReply() } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                Button { onForward() } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
                Button { store.copyText(message) } label: { Label("Copy text", systemImage: "doc.on.doc") }
                Button { store.toggleStar(message.id) } label: {
                    Label(store.isStarred(message.id) ? "Unsave" : "Save", systemImage: store.isStarred(message.id) ? "bookmark.slash" : "bookmark")
                }
                // Translation is macOS 15+ (Apple's Translation framework) — hide these
                // entirely on Ventura/Sonoma so there are no dead menu items.
                if #available(macOS 15.0, *), !message.hasMedia, !message.text.isEmpty {
                    Divider()
                    if store.isTranslated(message.id) {
                        Button { store.removeTranslation(message.id) } label: { Label("Show original", systemImage: "character.bubble") }
                    } else {
                        Button { store.requestTranslation(message.id, message.text) } label: { Label("Translate", systemImage: "character.bubble") }
                    }
                    Button { store.toggleAutoTranslate(message.thread) } label: {
                        Label(store.autoTranslate.contains(message.thread) ? "Stop translating chat" : "Translate whole chat", systemImage: "globe")
                    }
                }
                if isMine {
                    Divider()
                    if !message.hasMedia {
                        Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                    }
                    Button(role: .destructive) { store.unsend(message) } label: { Label("Unsend", systemImage: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14)).frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 3)
        .relayGlass(in: Capsule(), interactive: true)
        .contentShape(Capsule())   // the whole pill is one continuous hit/hover object
    }

    private var emojiRow: some View {
        HStack(spacing: 2) {
            ForEach(Self.quickReactions, id: \.self) { emoji in
                let mine = store.reactions[message.id]?[store.selfID] == emoji
                Button {
                    store.react(messageID: message.id, thread: message.thread, emoji: emoji, fromMe: isMine)
                    withAnimation(.smooth(duration: 0.22)) { picking = false }
                } label: {
                    Text(emoji).font(.system(size: 18))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(mine ? accent.opacity(0.35) : .clear))
                        .scaleEffect(mine ? 1.12 : 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .relayGlass(in: Capsule())
        .contentShape(Capsule())
        .transition(.scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                if message.hasMedia {
                    MessageMedia(message: message)
                        .help(RelayFmt.exact(message.ts))
                        .onTapGesture { onOpenMedia() }
                        .onHover { NSCursor.pointingHand.set(); if !$0 { NSCursor.arrow.set() } }
                    if let cap = caption {
                        Text(RelayFmt.render(cap, mine: isMine))
                            .font(.system(size: 14))
                            .foregroundStyle(isMine ? .white : .primary)
                            .tint(isMine ? .white : accent)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .modifier(BubbleBG(isMine: isMine, accent: accent))
                    }
                } else {
                    VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(RelayFmt.render(message.text, mine: isMine))
                                .tint(isMine ? .white : accent)
                            if let tr = store.translations[message.id] {
                                // A fine line separates the original from its translation.
                                Rectangle().fill((isMine ? Color.white : Color.primary).opacity(0.18))
                                    .frame(height: 0.5)
                                Text(RelayFmt.render(tr, mine: isMine))
                                    .tint(isMine ? .white : accent)
                                    .foregroundStyle(isMine ? .white.opacity(0.9) : .primary.opacity(0.9))
                            }
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(isMine ? .white : .primary)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .modifier(BubbleBG(isMine: isMine, accent: accent, first: first, last: last))
                        .help(RelayFmt.exact(message.ts))   // exact time on hover, like Messenger
                        if let link = RelayFmt.firstLink(message.text) {
                            LinkPreviewCard(url: link)
                        }
                    }
                }
        }
    }
}

// Inline picture / sticker. Local decrypted file (encrypted chats) or CDN url
// (regular chats); shows a spinner while an encrypted image is still downloading.
private struct MessageMedia: View {
    let message: Message
    private var isSticker: Bool { message.kind == "sticker" }

    var body: some View {
        if message.isInlineImage {
            content
                .frame(maxWidth: isSticker ? 150 : 260, maxHeight: isSticker ? 150 : 320)
                .clipShape(RoundedRectangle(cornerRadius: isSticker ? 6 : 16, style: .continuous))
        } else {
            tile   // video / voice note / file → openable tile
        }
    }

    // A tile for non-image media; tap (handled by the parent) opens it in the default app.
    private var tile: some View {
        let ready = message.mediaPath != nil || message.mediaURL != nil
        return HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(.secondary)
            Text(label).font(.system(size: 13, weight: .medium))
            if !ready { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial))
        .opacity(ready ? 1 : 0.6)
    }
    private var icon: String {
        switch message.kind {
        case "video": return "play.rectangle.fill"
        case "audio": return "waveform"
        default: return "doc.fill"
        }
    }
    private var label: String {
        switch message.kind {
        case "video": return "Video"
        case "audio": return "Voice message"
        default: return "File"
        }
    }

    @ViewBuilder private var content: some View {
        if let path = message.mediaPath, let img = NSImage(contentsOfFile: path) {
            Image(nsImage: img).resizable().scaledToFit()
        } else if let s = message.mediaURL, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                if let img = phase.image { img.resizable().scaledToFit() }
                else if phase.error != nil { failed }
                else { loading }
            }
        } else {
            loading   // encrypted image still downloading
        }
    }

    private var loading: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
            ProgressView().controlSize(.small)
        }
        .frame(width: 200, height: 140)
    }
    private var failed: some View {
        Text(message.text.isEmpty ? "📷 Photo" : message.text)
            .font(.system(size: 14)).foregroundStyle(.secondary)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
    }
}

// Full-size image viewer: dim backdrop, click anywhere or press Escape to close.
private struct MediaViewer: View {
    let message: Message
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            image
                .padding(40)
            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)   // Escape
                    .padding(20)
                }
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onClose() }
        .transition(.opacity)
    }

    @ViewBuilder private var image: some View {
        if let path = message.mediaPath, let img = NSImage(contentsOfFile: path) {
            Image(nsImage: img).resizable().scaledToFit()
        } else if let s = message.mediaURL, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                if let img = phase.image { img.resizable().scaledToFit() }
                else { ProgressView().controlSize(.large).tint(.white) }
            }
        }
    }
}

// Pick a conversation to forward a message to.
struct ForwardPicker: View {
    @EnvironmentObject var store: RelayStore
    @Environment(\.dismiss) private var dismiss
    let message: Message
    @State private var query = ""

    private var filtered: [ChatThread] {
        query.isEmpty ? store.threads
            : store.threads.filter { store.threadTitle($0).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Forward to…").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 16).padding(.bottom, 8)
            Divider()
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { t in
                        Button {
                            store.forward(message, to: t.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Avatar(url: store.threadAvatar(t), title: store.threadTitle(t), size: 34)
                                Text(store.threadTitle(t)).font(.system(size: 14, weight: .medium))
                                Spacer()
                            }
                            .padding(.vertical, 6).padding(.horizontal, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 360, height: 460)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Quick switcher (⌘K)

/// Spotlight-style jump-to-conversation. Type to fuzzy-filter, ↑/↓ to move,
/// Enter to open, Esc to dismiss (Esc handled by the app-wide key monitor).
struct QuickSwitcher: View {
    @EnvironmentObject var store: RelayStore
    @Binding var selected: String?
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var highlight = 0
    @FocusState private var focused: Bool

    private var results: [ChatThread] {
        let base = store.threads.filter { $0.folder != "hidden" }
        guard !query.isEmpty else { return Array(base.prefix(25)) }
        return base.filter { store.threadTitle($0).localizedCaseInsensitiveContains(query)
            || $0.snippet.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Jump to conversation…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 16))
                    .focused($focused)
                    .onChangeCompat(of: query) { _, _ in highlight = 0 }
                    .onKeyPressCompat(.upArrow) { move(-1) }
                    .onKeyPressCompat(.downArrow) { move(1) }
                    .onSubmit { if highlight < results.count { choose(results[highlight]) } }
            }
            .padding(.horizontal, 18).padding(.vertical, 15)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { idx, t in
                            row(t, active: idx == highlight)
                                .id(idx)
                                .contentShape(Rectangle())
                                .onTapGesture { choose(t) }
                        }
                    }
                    .padding(8)
                }
                .onChangeCompat(of: highlight) { _, h in withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(h, anchor: .center) } }
            }
        }
        .frame(width: 540, height: 440)
        .background(.ultraThinMaterial)
        .onAppear { focused = true; highlight = 0 }
    }

    private func move(_ d: Int) {
        guard !results.isEmpty else { return }
        highlight = max(0, min(results.count - 1, highlight + d))
    }
    private func choose(_ t: ChatThread) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selected = t.id }
        isPresented = false
    }

    @ViewBuilder private func row(_ t: ChatThread, active: Bool) -> some View {
        HStack(spacing: 12) {
            Avatar(url: store.threadAvatar(t), title: store.threadTitle(t), size: 34,
                   online: store.isOnline(t))
            VStack(alignment: .leading, spacing: 1) {
                Text(store.threadTitle(t)).font(.system(size: 14, weight: .medium)).lineLimit(1)
                if !t.snippet.isEmpty {
                    Text(t.snippet).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if t.folder != "inbox" {
                Text(t.folder.capitalized).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 7).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(active ? Color.accentColor.opacity(0.28) : .clear))
    }
}

// MARK: - Chat rows (messages + day separators)

enum ChatRow: Identifiable {
    case time(label: String, beforeID: String)
    case message(Message, first: Bool, last: Bool)

    var id: String {
        switch self {
        case .time(_, let b): return "time-\(b)"
        case .message(let m, _, _): return m.id
        }
    }

    /// Messenger-style: a centered time header appears only when there's a real gap
    /// between consecutive messages (or at the very start) — not on every message.
    static let gap: TimeInterval = 60 * 60      // 1 hour → insert a time header
    static let groupGap: TimeInterval = 3 * 60  // within 3 min + same sender → one visual cluster

    /// Two messages belong to the same visual cluster if same sender, same system-ness,
    /// and close in time (and no time header sits between them).
    private static func sameGroup(_ a: Message, _ b: Message) -> Bool {
        a.sender == b.sender && a.system == b.system &&
        abs(b.ts - a.ts) / 1000 < groupGap && abs(b.ts - a.ts) / 1000 < gap
    }

    static func build(_ msgs: [Message]) -> [ChatRow] {
        var out: [ChatRow] = []
        for (i, m) in msgs.enumerated() {
            let secs = m.ts / 1000
            let prevMsg = i > 0 ? msgs[i - 1] : nil
            let nextMsg = i + 1 < msgs.count ? msgs[i + 1] : nil
            let timeHeader = prevMsg.map { secs - $0.ts / 1000 >= gap } ?? true
            if timeHeader {
                out.append(.time(label: RelayFmt.cluster(m.ts), beforeID: m.id))
            }
            // First in cluster if a time header precedes it, or the previous message is a
            // different sender / too far back. Last if the next one breaks the cluster.
            let first = timeHeader || prevMsg.map { !sameGroup($0, m) } ?? true
            let last = nextMsg.map { !sameGroup(m, $0) } ?? true
            out.append(.message(m, first: first, last: last))
        }
        return out
    }
}

// MARK: - Thread / group info sheet

struct ThreadInfoView: View {
    @EnvironmentObject var store: RelayStore
    @Environment(\.dismiss) private var dismiss
    let thread: ChatThread

    @State private var name = ""
    @State private var showAddPeople = false
    @State private var confirmLeave = false
    @State private var showExport = false
    @State private var showNickname = false

    private var isGroup: Bool { store.isGroup(thread) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isGroup ? "Group info" : "Contact info").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            ZStack(alignment: .bottomTrailing) {
                Avatar(url: store.threadAvatar(thread), title: store.threadTitle(thread), size: 72)
                if isGroup {
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 22)).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                }
            }
            .padding(.top, 6)
            .onTapGesture { if isGroup { pickGroupPhoto() } }
            .help(isGroup ? "Change group photo" : "")

            // Editable name (groups) — submit to rename. Non-groups show the contact name.
            if isGroup {
                TextField("Group name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .onSubmit { store.renameGroup(thread.id, name) }
                    .padding(.top, 8)
            } else {
                Text(store.threadTitle(thread)).font(.title3.weight(.semibold)).padding(.top, 8)
            }

            if isGroup {
                Text("\(store.members(of: thread).count) members")
                    .font(.callout).foregroundStyle(.secondary).padding(.top, 2).padding(.bottom, 10)
                Button { showAddPeople = true } label: {
                    Label("Add people", systemImage: "person.badge.plus")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)
            }

            Divider()
            // Per-chat accent: tints this conversation's replies, badge, and selection.
            ChatColorSection(threadID: thread.id).padding(.vertical, 12)
            Divider()
            // Per-chat wallpaper.
            WallpaperSection(threadID: thread.id).padding(.vertical, 12)

            if isGroup {
                Divider()
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.members(of: thread), id: \.self) { id in
                            MemberRow(thread: thread, id: id)
                        }
                    }
                    .padding(12)
                }
                Divider()
                infoButton("Export conversation", "square.and.arrow.up") { showExport = true }
                Divider()
                Button(role: .destructive) { confirmLeave = true } label: {
                    Label("Leave group", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.red)
            } else {
                Divider()
                infoButton("Set nickname", "person.text.rectangle") { showNickname = true }
                Divider()
                infoButton("Export conversation", "square.and.arrow.up") { showExport = true }
                Divider()
                infoButton("Open Facebook profile", "arrow.up.right.square") { store.openFacebookProfile(thread.contactID) }
            }
        }
        // Groups need the tall scrollable member list; a contact sheet sizes to its content
        // so there's no big empty void below.
        .frame(width: 400, height: isGroup ? 620 : nil)
        .background(.ultraThinMaterial)
        .onAppear { name = store.threadTitle(thread) }
        .sheet(isPresented: $showAddPeople) { AddPeopleSheet(thread: thread) }
        .sheet(isPresented: $showExport) { ExportConversationSheet(thread: thread).environmentObject(store) }
        .sheet(isPresented: $showNickname) {
            NicknameSheet(thread: thread.id, contactID: thread.contactID,
                          realName: store.name(for: thread.contactID)).environmentObject(store)
        }
        .confirmationDialog("Leave this group?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave group", role: .destructive) { store.leaveGroup(thread.id); dismiss() }
        }
    }

    // A full-width tappable row used for the footer actions.
    @ViewBuilder private func infoButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pickGroupPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            store.setGroupPhoto(thread.id, url)
        }
    }
}

// Pick a per-chat accent color from a curated palette (or any custom color). Stored
// locally; tints this conversation's sent bubbles, unread badge, and selection highlight.
private struct ChatColorSection: View {
    @EnvironmentObject var store: RelayStore
    let threadID: String

    private static let palette: [String] = [
        "#6C63FF", "#0A84FF", "#30B0C7", "#32D74B",
        "#FFD60A", "#FF9F0A", "#FF375F", "#BF5AF2",
    ]

    private var current: String? { store.chatColors[threadID] }
    private var isCustom: Bool {
        guard let c = current else { return false }
        return !Self.palette.contains { $0.caseInsensitiveCompare(c) == .orderedSame }
    }

    private var customBinding: Binding<Color> {
        Binding(get: { store.accent(for: threadID) },
                set: { store.setChatColor(threadID, hex: $0.hexString) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Chat color").font(.system(size: 13, weight: .semibold))
                Spacer()
                if current != nil {
                    Button("Reset") { withAnimation(.snappy(duration: 0.2)) { store.setChatColor(threadID, hex: nil) } }
                        .font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            // Evenly spread across the width (Spacers between), so the row never overflows.
            HStack(spacing: 0) {
                ForEach(Self.palette, id: \.self) { hex in
                    swatch(hex)
                    Spacer(minLength: 0)
                }
                customSwatch
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 4)
    }

    @ViewBuilder private func swatch(_ hex: String) -> some View {
        let selected = current?.caseInsensitiveCompare(hex) == .orderedSame
        Circle()
            .fill(Color(hex: hex) ?? .gray)
            .frame(width: 28, height: 28)
            .overlay(Circle().strokeBorder(.white.opacity(selected ? 0.95 : 0), lineWidth: 2.5))
            .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .scaleEffect(selected ? 1.12 : 1)
            .contentShape(Circle())
            .onTapGesture { withAnimation(.snappy(duration: 0.2)) { store.setChatColor(threadID, hex: hex) } }
    }

    // A round "custom color" button: a rainbow disc with the system color picker layered on
    // top (nearly invisible but fully clickable), so it matches the swatches instead of
    // rendering as a stretched native color well.
    private var customSwatch: some View {
        ZStack {
            Circle().fill(AngularGradient(
                gradient: Gradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red]),
                center: .center))
            ColorPicker("", selection: customBinding, supportsOpacity: false)
                .labelsHidden()
                .opacity(0.02)
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(isCustom ? 0.95 : 0.25), lineWidth: isCustom ? 2.5 : 0.5))
        .scaleEffect(isCustom ? 1.12 : 1)
        .help("Custom color")
    }
}

// Saved/starred messages across every conversation; tap one to jump to it.
private struct SavedMessagesView: View {
    @EnvironmentObject var store: RelayStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Saved").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider()
            let saved = store.savedMessages
            if saved.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bookmark").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text("No saved messages yet").foregroundStyle(.secondary)
                    Text("Save a message from its ••• menu.").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(saved) { m in
                            Button {
                                selected = m.thread
                                store.scrollTarget = m.id
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Avatar(url: store.avatarURL(forContact: m.sender), title: store.name(for: m.sender), size: 34)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(store.name(for: m.sender)).font(.system(size: 13, weight: .semibold))
                                        Text(m.text.isEmpty ? "📎 Attachment" : m.text)
                                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                    Button { store.toggleStar(m.id) } label: {
                                        Image(systemName: "bookmark.fill").font(.system(size: 12)).foregroundStyle(.orange)
                                    }.buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(width: 420, height: 480)
        .background(.ultraThinMaterial)
    }
}

private struct MemberRow: View {
    @EnvironmentObject var store: RelayStore
    let thread: ChatThread
    let id: String

    @State private var showNickname = false
    private var isMe: Bool { id == store.selfID }
    private var isGroup: Bool { store.isGroup(thread) }
    private var admin: Bool { store.isAdmin(thread.id, id) }

    var body: some View {
        HStack(spacing: 12) {
            Avatar(url: store.avatarURL(forContact: id), title: store.displayName(id, in: thread.id), size: 36)
            Text(store.displayName(id, in: thread.id) + (isMe ? " (you)" : ""))
                .font(.system(size: 14, weight: .medium))
            if admin {
                Text("admin").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
            Spacer()
            if !isMe { Image(systemName: "ellipsis").foregroundStyle(.secondary) }
        }
        .padding(.vertical, 7).padding(.horizontal, 10)
        .contentShape(Rectangle())
        .contextMenu {
            Button { showNickname = true } label: { Label("Set nickname", systemImage: "person.text.rectangle") }
            if !isMe {
                Button { store.openFacebookProfile(id) } label: { Label("Open Facebook profile", systemImage: "arrow.up.right.square") }
                if isGroup {
                    Divider()
                    Button { store.setAdmin(thread.id, id, !admin) } label: {
                        Label(admin ? "Remove as admin" : "Make admin", systemImage: admin ? "star.slash" : "star")
                    }
                    Button(role: .destructive) { store.removeMember(thread.id, id) } label: {
                        Label("Remove from group", systemImage: "person.badge.minus")
                    }
                }
            }
        }
        .onTapGesture { if !isMe { store.openFacebookProfile(id) } }
        .sheet(isPresented: $showNickname) {
            NicknameSheet(thread: thread.id, contactID: id, realName: store.name(for: id)).environmentObject(store)
        }
    }
}

// Pick contacts to add to a group.
private struct AddPeopleSheet: View {
    @EnvironmentObject var store: RelayStore
    @Environment(\.dismiss) private var dismiss
    let thread: ChatThread
    @State private var query = ""
    @State private var selected: Set<String> = []

    private var candidates: [Contact] {
        let members = store.participantsByThread[thread.id] ?? []
        return store.contacts.values
            .filter { !members.contains($0.id) && $0.id != store.selfID && !$0.display.isEmpty }
            .filter { query.isEmpty || $0.display.localizedCaseInsensitiveContains(query) }
            .sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add people").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { store.addMembers(thread.id, Array(selected)); dismiss() }
                    .disabled(selected.isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            TextField("Search contacts", text: $query)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 16).padding(.bottom, 8)
            Divider()
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(candidates) { c in
                        Button {
                            if selected.contains(c.id) { selected.remove(c.id) } else { selected.insert(c.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Avatar(url: store.avatarURL(forContact: c.id), title: c.display, size: 32)
                                Text(c.display).font(.system(size: 14, weight: .medium))
                                Spacer()
                                Image(systemName: selected.contains(c.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(c.id) ? Color.accentColor : .secondary)
                            }
                            .padding(.vertical, 6).padding(.horizontal, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 380, height: 480)
        .background(.ultraThinMaterial)
    }
}

// Create a brand-new group: pick contacts + optional name.
private struct NewGroupSheet: View {
    @EnvironmentObject var store: RelayStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var query = ""
    @State private var selected: Set<String> = []

    private var candidates: [Contact] {
        store.contacts.values
            .filter { $0.id != store.selfID && !$0.display.isEmpty }
            .filter { query.isEmpty || $0.display.localizedCaseInsensitiveContains(query) }
            .sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New group").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { store.createGroup(name: name, ids: Array(selected)); dismiss() }
                    .disabled(selected.isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            TextField("Group name (optional)", text: $name)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 16).padding(.bottom, 6)
            TextField("Search contacts", text: $query)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 16).padding(.bottom, 8)
            if !selected.isEmpty {
                Text("\(selected.count) selected").font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.bottom, 4)
            }
            Divider()
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(candidates) { c in
                        Button {
                            if selected.contains(c.id) { selected.remove(c.id) } else { selected.insert(c.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Avatar(url: store.avatarURL(forContact: c.id), title: c.display, size: 32)
                                Text(c.display).font(.system(size: 14, weight: .medium))
                                Spacer()
                                Image(systemName: selected.contains(c.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(c.id) ? Color.accentColor : .secondary)
                            }
                            .padding(.vertical, 6).padding(.horizontal, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 380, height: 520)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Date formatting

enum RelayFmt {
    static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    static let weekdayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    static let dayFull: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .long; f.timeStyle = .none; return f
    }()
    static let exactFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    static func date(_ ts: Double) -> Date { Date(timeIntervalSince1970: ts / 1000) }
    static func time(_ ts: Double) -> String { timeFmt.string(from: date(ts)) }
    static func exact(_ ts: Double) -> String { exactFmt.string(from: date(ts)) }  // hover tooltip

    /// Compact label for a future fire/snooze time: "3:42 PM" today, "Tue 9:00 AM", "Jun 20".
    static func snoozeLabel(_ ts: Double) -> String {
        let d = date(ts)
        if Calendar.current.isDateInToday(d) { return time(ts) }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow " + time(ts) }
        if let days = Calendar.current.dateComponents([.day], from: Date(), to: d).day, days < 7 {
            return weekdayFmt.string(from: d) + " " + time(ts)
        }
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: d)
    }

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    // Rendering markdown + running the link detector is expensive and was happening on every
    // bubble every scroll frame. The output depends only on the raw text, so memoize it.
    // (Main-thread only — SwiftUI bodies — so no locking needed.)
    private static var renderCache: [String: AttributedString] = [:]
    private static var renderOrder: [String] = []

    /// Render a message body with inline markdown (**bold**, _italic_, `code`, ~~strike~~) and
    /// tappable links. `mine` keeps link text white/legible on the accent bubble.
    static func render(_ raw: String, mine: Bool) -> AttributedString {
        if let cached = renderCache[raw] { return cached }
        let result = build(raw)
        renderCache[raw] = result
        renderOrder.append(raw)
        if renderOrder.count > 2000 {            // bound memory: drop the oldest 500
            for key in renderOrder.prefix(500) { renderCache[key] = nil }
            renderOrder.removeFirst(500)
        }
        return result
    }

    private static func build(_ raw: String) -> AttributedString {
        var attr = (try? AttributedString(
            markdown: raw,
            options: .init(allowsExtendedAttributes: true,
                           interpretedSyntax: .inlineOnlyPreservingWhitespace,
                           failurePolicy: .returnPartiallyParsedIfPossible)))
            ?? AttributedString(raw)
        // Auto-link bare URLs that markdown left as plain text.
        let plain = String(attr.characters)
        let full = NSRange(plain.startIndex..., in: plain)
        for m in linkDetector?.matches(in: plain, range: full) ?? [] {
            guard let r = Range(m.range, in: plain), let url = m.url else { continue }
            let lo = attr.index(attr.startIndex, offsetByCharacters: plain.distance(from: plain.startIndex, to: r.lowerBound))
            let hi = attr.index(attr.startIndex, offsetByCharacters: plain.distance(from: plain.startIndex, to: r.upperBound))
            if attr[lo..<hi].link == nil { attr[lo..<hi].link = url }
        }
        return attr
    }

    /// The first http(s) link in a message, for the preview card.
    static func firstLink(_ raw: String) -> URL? {
        let full = NSRange(raw.startIndex..., in: raw)
        for m in linkDetector?.matches(in: raw, range: full) ?? [] {
            if let u = m.url, u.scheme == "http" || u.scheme == "https" { return u }
        }
        return nil
    }

    /// Header above a cluster of messages: just the time today, "Yesterday 3:42 PM",
    /// "Mon 3:42 PM" within a week, else "June 10, 2026 · 3:42 PM".
    static func cluster(_ ts: Double) -> String {
        let d = date(ts)
        let cal = Calendar.current
        let t = timeFmt.string(from: d)
        if cal.isDateInToday(d) { return t }
        if cal.isDateInYesterday(d) { return "Yesterday \(t)" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d),
                                      to: cal.startOfDay(for: Date())).day ?? 99
        if days < 7 { return "\(weekdayFmt.string(from: d)) \(t)" }
        return "\(dayFull.string(from: d)) · \(t)"
    }
}

private struct Composer: View {
    @EnvironmentObject var store: RelayStore
    @Binding var draft: String
    @Binding var replyingTo: Message?
    @Binding var editing: Message?
    let onSend: () -> Void
    let onAttach: () -> Void
    var onVoice: (URL) -> Void = { _ in }
    var onCancelEdit: () -> Void = {}
    var thread: String = ""
    @StateObject private var recorder = VoiceRecorder()
    @FocusState private var inputFocused: Bool
    @AppStorage("enterToSend") private var enterToSend = true
    @State private var showSchedule = false
    @State private var scheduleDate = Date().addingTimeInterval(3600)
    @State private var showEmoji = false

    /// Append an emoji to the draft, keeping the field focused so several can be added.
    private func insertEmoji(_ e: String) {
        draft += e
        inputFocused = true
    }

    private var canSend: Bool {
        !store.stagedImages.isEmpty || !draft.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private static func stagedIcon(for url: URL) -> String {
        switch RelayStore.mediaKind(for: url) {
        case "video": return "play.rectangle.fill"
        case "audio": return "waveform"
        case "image": return "photo.fill"
        default: return "doc.fill"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(store.scheduledFor(thread)) { m in
                scheduledBanner(m)
            }
            if editing != nil {
                banner(icon: "pencil") {
                    Text("Editing message").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                } onClose: { onCancelEdit() }
            }
            if let r = replyingTo {
                banner(icon: "arrowshape.turn.up.left") {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Replying to \(store.displayName(r.sender, in: thread))")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        Text(r.text).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                } onClose: { withAnimation(.smooth(duration: 0.2)) { replyingTo = nil } }
            }
            if !store.stagedImages.isEmpty { stagedBanner(store.stagedImages) }

            if recorder.recording {
                recordingBar
            } else {
                // Separate floating glass controls — the messages scroll behind and
                // refract through them. The container lets the glass blend fluidly.
                GlassBox(spacing: 8) {
                    HStack(spacing: 8) {
                        glassPill { Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary) } action: { onAttach() }
                        glassPill { Image(systemName: "face.smiling").font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.secondary) } action: { showEmoji.toggle() }
                            .popover(isPresented: $showEmoji, arrowEdge: .top) {
                                EmojiGifPicker(onEmoji: { insertEmoji($0) },
                                               onGif: { mp4, gif in
                                                   store.sendGif(thread: thread, mp4URL: mp4, gifURL: gif)
                                                   showEmoji = false
                                               })
                                    .environmentObject(store)
                            }
                        inputPill
                        trailingButton
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 12)
    }

    // A single floating round glass control.
    private func glassPill<L: View>(tint: Color? = nil, @ViewBuilder label: () -> L,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) { label().frame(width: 40, height: 40).contentShape(Circle()) }
            .buttonStyle(.plain)
            .relayGlass(in: Circle(), tint: tint, interactive: true)
    }

    private var inputPill: some View {
        composerField
            .textFieldStyle(.plain)
            .focused($inputFocused)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .relayGlass(in: Capsule())
            .contentShape(Capsule())
            .onTapGesture { inputFocused = true }   // click anywhere in the bar to type
            .modifier(ReturnToSend(enterToSend: enterToSend, canSend: canSend, onSend: onSend))
    }

    // macOS 14+ gets a growing multi-line field (Return handled by onKeyPress). Ventura uses
    // a single-line field where onSubmit fires reliably on Return — so "Return to send" always
    // works there (a multi-line vertical field can swallow Return into a newline on 13).
    @ViewBuilder private var composerField: some View {
        let placeholder = store.stagedImages.isEmpty ? "Message" : "Add a caption…"
        if #available(macOS 14.0, *) {
            TextField(placeholder, text: $draft, axis: .vertical).lineLimit(1...6)
        } else {
            TextField(placeholder, text: $draft)
        }
    }

    @ViewBuilder private var trailingButton: some View {
        if canSend {
            glassPill(tint: .accentColor) {
                Image(systemName: editing != nil ? "checkmark" : "arrow.up")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            } action: { onSend() }
            // Right-click (or the contextual menu) to send later instead.
            .contextMenu {
                if editing == nil && !thread.isEmpty {
                    Button { schedule(at: Date().addingTimeInterval(3600)) } label: { Label("Send in 1 hour", systemImage: "clock") }
                    Button { schedule(at: ThreadRow.todayAt(18)) } label: { Label("Send this evening", systemImage: "sunset") }
                    Button { schedule(at: ThreadRow.tomorrowAt(9)) } label: { Label("Send tomorrow morning", systemImage: "sunrise") }
                    Button { scheduleDate = Date().addingTimeInterval(3600); showSchedule = true } label: { Label("Schedule…", systemImage: "calendar") }
                }
            }
            .popover(isPresented: $showSchedule, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Send later").font(.headline)
                    DatePicker("", selection: $scheduleDate, in: Date()...)
                        .datePickerStyle(.graphical).labelsHidden()
                    HStack {
                        Spacer()
                        Button("Cancel") { showSchedule = false }
                        Button("Schedule") { schedule(at: scheduleDate); showSchedule = false }
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(16).frame(width: 300)
            }
        } else {
            glassPill { Image(systemName: "mic.fill").font(.system(size: 15)).foregroundStyle(.secondary) }
                action: { recorder.start() }
        }
    }

    private func schedule(at date: Date) {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !thread.isEmpty else { return }
        store.scheduleSend(thread: thread, text: t, at: date)
        draft = ""
    }

    private func scheduledBanner(_ m: ScheduledMessage) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge").font(.system(size: 13)).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Scheduled · \(RelayFmt.snoozeLabel(m.fireAt))")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text(m.text).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { store.cancelScheduled(m.id) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.secondary)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .relayGlass(in: Capsule())
    }

    private var recordingBar: some View {
        GlassBox(spacing: 8) {
            HStack(spacing: 8) {
                glassPill { Image(systemName: "trash").font(.system(size: 15)).foregroundStyle(.red) }
                    action: { recorder.cancel() }
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 9, height: 9)
                        .opacity(recorder.elapsed.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.25)
                    let s = Int(recorder.elapsed)
                    Text(String(format: "%d:%02d", s / 60, s % 60))
                        .font(.system(size: 14, weight: .medium).monospacedDigit())
                    Text("Recording…").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .relayGlass(in: Capsule())
                glassPill(tint: .accentColor) {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                } action: { if let u = recorder.stop() { onVoice(u) } }
            }
        }
    }

    @ViewBuilder private func banner<C: View>(icon: String, @ViewBuilder content: () -> C,
                                              onClose: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Color.accentColor)
            content()
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .relayGlass(in: Capsule())
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func stagedBanner(_ urls: [URL]) -> some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(urls, id: \.self) { url in stagedThumb(url) }
                }
                .padding(.vertical, 2)
            }
            Text(urls.count == 1 ? "Add a caption or just send"
                                 : "\(urls.count) attachments — caption goes on the first")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            Spacer(minLength: 0)
            Button { withAnimation(.easeOut(duration: 0.15)) { store.stagedImages = [] } } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.secondary)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Remove all")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .relayGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // One staged attachment: a thumbnail (or type icon) with a remove badge.
    private func stagedThumb(_ url: URL) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if RelayStore.mediaKind(for: url) == "image", let img = NSImage(contentsOf: url) {
                    Image(nsImage: img).resizable().scaledToFill().frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.ultraThinMaterial)
                        .frame(width: 48, height: 48)
                        .overlay(Image(systemName: Self.stagedIcon(for: url)).font(.system(size: 18)).foregroundStyle(.secondary))
                }
            }
            Button { withAnimation(.easeOut(duration: 0.15)) { store.stagedImages.removeAll { $0 == url } } } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                    .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.55))
            }
            .buttonStyle(.plain).padding(2)
        }
    }
}

// MARK: - Avatar

struct Avatar: View {
    let url: URL?
    let title: String
    var size: CGFloat = 38
    var online: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                if let url {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() }
                        else { initials }
                    }
                } else {
                    initials
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))

            if online {
                Circle().fill(Color.green)
                    .frame(width: size * 0.28, height: size * 0.28)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 2))
            }
        }
        .frame(width: size, height: size)
    }

    private var initials: some View {
        Text(String(title.prefix(1)).uppercased())
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}
