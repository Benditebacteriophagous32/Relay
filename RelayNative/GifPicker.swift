import SwiftUI

// Giphy-backed GIF picker. Trending by default, searchable. Picking returns the
// GIF's mp4 URL (used for encrypted chats — downloaded + sent as media) and its
// gif URL (used for regular chats — sent as an external-media link).

private struct GiphyResponse: Decodable { let data: [GiphyGif] }
struct GiphyGif: Decodable, Identifiable {
    let id: String
    let images: Images
    struct Images: Decodable {
        let fixedWidth: Img
        let original: Img
        enum CodingKeys: String, CodingKey { case fixedWidth = "fixed_width", original }
    }
    struct Img: Decodable { let url: String; let mp4: String? }
}

struct GifPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (_ mp4URL: String, _ gifURL: String) -> Void

    @State private var query = ""
    @State private var gifs: [GiphyGif] = []
    @State private var loading = false
    @FocusState private var focused: Bool

    // Giphy public beta key — fine for personal, low-volume use.
    private let apiKey = "dc6zaTOxFJmzC"
    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 6)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search GIPHY", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 15))
                    .focused($focused)
                    .onSubmit { Task { await load() } }
                if loading { ProgressView().controlSize(.small) }
                Button("Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.vertical, 13)
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(gifs) { gif in
                        Button {
                            onPick(gif.images.original.mp4 ?? gif.images.original.url, gif.images.original.url)
                            dismiss()
                        } label: {
                            AsyncImage(url: URL(string: gif.images.fixedWidth.url)) { phase in
                                if let img = phase.image {
                                    img.resizable().scaledToFill()
                                } else {
                                    Rectangle().fill(.ultraThinMaterial)
                                }
                            }
                            .frame(height: 110)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 560, height: 520)
        .background(.ultraThinMaterial)
        .onAppear { focused = true; Task { await load() } }
        .onChangeCompat(of: query) { _, _ in Task { await debouncedLoad() } }
    }

    private func debouncedLoad() async {
        let snapshot = query
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard snapshot == query else { return }   // a newer keystroke superseded this one
        await load()
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let q = query.trimmingCharacters(in: .whitespaces)
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let endpoint = q.isEmpty
            ? "https://api.giphy.com/v1/gifs/trending?api_key=\(apiKey)&limit=30&rating=pg-13"
            : "https://api.giphy.com/v1/gifs/search?api_key=\(apiKey)&q=\(enc)&limit=30&rating=pg-13"
        guard let url = URL(string: endpoint),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let resp = try? JSONDecoder().decode(GiphyResponse.self, from: data) else { return }
        gifs = resp.data
    }
}
