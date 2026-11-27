# 官网

`website/` 是官网的源码：Astro 静态站，中文（`/`）和英文（`/en/`）两个页面，部署在 Cloudflare Pages（默认域名 `orbit-mac.pages.dev`，还没有自己的域名）。

## 本地开发

```sh
cd website
npm install
npm run dev        # http://localhost:4321
npm run build      # 输出到 website/dist
```

## 部署

```sh
cd website
npm run deploy     # = astro build && wrangler pages deploy dist --project-name orbit-mac
```

需要先 `wrangler login`。第一次要建项目：`wrangler pages project create orbit-mac --production-branch main`。

## 发新版本时

改 `website/src/site.ts` 里的 `VERSION`，下载按钮指向 `releases/download/v<版本>/Orbit-<版本>.dmg`，所以要在 GitHub Release 上传完 DMG 之后再部署。

## 内容和素材

- 文案都在 `website/src/i18n.ts`（中英各一份），页面结构在 `src/components/Landing.astro`，样式在 `src/styles/global.css`。
- 页面上的产品图是 Orbit 自己渲染的真实界面，不是示意图：

  ```sh
  ORBIT_STORE_PATH=/tmp/site.sqlite ORBIT_SAMPLE_SHOTS=1 ORBIT_SITE_SHOTS=1 ORBIT_FLAT=1 \
    build/Orbit.app/Contents/MacOS/Orbit --render-check /tmp/site                     # 中文
  ... -AppleLanguages "(en)" --render-check /tmp/site-en                                # 英文
  build/Orbit.app/Contents/MacOS/Orbit --beautify-selftest /tmp/site-bf               # 标注 + 美化示例
  ```

  再把需要的图裁剪、转成 JPEG 放进 `website/public/img/`。`ORBIT_SITE_SHOTS=1` 让截图库用自带的风景照做缩略图。
- 分享图（`share.jpg`）和标注示例目前中英文共用同一张。
- 设计稿在 Doop 画布「Orbit · Mac 设计稿 v1」的「官网 · 落地页」页面。
