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

GitHub Pages 使用 Actions 发布，工作流为 `.github/workflows/pages.yml`。网站相关文件或 Studio 示例数据源码推送至 main，正式 Release 发布、编辑、删除，或手动运行工作流时，读取最新正式 Release 并构建。版本号、日期、DMG 大小、下载链接和前三条发布要点直接来自 GitHub；发布要点按纯文本转义，完整说明链接至 Release。未找到正式 arm64 DMG 时停止构建，保留已发布站点。

页面关于最低系统、v0.2.0 签名公证与验证环境的说明是明确标记版本的产品文案；后续改变这些信息时同步编辑 `site/index.html`。工作流只上传 `_site` 的网页资产，不发布仓库其他目录。

## 交互与视觉

- Liquid Glass：冷白、浅青与淡紫空间；半透明导航、内侧高光、薄边框和柔和投影。
- 真实截图使用 2880×1800 的系统原始 PNG，提供深浅外观切换、放大和原图入口；截图不做三维变换，退出大图支持 Esc 并归还焦点。
- 示例数据在构建时从 `ConnectionVault.swift` 的 Studio 建库 SQL 读取，在独立内存 SQLite 中生成；六个字段与十二条初始记录与原生应用一致。示例表格支持当前页全字段筛选、列排序、选择、字段编辑、NULL、保存与撤销，主键只读，未保存修改会阻止切换记录或面板。数据只存在于页面内存中。
- 固定示例查询读取当前已保存记录，支持 ⌘↵；CSV 导出该次查询结果，处理引号和潜在表格公式。这里不提供任意 SQL 编辑/执行，原生应用可自由编辑 SQL / MongoDB JSON 命令。
- Agent 示意区展示操作目的、目标连接、完整查询、确认执行/拒绝、展开本地结果、另行确认发送以及重置；拒绝结果也可单独确认发送，与原生应用一致。没有 AI 调用或数据库连接。
- 分段控件支持方向键、Home、End；动效遵循 `prefers-reduced-motion`；不支持模糊效果时使用实色背景。

测试只覆盖本轮网页、构建和发布改动；原生应用及实际数据库/AI 验收不由网页示意替代。

高清深浅截图来自同一发布构建的 Studio 示例窗口（1440×900 pt，2× Retina），通过系统原生窗口截图获取，未进行锐化、放大重采样或重新绘制；截图后恢复应用原外观设置。网页展示的是核心流程子集，完整导航、结构页、MongoDB Extended JSON、真实网络连接与数据库约束执行仍在原生应用中。
