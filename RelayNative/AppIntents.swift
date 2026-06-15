import AppIntents
import SwiftUI

// Siri / Shortcuts integration. Intents drive the SAME live session as the UI via
// RelayStore.shared, so "Hey Siri, send a message on Relay" reuses the connected helper.

// MARK: - Conversation entity (a recipient Siri can resolve by name)

struct RelayConversationEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Conversation"
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    static var defaultQuery = RelayConversationQuery()
}

struct RelayConversationQuery: EntityStringQuery {
    // Resolve specific ids back to entities (Shortcuts stores the chosen id).
    @MainActor
    func entities(for identifiers: [String]) async throws -> [RelayConversationEntity] {
        let store = RelayStore.shared
        return store.threads
            .filter { identifiers.contains($0.id) }
            .map { RelayConversationEntity(id: $0.id, name: store.threadTitle($0)) }
    }

    // Match a spoken/typed name to conversations (fuzzy, case-insensitive).
    @MainActor
    func entities(matching string: String) async throws -> [RelayConversationEntity] {
        let store = RelayStore.shared
        return store.threads
            .filter { store.threadTitle($0).localizedCaseInsensitiveContains(string) }
            .prefix(12)
            .map { RelayConversationEntity(id: $0.id, name: store.threadTitle($0)) }
    }

    // Offered as suggestions in the Shortcuts editor (most-recent conversations).
    @MainActor
    func suggestedEntities() async throws -> [RelayConversationEntity] {
        let store = RelayStore.shared
        return store.threads
            .prefix(20)
            .map { RelayConversationEntity(id: $0.id, name: store.threadTitle($0)) }
    }
}

// MARK: - Send a message

struct SendMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Send a Message"
    static var description = IntentDescription("Send a message to one of your Relay conversations.")
    // Don't steal focus: send in the background when Relay is already running.
    static var openAppWhenRun = false

    @Parameter(title: "To") var conversation: RelayConversationEntity
    @Parameter(title: "Message", requestValueDialog: "What do you want to say?") var message: String

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$message) to \(\.$conversation)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = RelayStore.shared
        store.ensureStarted()
        guard await store.waitUntilConnected(timeout: 10) else {
            if store.needsLogin {
                throw AppIntentError.message("Open Relay and sign in first.")
            }
            throw AppIntentError.message("Relay couldn't connect. Try again in a moment.")
        }
        guard store.threads.contains(where: { $0.id == conversation.id }) else {
            throw AppIntentError.message("I couldn't find that conversation.")
        }
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AppIntentError.message("The message was empty.") }
        store.send(thread: conversation.id, text: text)
        return .result(dialog: "Sent to \(conversation.name).")
    }
}

// MARK: - Open a conversation

struct OpenConversationIntent: AppIntent {
    static var title: LocalizedStringResource = "Open a Conversation"
    static var description = IntentDescription("Open a Relay conversation.")
    static var openAppWhenRun = true   // this one shows UI, so bring the app forward

    @Parameter(title: "Conversation") var conversation: RelayConversationEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$conversation)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = RelayStore.shared
        store.ensureStarted()
        store.pendingOpen = conversation.id
        return .result()
    }
}

// A small typed error so failures read as a clean spoken/printed sentence.
enum AppIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case message(String)
    var localizedStringResource: LocalizedStringResource {
        switch self { case .message(let m): return "\(m)" }
    }
}

// MARK: - Siri phrases

struct RelayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendMessageIntent(),
            phrases: [
                "Send a message with \(.applicationName)",
                "Send a \(.applicationName) message",
                "Tell someone on \(.applicationName)",
            ],
            shortTitle: "Send Message",
            systemImageName: "paperplane.fill")
        AppShortcut(
            intent: OpenConversationIntent(),
            phrases: [
                "Open a conversation in \(.applicationName)",
                "Open \(.applicationName)",
            ],
            shortTitle: "Open Conversation",
            systemImageName: "bubble.left.and.bubble.right.fill")
    }
}
