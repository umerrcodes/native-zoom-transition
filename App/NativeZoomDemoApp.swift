// Open NativeZoomDemo.xcodeproj in Xcode 26+, select an iPhone Simulator, and run.
// iOS 18+. No packages, API keys, downloads, or custom fonts are required.
import SwiftUI
import UIKit

@main
struct NativeZoomDemoApp: App {
    init() {
        for index in 1...2 {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600)).image { context in
                (index == 1 ? UIColor.systemPurple : UIColor.systemIndigo).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
                let label = "IMAGE \(index)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 50),
                    .foregroundColor: UIColor.white
                ]
                let size = label.size(withAttributes: attributes)
                label.draw(at: CGPoint(x: (400 - size.width) / 2, y: 240), withAttributes: attributes)
            }
            ImageCache.shared.set(image, for: URL(string: "https://example.invalid/image\(index).png")!)
        }
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { DemoGallery() }
                    .tabItem { Label("Gallery", systemImage: "square.grid.2x2") }
            }
            .tint(DemoStyle.primary400)
            .preferredColorScheme(.dark)
        }
    }
}

private struct DemoGallery: View {
    @StateObject private var presentation = ZoomPresentationCoordinator()

    private let sampleRows = (1...14).map { index in
        SampleValue(number: index, value: 20, count: 10)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Placeholder images and sample content")
                    .font(.subheadline)
                    .foregroundStyle(DemoStyle.textSecondary)
                ForEach(1...4, id: \.self) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Collection \(section)")
                            .font(.headline)
                            .foregroundStyle(DemoStyle.textPrimary)
                        ForEach(1...4, id: \.self) { offset in
                            let index = (section - 1) * 4 + offset
                            let imageIndex = index.isMultiple(of: 2) ? 2 : 1
                            let url = "https://example.invalid/image\(imageIndex).png"
                            ThumbnailRow(
                                item: PreviewItem(
                                    id: "sample-\(index)",
                                    name: "Sample \(index)",
                                    details: [index.isMultiple(of: 2) ? "Short preview" : "Scrollable preview"],
                                    imgUrl: url,
                                    imageUrls: [url, "https://example.invalid/image\(3 - imageIndex).png"]
                                ),
                                sampleValues: index.isMultiple(of: 2) ? [] : sampleRows,
                                imageURL: URL(string: url),
                                sourceID: "sample-\(index)",
                                presentation: presentation,
                                onTap: {}
                            )
                            if offset < 4 { Divider().overlay(DemoStyle.cardStroke) }
                        }
                    }
                    .padding(16)
                    .background(DemoStyle.cardFill, in: RoundedRectangle(cornerRadius: 24))
                }
            }
            .padding(16)
        }
        .background(DemoStyle.backgroundBottom.ignoresSafeArea())
        .navigationTitle("Native Zoom Demo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .background(ZoomPresentationHost(presentation: presentation))
    }
}

private struct ThumbnailRow: View {
    let item: PreviewItem
    let sampleValues: [SampleValue]?
    let sourceID: String
    let onTap: () -> Void
    let presentation: ZoomPresentationCoordinator

    @StateObject private var imageLoader: ImageLoader

    init(item: PreviewItem, sampleValues: [SampleValue]?, imageURL: URL?, sourceID: String, presentation: ZoomPresentationCoordinator, onTap: @escaping () -> Void) {
        self.item = item
        self.sampleValues = sampleValues
        self.sourceID = sourceID
        self.onTap = onTap
        self.presentation = presentation
        _imageLoader = StateObject(wrappedValue: ImageLoader(url: imageURL))
    }

    var body: some View {
        Button {
            onTap()
            presentation.open(
                item: item,
                sampleValues: sampleValues,
                sourceID: sourceID
            )
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ZoomSourceView(imageLoader: imageLoader, sourceID: sourceID, presentation: presentation)
                    .frame(width: 44, height: 60)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .medium))
                        .lineSpacing(6)
                        .foregroundStyle(DemoStyle.textPrimary)

                    if let muscle = item.details?.first, !muscle.isEmpty {
                        Text(muscle.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.footnote)
                            .foregroundStyle(DemoStyle.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .buttonStyle(RowPressStyle(cornerRadius: 12))
        .accessibilityIdentifier(sourceID)
        .accessibilityHint("Opens item details")
    }

}

struct RowPressStyle: ButtonStyle {
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        configuration.label
            .background(configuration.isPressed ? DemoStyle.white008 : .clear, in: shape)
            .contentShape(shape)
    }
}
