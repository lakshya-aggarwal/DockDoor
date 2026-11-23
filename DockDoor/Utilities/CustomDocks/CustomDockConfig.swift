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
}
