import SwiftUI

struct HelpSheet: View {
    @ObservedObject var model: HelperModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How it works").font(.serif(22)).accessibilityAddTraits(.isHeader)
            // Fixed height so the sheet always fits inside the small window; longer translations scroll,
            // with a fade at the bottom edge so the cut-off text reads as "scroll for more".
            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }
                    .scrollIndicators(.visible)
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [Palette.canvas.opacity(0), Palette.canvas], startPoint: .top, endPoint: .bottom)
                            .frame(height: 28).allowsHitTesting(false)
                    }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            HStack {
                Button("Anthropic’s sign-in help ↗") { model.openSupport() }.buttonStyle(LinkButtonStyle()).padding(.leading, -6)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(OutlineButtonStyle()).keyboardShortcut(.cancelAction)
            }
            .padding(.top, 8)
        }
        .padding(20).frame(width: 400, height: 440)
        .background(Palette.canvas)
        .foregroundStyle(Palette.text)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 9) {
            item("What you need", "Claude signed in to Safari, and Claude Desktop opened once, then quit with ⌘Q.")
            VStack(alignment: .leading, spacing: 8) {
                item("If macOS blocks access", "Allow this app in Privacy & Security → Full Disk Access, then reopen it. Only do this if you trust it.")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { accessButtons }
                    VStack(alignment: .leading, spacing: 6) { accessButtons }
                }
            }
            item("The Keychain prompt", "If macOS asks about “Claude Safe Storage,” choose Allow. It may ask twice. Type your password only in that dialog.")
            item("Privacy", "Runs only on this Mac, with no network requests. Reads only Claude’s sign-in cookies; Safari isn’t changed.")
            item("Limits", "Independent utility. Safari’s default profile and one Claude session only.")
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var accessButtons: some View {
        Button("Open Full Disk Access") { model.openAccessSettings() }.buttonStyle(OutlineButtonStyle(height: 26))
        Button("Show app in Finder") { model.revealApp() }.buttonStyle(OutlineButtonStyle(height: 26))
    }

    private func item(_ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.ui(12.5, weight: .semibold))
            Text(detail).font(.ui(12.5)).foregroundStyle(Palette.text2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
