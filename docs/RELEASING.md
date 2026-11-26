# 发布流程

给维护者看的。发布包是 **Developer ID 签名、Apple 公证、已装订** 的 DMG，同时支持 Apple 芯片和 Intel。

## 一次性准备

1. 一个付费的 Apple Developer 账号，钥匙串里有 **Developer ID Application** 证书。
2. 保存公证凭据（只需一次）：

   ```sh
   xcrun notarytool store-credentials orbit-notary \
     --apple-id <你的 Apple ID> --team-id <团队 ID> --password <App 专用密码>
   ```

3. 用完整的 Xcode：`export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

## 发一个版本

1. 改 `Packaging/VERSION`（营销版本号，如 `0.2.0`）。构建号自动取提交数，每次都会增加。
2. 提交并打 tag：`git tag v0.2.0`。
3. 构建、签名、公证：

   ```sh
   CODESIGN_IDENTITY="<证书名称或它的 SHA-1>" \
   NOTARY_PROFILE=orbit-notary \
   scripts/release.sh
   ```

   证书在钥匙串里有重名时，用 `security find-identity -v -p codesigning` 查出 SHA-1，填 SHA-1。

   脚本会依次：构建通用二进制并用 Hardened Runtime 签名 → 打 DMG 并签名 → 提交公证并等待 → 装订 → 用 `spctl` 校验。校验结果必须是 `accepted` 加 `source=Notarized Developer ID`，否则不要发布。
4. 产物在 `build/release/Orbit-<版本>.dmg`。在 GitHub 上建 Release，上传这个 DMG。

## 本地开发构建

`scripts/build-app.sh debug` 生成只在本机能用的 ad-hoc 签名包，不需要证书。

## 应用图标

源文件是 `Packaging/AppIcon.svg`（和 16 到 64 像素用的简化版 `AppIconSmall.svg`）。改了之后运行 `scripts/make-icon.sh` 重新生成 `Packaging/AppIcon.icns`，需要 Google Chrome。
