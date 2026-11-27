# Orbit

**一款本地优先的 Mac 截图工具，为分享而生。**

*Orbit is a local-first screenshot tool for macOS — menu-bar app, global shortcuts, every capture saved to a library you own. It can also turn the software you use into a shareable card. Nothing is uploaded.*

## 功能

### 截图（主要功能）

- **四种捕获**：区域、窗口、全屏、延时，外加「重复上一次区域」（⌃⇧R）：一键再截同一块区域，适合反复对比。区域和窗口选择时会冻结屏幕，菜单、悬停状态也能截。
- **菜单栏常驻 + 全局快捷键**：默认 ⌃⇧4 区域、⌃⇧5 窗口、⌃⇧3 全屏、⌃⇧6 延时（避开了系统自带的 ⌘⇧3/4/5），可以自定义。
- **截图库**：**每一张截图都保存**在 `~/Pictures/Orbit`（可改），文件名以 `Orbit` 开头；「截图」页按日期分组展示，可搜索、按方式筛选，点开看大图和详细信息。
- **快速浮窗**：截完后角落出现缩略图，可复制、在 Finder 中显示、分享、删除，也可以直接拖进别的应用。
- 删除走废纸篓；你在 Finder 里自己删文件，截图库会自动同步。

### 标注

点浮窗、截图库或详情页里的「编辑」打开编辑器：

- **箭头、矩形、椭圆、直线、文字**，颜色、粗细、阴影可调；画好后还能选中、拖动、缩放、改样式。
- **序号标记**：每点一下加一个 ①②③，自动编号，删掉一个会自动重新编号。**荧光笔**：半透明盖在文字上。
- **模糊 / 马赛克**：导出时真正抹掉这块区域的像素，无法还原，适合遮挡敏感信息。
- **裁剪**，支持常用比例。
- 无限次撤销、重做。
- 完成时默认**保存为新截图**（`… 已编辑.png`），原图保留；也可以覆盖原图（旧文件进废纸篓，能找回）。

### 美化

编辑器顶部切到「美化」页，把截图放进一张好看的画布：

- **一键预设**：社交媒体（渐变背景、窗口边框）、文档（浅灰底、细阴影）、纯净（透明背景）。
- **背景**：渐变、内置图片、自选图片、纯色或透明；边距、圆角、阴影可调。
- **窗口边框**：无 / macOS 窗口标题栏 / 浏览器地址栏样式（只显示你填的文字，不读取真实网址）。
- **尺寸**：自动，或 1:1、4:5、3:4、16:9、9:16。
- 署名和 Orbit 水印；上次用的样式会记住。
- 在美化页点「完成」，保存为 `… 已美化.png`，原图保留。

更多功能见路线图 [docs/PRD.md](docs/PRD.md)。

### 软件分享

把你在 Mac 上用的软件，做成好看、可以直接分享的图：

- **数据排行**：用真实的使用时长生成排行榜、卡片、年度报告、气泡图。可选年 / 月 / 周。
- **自选软件**：从已安装软件、Dock、终端工具里挑，分组摆放；四种版式：峡湾、玻璃、纸感、极简；还可以给每个软件配一句短评。
- **导出**：2x PNG、剪贴板、系统分享菜单；可复制成文字清单（Markdown，可带话题标签）；尺寸预设含小红书、X、手机壁纸。

## 隐私

- 所有数据只在本机处理，**不上传、不生成在线链接**。
- 除检查更新外，Orbit 不联网。更新检查（Sparkle）只请求一份版本信息，不发送任何使用数据，也不发送系统信息；可以在设置里关掉自动检查。
- 截图需要 **屏幕录制** 权限（首次使用时引导）。Orbit 只在你按下快捷键时截图，截图只保存在你的这台 Mac 上。
- 「数据排行」读取 macOS 的屏幕使用时间数据库（`knowledgeC.db`），需要授予 **完全磁盘访问权限**。不授权也能用：Orbit 会从授权那一刻起，用 `NSWorkspace` 自己记录前台应用。
- 屏幕使用时间只保留约 3 周，Orbit 会把读到的记录存进自己的本地历史库（`~/Library/Application Support/Orbit`），这样才能做年度统计。设置里可以随时清除。
- 「自选软件」不需要任何特殊权限。

## 系统要求

- macOS 14.0 及以上
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
| `Sources/OrbitCore` | 与界面无关的核心：截图库索引与命名、读取屏幕使用时间、本地历史库、统计、气泡排布、Dock 读取、清单文本生成 |
| `Sources/OrbitApp` | SwiftUI 应用：截图（ScreenCaptureKit 捕获、选择覆盖层、全局快捷键、截图库）、分享图编辑器、设置 |
| `Sources/OrbitCLI` | 开发用命令行 `orbit-cli`：导入数据并打印统计、列出 Dock 软件 |
| `Tests/OrbitCoreTests` | 核心层的单元测试 |
| `docs/` | 产品需求文档 |

## 参与贡献

欢迎提 Issue 和 PR，请先看 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

代码以 [MIT](LICENSE) 许可证发布。内置的背景图和品牌 logo 各有各的许可证，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

官方发布的安装包界面用了 Vinz 设计的 Glass 图标。按作者的许可证，这些图标文件不能放进公开仓库，所以从源码构建时界面图标会换成 SF Symbols，功能完全一样。
