import Foundation

/// Only the data needed by this standalone preview.
struct PreviewItem: Identifiable {
    let id: String
    let name: String
    let details: [String]?
    let imgUrl: String?
    let imageUrls: [String]
}

struct SampleValue {
    let number: Int?
    let value: Double?
    let count: Int?
}
