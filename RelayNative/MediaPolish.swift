import SwiftUI
import LinkPresentation
import Quartz

// MARK: - Link preview card (rich unfurl, styled to match the glass UI)

struct LinkInfo { var title: String?; var image: NSImage? }

/// Fetches + caches link metadata so each URL is only unfurled once.
actor LinkMetadataCache {
    static let shared = LinkMetadataCache()
    private var cache: [URL: LinkInfo] = [:]

    func info(for url: URL) async -> LinkInfo {
        if let c = cache[url] { return c }
        var info = LinkInfo()
        let provider = LPMetadataProvider()
        provider.shouldFetchSubresources = true
        provider.timeout = 8
        if let md = try? await provider.startFetchingMetadata(for: url) {
            info.title = md.title
            if let imgP = md.imageProvider ?? md.iconProvider {
                info.image = await Self.loadImage(imgP)
            }
        }
        cache[url] = info
        return info
    }

    private static func loadImage(_ p: NSItemProvider) async -> NSImage? {
        guard p.canLoadObject(ofClass: NSImage.self) else { return nil }
        return await withCheckedContinuation { cont in
            p.loadObject(ofClass: NSImage.self) { obj, _ in cont.resume(returning: obj as? NSImage) }
        }
    }
}

/// A compact, clickable preview card for the first link in a message.
struct LinkPreviewCard: View {
    let url: URL
    @State private var info: LinkInfo?
    @State private var loaded = false

    var body: some View {
        Group {
            if let info, (info.title != nil || info.image != nil) {
                Link(destination: url) {
                    HStack(spacing: 0) {
                        if let img = info.image {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 64, height: 64).clipped()
                        } else {
                            Image(systemName: "link").font(.system(size: 18)).foregroundStyle(.secondary)
                                .frame(width: 64, height: 64).background(.ultraThinMaterial)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.title ?? url.host ?? url.absoluteString)
                                .font(.system(size: 12, weight: .semibold)).lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(url.host ?? "").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        Spacer(minLength: 0)
                    }
                    .frame(width: 280, alignment: .leading)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .task(id: url) {
            guard !loaded else { return }
            loaded = true
            let result = await LinkMetadataCache.shared.info(for: url)
            withAnimation(.easeOut(duration: 0.2)) { info = result }
        }
    }
}

// MARK: - Quick Look (spacebar-style preview for local media)

/// Presents a local file in a Quick Look panel; falls back handled by the caller.
final class QuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLook()
    private var items: [NSURL] = []

    /// Returns false if the panel couldn't be shown (caller can fall back to opening the file).
    @discardableResult
    func show(_ url: URL) -> Bool {
        items = [url as NSURL]
        guard let panel = QLPreviewPanel.shared() else { return false }
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int { items.count }
    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem { items[index] }
}
