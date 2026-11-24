import Defaults
import Foundation

struct CustomDockConfig: Codable, Identifiable, Equatable, Defaults.Serializable {
    var id = UUID()
    var name: String
    var isVertical = false
    var iconSize: CGFloat = 48
    var bundleIDs: [String] = []
    var screenID: String?
    var relativeX: CGFloat = 0.5
    var relativeY: CGFloat = 0.3
    var autoHide = false
}

extension CustomDockConfig {
    // Synthesized decoding rejects docks saved before a field existed, so every field falls back to its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        isVertical = try c.decodeIfPresent(Bool.self, forKey: .isVertical) ?? false
        iconSize = try c.decodeIfPresent(CGFloat.self, forKey: .iconSize) ?? 48
        bundleIDs = try c.decodeIfPresent([String].self, forKey: .bundleIDs) ?? []
        screenID = try c.decodeIfPresent(String.self, forKey: .screenID)
        relativeX = try c.decodeIfPresent(CGFloat.self, forKey: .relativeX) ?? 0.5
        relativeY = try c.decodeIfPresent(CGFloat.self, forKey: .relativeY) ?? 0.3
        autoHide = try c.decodeIfPresent(Bool.self, forKey: .autoHide) ?? false
    }
}
