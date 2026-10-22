import SwiftUI

/// The same cached two-image image viewer used by item previews and set logging.
struct ImageCarousel: View {
    let imageURLs: [URL]
    let itemName: String
    let size: CGSize
    var accessibilityIdentifierPrefix = "zoom-preview"

    @State private var selectedImage = 0

    private var hasImagePair: Bool { imageURLs.count == 2 }

    var body: some View {
        ZStack(alignment: .bottom) {
            heroImage(size: size)

            if hasImagePair {
                pagination
            }
        }
        .onChange(of: imageURLs) { _, _ in selectedImage = 0 }
    }

    private func heroImage(size: CGSize) -> some View {
        Group {
            ZStack {
                DemoStyle.backgroundBottom

                if imageURLs.isEmpty {
                    imagePlaceholder
                } else {
                    // Both pages have their own loaders. Preload the second image without
                    // changing the row's image loader or UIKit's zoom source.
                    ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, url in
                        CachedAsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: size.width, height: size.height)
                                .clipped()
                        } placeholder: {
                            imagePlaceholder
                        }
                        .id(url)
                        .frame(width: size.width, height: size.height)
                        .opacity(selectedImage == index ? 1 : 0)
                        .accessibilityHidden(true)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(
                    stops: [
                        .init(color: DemoStyle.backgroundBottom.opacity(0), location: 0),
                        .init(color: DemoStyle.backgroundBottom.opacity(0.05), location: 0.18),
                        .init(color: DemoStyle.backgroundBottom.opacity(0.2), location: 0.4),
                        .init(color: DemoStyle.backgroundBottom.opacity(0.5), location: 0.62),
                        .init(color: DemoStyle.backgroundBottom.opacity(0.84), location: 0.82),
                        .init(color: DemoStyle.backgroundBottom, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: size.height * 0.36)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .onTapGesture(perform: advanceImage)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(hasImagePair ? .isButton : .isImage)
        .accessibilityAction { advanceImage() }
        .accessibilityLabel("\(itemName), item image")
        .accessibilityValue(imageURLs.isEmpty ? "Image unavailable" : "Image \(selectedImage + 1) of \(imageURLs.count)")
        .accessibilityHint(hasImagePair ? "Double tap to show the other image" : "")
        .accessibilityIdentifier("\(accessibilityIdentifierPrefix)-image")
    }

    private var imagePlaceholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 64))
            .foregroundStyle(DemoStyle.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pagination: some View {
        Button(action: advanceImage) {
            HStack(spacing: 8) {
                ForEach(0..<2) { index in
                    Circle()
                        .fill(.white.opacity(selectedImage == index ? 1 : 0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("PreviewItem images")
        .accessibilityValue("Image \(selectedImage + 1) of 2")
        .accessibilityHint("Double tap to show the other image")
        .accessibilityIdentifier("\(accessibilityIdentifierPrefix)-pagination")
    }

    private func advanceImage() {
        guard hasImagePair else { return }
        selectedImage = (selectedImage + 1) % 2
    }
}
