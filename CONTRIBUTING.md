# 参与贡献

谢谢你愿意帮忙。先说清楚项目的边界，省得你白做工。

## 范围

Orbit 正在从「Mac 软件分享」扩展为「截图工具」：菜单栏常驻、全局快捷键、捕获、标注、美化、分享，原有的软件分享作为第二个页签保留。完整的范围、阶段和「不做什么」见 [docs/PRD.md](docs/PRD.md)。

下面这些不在范围内，相关 PR 大概率不会合并：

- 滚动长截图、屏幕录制、GIF、OCR、贴图（第一版不做）
- 统计仪表盘
- 云端上传、在线链接（保持完全本地）

想做范围之外的东西，请先开 Issue 讨论。

## 开发环境

需要完整的 Xcode（见 README）。

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build
swift test
```

改界面后，可以用离屏渲染检查，不用动桌面：

```sh
BIN="$(swift build --show-bin-path)/Orbit"
ORBIT_FLAT=1 "$BIN" --render-check /tmp/orbit-dark                 # 深色
ORBIT_LIGHT=1 ORBIT_FLAT=1 "$BIN" --render-check /tmp/orbit-light  # 浅色
```

深色和浅色模式都要看一遍。

## 提交 PR 前

- `swift build` 和 `swift test` 都要通过。
- 核心逻辑（`OrbitCore`）的改动请带单元测试。
- 界面改动请附截图（深色、浅色各一张），最好说明为什么这样改。
- 一个 PR 只做一件事，保持小而聚焦。
- 提交信息用 [Conventional Commits](https://www.conventionalcommits.org/) 风格：`feat:`、`fix:`、`polish:`、`refactor:`、`docs:`。

## 设计约定

- 不要提交 Glass 图标文件（`Resources/GlassIcons/*.png`、`Design/`），它们受作者许可证限制，已被 git 忽略。需要新图标时，先在 `GlassIcons.symbols` 里给它配一个 SF Symbol。
- 界面扁平、一体化，不加无意义的分割线、描边和渐变装饰；控件（按钮、分段控件、开关）的质感是例外，统一在 `Theme.swift` 里。
- 完整支持系统深色和浅色模式，颜色用 `Theme` 里随系统外观变化的颜色，不要写死。
- 分享图里所有视觉选项默认可调，不要写死。
- 所有数据只在本机处理，不要加任何网络请求。

## 报告问题

请使用 Issue 模板，并写明 macOS 版本。涉及屏幕使用时间读不到的问题，请说明是否已授予完全磁盘访问。

## Localization

The UI is Simplified Chinese (source language) and English; it follows the system language. Chinese text in code is the key:
SwiftUI `Text("…")` and `String(localized: "…")` look it up in `Packaging/Localization/en.lproj/Localizable.strings`,
which `scripts/build-app.sh` copies into the app. Enum raw values that are shown in the UI are looked up through
`LocalizedStringKey(rawValue)`, so they need an entry too (the compiler can't see them).

- Add the English line for every new Chinese string. Use positional specifiers (`%1$@`) when word order differs.
- `scripts/i18n-scan.py` lists Chinese literals the compiler did not extract; `scripts/i18n-check.py <dir>` compares
  extracted keys with the `.strings` file (see the scripts for usage).
- Check the result with `build/Orbit.app/Contents/MacOS/Orbit -AppleLanguages "(en)" --render-check <dir>`.
