import SwiftUI

// Tiered Liquid Glass: real `.glassEffect` on macOS 26 (Tahoe), a frosted-material
// fallback on macOS 13–15 so Relay still looks right on older / Intel Macs. Every
// place that wants glass calls `.relayGlass(...)` / `GlassBox` instead of the raw
// macOS-26-only API, so there's a single availability gate to maintain.
//
// NOTE: callers pass CONCRETE shapes (Capsule(), Circle(), RoundedRectangle(...)).
// The `.capsule` / `.rect(cornerRadius:)` shape shorthands are themselves newer
// API and would break the Ventura build.

extension View {
    /// Glass on 26+, frosted material below. `tint` colors the surface (e.g. the send
    /// button); `interactive` enables the glass's touch response on 26.
    @ViewBuilder
    func relayGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            glassShim(in: shape, tint: tint, interactive: interactive)
        } else {
            background(tint == nil ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(tint!), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(tint == nil ? 0.12 : 0), lineWidth: 0.5))
        }
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private func glassShim<S: InsettableShape>(in shape: S, tint: Color?, interactive: Bool) -> some View {
        switch (tint, interactive) {
        case let (t?, true):  glassEffect(.regular.tint(t).interactive(), in: shape)
        case let (t?, false): glassEffect(.regular.tint(t), in: shape)
        case (nil, true):     glassEffect(.regular.interactive(), in: shape)
        case (nil, false):    glassEffect(.regular, in: shape)
        }
    }
}

/// Return-to-send for the composer. Uses the precise `onKeyPress` handler on macOS 14+
/// (Shift+Return = newline, ⌘+Return sends when "Return to send" is off); on Ventura,
/// where `onKeyPress` doesn't exist, falls back to `onSubmit` (the Send button always works).
struct ReturnToSend: ViewModifier {
    let enterToSend: Bool
    let canSend: Bool
    let onSend: () -> Void
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.onKeyPress { press in
                guard press.key == .return else { return .ignored }
                if press.modifiers.contains(.shift) { return .ignored }   // newline
                if !enterToSend && !press.modifiers.contains(.command) { return .ignored }
                if canSend { onSend() }
                return .handled
            }
        } else {
            content.onSubmit { if canSend { onSend() } }
        }
    }
}

extension View {
    /// `onChange(of:) { old, new in }` works on macOS 14+; on Ventura it maps to the
    /// older single-value `onChange`, passing (new, new) since the old value isn't
    /// available there. Lets every call site keep the two-parameter closure.
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, _ action: @escaping (V, V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            onChange(of: value) { old, new in action(old, new) }
        } else {
            onChange(of: value) { new in action(new, new) }
        }
    }

    /// Hide the unified window-toolbar background (macOS 15+ `.windowToolbar` placement). On
    /// Ventura the continuous-glass window comes from the transparent NSWindow titlebar
    /// (see GlassWindowBackground), so this is just a no-op there.
    @ViewBuilder
    func hideWindowToolbarBackground() -> some View {
        if #available(macOS 15.0, *) {
            toolbarBackground(.hidden, for: .windowToolbar)
        } else {
            self
        }
    }

    /// Anchor a scroll view to the bottom by default (macOS 14+). On Ventura it's a no-op —
    /// ThreadView scrolls to the latest message on appear instead.
    @ViewBuilder
    func defaultBottomAnchorCompat() -> some View {
        if #available(macOS 14.0, *) {
            defaultScrollAnchor(.bottom)
        } else {
            self
        }
    }

    /// Track whether the scroll view is pinned near the bottom (macOS 15+ scroll geometry).
    /// On Ventura it's a no-op — `atBottom` stays true, so new messages always scroll into
    /// view (the jump-to-bottom pill simply doesn't appear).
    @ViewBuilder
    func onScrollAtBottomChange(threshold: CGFloat = 120, _ action: @escaping (Bool) -> Void) -> some View {
        if #available(macOS 15.0, *) {
            onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentSize.height - geo.contentOffset.y - geo.containerSize.height
            } action: { _, distance in action(distance < threshold) }
        } else {
            self
        }
    }

    /// Apply `onKeyPress` for a specific key only where it exists (macOS 14+); a no-op below.
    @ViewBuilder
    func onKeyPressCompat(_ key: KeyEquivalent, perform: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, *) {
            onKeyPress(key) { perform(); return .handled }
        } else {
            self
        }
    }
}

/// `GlassEffectContainer` on 26 (lets adjacent glass blend); a plain passthrough below.
struct GlassBox<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
