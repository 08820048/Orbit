# 参与贡献

谢谢你愿意帮忙。先说清楚项目的边界，省得你白做工。

## 范围

Orbit **只做 Mac 软件分享**：把你用的软件做成好看的分享图。下面这些不在范围内，相关 PR 大概率不会合并：

- 统计仪表盘、单个应用的分析页
- 截图、录屏
- 硬件信息、桌面壁纸等和「软件」无关的内容
- 云端上传、在线链接（保持完全本地）

完整的取舍和理由在 [docs/PRD.md](docs/PRD.md) 的「范围边界」一节。想做范围之外的东西，请先开 Issue 讨论。

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
