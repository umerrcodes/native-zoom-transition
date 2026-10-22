import SwiftUI
import UIKit
import Combine

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    private init() {}

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func set(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

@MainActor
final class ImageLoader: ObservableObject {
    @Published var image: UIImage?

    private let url: URL?
    private var task: URLSessionDataTask?

    init(url: URL?) {
        self.url = url
        load()
    }

    deinit {
        task?.cancel()
    }

    private func load() {
        guard let url else { return }

        if let cached = ImageCache.shared.image(for: url) {
            image = cached
            return
        }

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 60)
        task = URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data, let uiImage = UIImage(data: data) else { return }
            ImageCache.shared.set(uiImage, for: url)
            DispatchQueue.main.async {
                self.image = uiImage
            }
        }
        task?.resume()
    }
}

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    @StateObject private var loader: ImageLoader
    private let content: (Image) -> Content
    private let placeholder: Placeholder

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        _loader = StateObject(wrappedValue: ImageLoader(url: url))
        self.content = content
        self.placeholder = placeholder()
    }

    var body: some View {
        if let image = loader.image {
            content(Image(uiImage: image))
        } else {
            placeholder
        }
    }
}
