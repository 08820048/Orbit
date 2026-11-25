import SwiftUI

/// Something about this Mac that can be turned into a share card ("素材" in the PRD).
/// Adding a new kind of shareable content starts here.
enum ShareSource: String, CaseIterable, Identifiable {
    case usage, gear, stack, wallpaper, image, screenshot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usage: "使用数据"
        case .gear: "我的装备"
        case .stack: "软件栈 / Dock"
        case .wallpaper: "桌面壁纸"
        case .image: "导入图片"
        case .screenshot: "桌面 / 窗口截图"
        }
    }

    var blurb: String {
        switch self {
        case .usage: "应用排行、时长、时段、年度报告"
        case .gear: "机型、芯片、内存、存储、系统版本"
        case .stack: "已装软件分组、Dock、终端工具"
        case .wallpaper: "当前壁纸，加背景与圆角后分享"
        case .image: "导入已有的图片或截图，加背景、圆角、阴影"
        case .screenshot: "在 Orbit 里直接截全屏或单个窗口"
        }
    }

    /// Index into the Glass icon pack.
    var icon: Int {
        switch self {
        case .usage: GI.trend
        case .gear: GI.sliders
        case .stack: GI.layout
        case .wallpaper: GI.background
        case .image: GI.docs
        case .screenshot: GI.eye
        }
    }

    /// The macOS permission this source needs, or nil when it needs none.
    var permission: String? {
        switch self {
        case .usage: "完全磁盘访问"
        case .screenshot: "屏幕录制"
        default: nil
        }
    }

    /// Sources that are built. The rest show as "coming soon" on the home page.
    var isAvailable: Bool {
        switch self {
        case .usage, .stack, .gear: true
        case .wallpaper, .image, .screenshot: false
        }
    }
}
