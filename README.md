# Orbit

**把你在 Mac 上用的软件，做成好看、可以直接分享的图。**

*Orbit is a local-first macOS app that turns the software you use into a beautiful, shareable image — a ranking from real usage data, or a hand-picked "my apps" card. Nothing is uploaded.*

## 功能

Orbit 只做一件事：生成「我的 Mac 软件」分享图。

- **数据排行**：用真实的使用时长生成排行榜、卡片、年度报告、气泡图。可选年 / 月 / 周。
- **自选软件**：从已安装软件、Dock、终端工具（Claude Code、Codex CLI 等）里挑，分组摆放。四种版式：峡湾、玻璃、纸感、极简。
- **软件短评**：给每个软件配一句话，说说为什么用它。
- **高度可调**：背景（纯色、渐变、内置图片、自选图片、毛玻璃）、圆角、尺寸（含小红书、X、手机壁纸预设）、署名、水印、标题字体、图标大小。
- **导出**：存为 2x PNG、拷贝到剪贴板、系统分享菜单；还能把软件名复制成文字清单（Markdown 列表，可带话题标签）。

产品定位和范围边界见 [docs/PRD.md](docs/PRD.md)。

## 隐私

- 所有数据只在本机处理，**不上传、不生成在线链接**。
- 除检查更新外，Orbit 不联网。更新检查（Sparkle）只请求一份版本信息，不发送任何使用数据，也不发送系统信息；可以在设置里关掉自动检查。
- 「数据排行」读取 macOS 的屏幕使用时间数据库（`knowledgeC.db`），需要授予 **完全磁盘访问权限**。不授权也能用：Orbit 会从授权那一刻起，用 `NSWorkspace` 自己记录前台应用。
- 屏幕使用时间只保留约 3 周，Orbit 会把读到的记录存进自己的本地历史库（`~/Library/Application Support/Orbit`），这样才能做年度统计。设置里可以随时清除。
- 「自选软件」不需要任何特殊权限。

## 系统要求

- macOS 13.0 及以上
- 从源码构建需要 **完整的 Xcode**（Swift 6 工具链）。只装命令行工具（Command Line Tools）无法编译 SwiftUI 的宏，会报 `external macro implementation ... could not be found`。

## 从源码构建

```sh
git clone https://github.com/08820048/Orbit.git
cd Orbit

# 如果 xcode-select 指向的是 Command Line Tools，先切到 Xcode：
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

swift build            # 编译
swift test             # 跑单元测试
scripts/build-app.sh   # 生成 build/Orbit.app（ad-hoc 签名，仅供本机使用）
```

已签名、已公证的安装包在 [Releases](https://github.com/08820048/Orbit/releases) 下载，应用内会自动检查更新。读取屏幕使用时间需要完全磁盘访问，不符合 Mac App Store 的沙盒要求，所以不上架 App Store。

## 项目结构

| 目录 | 内容 |
| ---- | ---- |
| `Sources/OrbitCore` | 与界面无关的核心：读取屏幕使用时间、本地历史库、统计、气泡排布、Dock 读取、清单文本生成 |
| `Sources/OrbitApp` | SwiftUI 应用：分享图编辑器、卡片渲染、设置、引导 |
| `Sources/OrbitCLI` | 开发用命令行 `orbit-cli`：导入数据并打印统计、列出 Dock 软件 |
| `Tests/OrbitCoreTests` | 核心层的单元测试 |
| `docs/` | 产品需求文档 |

## 参与贡献

欢迎提 Issue 和 PR，请先看 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

代码以 [MIT](LICENSE) 许可证发布。内置的背景图和品牌 logo 各有各的许可证，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

官方发布的安装包界面用了 Vinz 设计的 Glass 图标。按作者的许可证，这些图标文件不能放进公开仓库，所以从源码构建时界面图标会换成 SF Symbols，功能完全一样。
