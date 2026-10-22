import SwiftUI
import UIKit

extension PreviewItem {
    /// A complete ordered pair, or the legacy image. Row thumbnails still use imgUrl.
    var previewImageURLs: [URL] {
        let pair = Array(imageUrls.compactMap(Self.previewImageURL).prefix(2))
        if pair.count == 2 { return pair }
        return imgUrl.flatMap(Self.previewImageURL).map { [$0] } ?? []
    }

    private static func previewImageURL(_ value: String) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}

/// Read-only item information presented with the system's interactive zoom transition.
struct PreviewScreen: View {
    let item: PreviewItem
    let sampleValues: [SampleValue]?
    var onScrollAtTopChange: (Bool) -> Void = { _ in }
    let onClose: () -> Void

    private var values: [SampleValue] {
        (sampleValues ?? [])
            .filter { $0.count != nil || $0.value != nil }
            .sorted { ($0.number ?? Int.max) < ($1.number ?? Int.max) }
    }

    private var details: [String] {
        (item.details ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: " ").capitalized }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        GeometryReader { geometry in
            let heroSize = CGSize(
                width: geometry.size.width,
                height: max(320, min(geometry.size.width * 1.4, geometry.size.height * 0.78))
            )

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ImageCarousel(
                        imageURLs: item.previewImageURLs,
                        itemName: item.name,
                        size: heroSize
                    )
                    .id(item.id)

                    VStack(alignment: .leading, spacing: 20) {
                        informationCard(title: "Name", text: item.name)

                        if !details.isEmpty {
                            informationCard(
                                title: "Details",
                                text: details.joined(separator: ", "),
                                symbol: "target"
                            )
                        }

                        valuesCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // Include the inset so the top is correct with any safe area.
                geometry.contentOffset.y + geometry.contentInsets.top <= 1
            } action: { _, isAtTop in
                onScrollAtTopChange(isAtTop)
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(DemoStyle.backgroundBottom)
        .preferredColorScheme(.dark)
        .overlay(alignment: .topTrailing) {
            PreviewCloseButton(action: onClose)
                .frame(width: 44, height: 44)
                .padding(16)
        }
    }

    private var valuesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .accessibilityHidden(true)
                Text("Sample Values")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(DemoStyle.primary400)

            if values.isEmpty {
                Text("No additional sample values.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DemoStyle.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(values.indices, id: \.self) { index in
                        let row = values[index]
                        if index > 0 {
                            Divider()
                                .overlay(DemoStyle.cardStroke)
                        }

                        HStack(spacing: 12) {
                            Text("Entry \(row.number ?? index + 1)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DemoStyle.textPrimary)
                                .frame(width: 52, alignment: .leading)

                            Spacer(minLength: 0)

                            Text(valueLabel(for: row))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(DemoStyle.textSecondary)

                            Text(row.count.map { "\($0) items" } ?? "— items")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(DemoStyle.textSecondary)
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DemoStyle.cardFill, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(DemoStyle.cardBorderGradient, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func valueLabel(for row: SampleValue) -> String {
        let sampleValue = row.value
        guard let sampleValue else { return "— points" }
        let value = sampleValue.rounded() == sampleValue
            ? String(format: "%.0f", sampleValue)
            : String(format: "%.1f", sampleValue)
        return "\(value) points"
    }

    private func informationCard(title: String, text: String, symbol: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(symbol == nil ? DemoStyle.textSecondary : DemoStyle.primary400)

            Text(text)
                .font(.headline)
                .foregroundStyle(DemoStyle.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(DemoStyle.cardFill, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(DemoStyle.cardBorderGradient, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

private struct PreviewCloseButton: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .close)
        if #available(iOS 26.0, *) {
            var configuration = UIButton.Configuration.glass()
            configuration.image = UIImage(systemName: "xmark")
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            configuration.baseForegroundColor = .label
            configuration.cornerStyle = .capsule
            button.configuration = configuration
        }
        button.accessibilityLabel = "Close item"
        button.accessibilityIdentifier = "close-zoom-preview"
        button.addTarget(context.coordinator, action: #selector(Coordinator.close), for: .primaryActionTriggered)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func close() { action() }
    }
}
