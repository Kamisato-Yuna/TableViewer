# TableViewer 产品网站

发布地址：<https://kamisato-yuna.github.io/TableViewer/>。

原生 HTML、CSS、JavaScript，无运行时框架、第三方字体、分析脚本或外部 API 请求。首页使用仓库真实截图；`assets/app-icon.png` 来源于 Icon Composer 的 `Design/Previews/TableViewer-Default.png` 导出。设计源修改后，运行 `script/export_icons.sh` 并同步该图标。

## 本地预览

在仓库根目录执行：

```sh
gh api repos/Kamisato-Yuna/TableViewer/releases/latest > /tmp/tableviewer-release.json
python3 script/build_site.py --release-json /tmp/tableviewer-release.json
python3 -m http.server 4173 --directory _site --bind 127.0.0.1
```

打开 <http://127.0.0.1:4173>。可使用先前保存的 Release JSON 离线构建。

## 发布与维护

`github-pages` 环境保留仅允许 main 部署的限制。Release 事件来自版本标签，因此先调度 main 上的 Pages 工作流，再由 main 读取最新正式 Release（含 `appcast.xml`）并部署；不直接从版本标签部署，也不扩大环境的分支/标签权限。更新清单和最终 DMG 随 Release 一起上传。

GitHub Pages 使用 Actions 发布，工作流为 `.github/workflows/pages.yml`。网站相关文件或 Studio 示例数据源码推送至 main，正式 Release 发布、编辑、删除，或手动运行工作流时，读取最新正式 Release 并构建。版本号、日期、DMG 大小、下载链接和前三条发布要点直接来自 GitHub；发布要点按纯文本转义，完整说明链接至 Release。未找到正式 arm64 DMG 时停止构建，保留已发布站点。

页面关于最低系统、签名公证与验证环境的说明是明确标记版本的产品文案；后续改变这些信息时同步编辑 `site/index.html`。工作流只上传 `_site` 的网页资产，不发布仓库其他目录。

## 交互与视觉

- Liquid Glass：冷白、浅青与淡紫空间；半透明导航、内侧高光、薄边框和柔和投影。
- 真实截图使用 2880×1800 的系统原始 PNG，提供工作台 / Agent 场景、跟随系统 / 深浅外观切换、放大和原图入口；首屏仅加载当前场景与外观的响应式 WebP；截图不做三维变换，退出大图支持 Esc 并归还焦点。
- 示例数据在构建时从 `ConnectionVault.swift` 的 Studio 建库 SQL 读取，在独立内存 SQLite 中生成；六个字段与十二条初始记录与原生应用一致。示例表格支持当前页全字段筛选、列排序、选择、字段编辑、NULL、保存与撤销，主键只读，未保存修改会阻止切换记录或面板。数据只存在于页面内存中。
- 固定示例查询读取当前已保存记录，支持 ⌘↵；CSV 导出该次查询结果，处理引号和潜在表格公式。这里不提供任意 SQL 编辑/执行，原生应用可自由编辑 SQL / MongoDB JSON 命令。
- Agent 示意区展示操作目的、目标连接、完整查询、确认执行/拒绝、展开本地结果、另行确认发送以及重置；拒绝结果也可单独确认发送，与原生应用一致。没有 AI 调用或数据库连接。
- 分段控件支持方向键、Home、End；动效遵循 `prefers-reduced-motion`；不支持模糊效果时使用实色背景。

测试只覆盖本轮网页、构建和发布改动；原生应用及实际数据库/AI 验收不由网页示意替代。

## 截图与资源维护

当前截图来自 0.5.0（6）最终 Release 应用的独立 PagesQA 副本：只替换 bundle identifier 并重签以隔离沙箱、偏好和 Keychain 命名空间，保留应用源码与原有安全权限。通过 macOS 原生 `screencapture -x -o -l <PagesQA 窗口编号>` 获取 1440×900 pt 的工作窗口，得到 2880×1800 Retina PNG，未锐化、重绘或放大。未操作用户主应用或发布任务的 QA 窗口。

`site/assets/screenshots/` 保存四张原图：Studio 数据表 / 自动估算栏 / 记录详情，以及 Agent Liquid Glass 输入区 / 最近会话时间线，各有深浅两种外观。数据为应用自带 Studio 示例；Agent 是通过应用创建并命名的本地示例会话与**未发送草稿**，未配置 API、未伪造模型回复或执行结果。网页原有交互示意继续与实际截图明确区分。

每张原图生成 768、1440、2880 宽的 WebP。采用 lossless 编码保留文本边缘并携带原图 Display P3 色彩配置；较小尺寸仅作下采样，最大尺寸保持原始像素。生成命令（本机 libwebp `cwebp`，无需运行时依赖）：

```sh
cwebp -lossless -m 6 -metadata icc -resize 768 0 workspace-light.png -o workspace-light-768.webp
cwebp -lossless -m 6 -metadata icc -resize 1440 0 workspace-light.png -o workspace-light-1440.webp
cwebp -lossless -m 6 -metadata icc workspace-light.png -o workspace-light-2880.webp
```

图标缩为 256×256 后以无损 WebP 保存，满足导航和 112 pt 下载图标的 Retina 展示；favicon 使用独立 64×64 PNG，避免浏览器再次以标签页图标请求 256px 图片；`app-icon.png` 保留为设计来源。构建直接复制 `site/assets`，旧 `docs/screenshots` 仍供仓库文档使用，不再作为 Pages 展示来源。

首张图片由 `<picture>` 的 media/source 与 srcset 选择，与系统外观一致；显式选择仅在当前页面有效，选择“跟随系统”可恢复跟随。切换先等待 `decode()`，再复用缓存中的图片元素替换，旧图保持可见，过期选择不覆盖最新选择，失败时保留旧图并允许重试。只在按钮 pointerenter/focus 时预取它对应的一张图；没有整组预加载。弹窗复用当前 WebP，原始 PNG 只在用户点击原图链接时请求。固定宽高比避免图片切换导致布局跳动。外观控制仍仅改变真实应用截图，保留站点原有浅色 Liquid Glass 设计。

验证首屏冷缓存 / 缓存命中、首次与连续切换、系统外观变化与显式选择优先级、快速切换及失败恢复；桌面 1× / 2×、390px / 320px、reduced motion、弹窗 Escape / 焦点归还、原有示例交互、控制台与资源请求。测试只覆盖本轮站点改动。性能采样区分本地与线上，不将不同网络下载耗时计算为严格提升百分比。
