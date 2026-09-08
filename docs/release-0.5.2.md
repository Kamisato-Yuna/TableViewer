# 0.5.2 发布验收

版本 0.5.2（8），关联 [Issue #28](https://github.com/Kamisato-Yuna/TableViewer/issues/28)。精确纳入已验收 GPG 签名提交 `4be2f40c1e83622cfdef0f8754c84e2522b91a57`，同时保留远端 main 的 0.5.1 发布验收与 Pages 更新。0.5.1 标签及附件不变。

## 修复与专项验证

- 统一编辑器辅助按钮与原生菜单的中性色外观、12pt medium 符号和图标槽，运行按钮仍保留突出样式。
- 在代码视口裁剪 NSRuler，避免竖线跨入 SQL 标题和快捷键提示区。
- 多 SQL 结果 Picker 使用枚举结果值，避免历史切换清空数组后，旧子视图继续按 index 读取而越界。
- `test_query_result_picker.sh` 真实 SwiftUI hosting 下选择第二结果并清空数组，30 轮通过。实现任务已用同测试确认 0.5.1 旧源码失败；本发布任务再次运行修复版本通过。
- `test_editor_viewport.sh` 的视口、人工滚动和真实 SwiftUI A/B/A 撤销生命周期通过；632 条双语资源和 8 项更新源测试通过。

## 正式构建与 GUI

Developer ID Release 构建通过，arm64 / 最低 macOS 26，保留 App Sandbox、Hardened Runtime，未包含 get-task-allow。app 与嵌套 Sparkle 深层严格签名验证通过；正式包资源的独立签名沙箱 en / zh-Hans 探针通过。

从正式 Release 包复制并重签独立 `local.yuna.TableViewer.Release052QA`，不重新编译，仅变更测试标识和更新设置以隔离真实连接、容器及 Keychain。实际 GUI 使用 Studio 合成 SQLite：

- 160 行脚本末尾选区 `SELECT 80 AS release_check;` 返回 80。
- 运行两条 SQL 得到 7 / 8，切到第二结果 8，再通过历史菜单恢复长脚本，结果清空且应用不崩溃；继续运行末尾选区仍返回 80。
- 实际重启应用后英文浅色界面和中文深色界面均完成视觉检查。
- 上下及左右分栏截图确认行号竖线止于代码视口；SQL 标题、快捷键提示与辅助控件显示边界正常。视觉检查不等同于逐像素光学尺寸测量。

## 公证与更新签名

app 公证 Accepted：`7fd42bef-4702-4f56-b236-e2c2e0469223`；DMG 公证 Accepted：`da4a679a-2f68-4d17-937f-f9cfa100e377`。两者 staple validate 与 Gatekeeper（Notarized Developer ID）通过。最终 DMG 生成现有 Sparkle Ed25519 清单，版本 0.5.2 / build 8，大小 10,047,857 字节。

## 验收范围

本机 macOS 27 beta、Xcode 27 beta。本轮未重复 macOS 26 真机、外部 PostgreSQL/MongoDB、真实模型供应商或生产客户端自动安装重启全链路；未访问用户真实数据库或调用真实 API。实现任务的输入法组合态、减弱动态、完整 Instruments 帧率和原生分隔线拖拽位置变化未获得专项验收证据，本次不把它们声明为通过。独立 QA 副本的 GUI 证据与发行原包的签名、公证、公开下载证据分别记录。

## 公开发行验证

[PR #29](https://github.com/Kamisato-Yuna/TableViewer/pull/29) 已合并为 `bccfca0b410ca1bcf5b2a48b0ddc3b1cfee3df11`。GPG 签名标签 `v0.5.2` 指向 `7cb16e6a7b81534e05191628fc31cbfad176c88d`；与构建源码一致，构建之后仅补充文档。正式 [Release](https://github.com/Kamisato-Yuna/TableViewer/releases/tag/v0.5.2) 于 2026-09-08 07:44:31 UTC 公开并设为 Latest，附件全部上传后发布；0.5.1 的标签、DMG 和 appcast 均保留。

- 不带认证从公开 GitHub 下载地址获取完整 DMG（HTTP Range 分段下载），10,047,857 字节，与本地正式 DMG 逐字节一致。公开 Release appcast 与本地签名清单一致。
- 下载 DMG 和只读挂载 app 均通过 staple validate、Gatekeeper（Notarized Developer ID）；app 深层严格签名验证通过，其可执行文件与正式构建一致。未安装或替换用户主应用。
- 使用 app 公钥与线上 Pages appcast，验证公开下载 DMG 的 Sparkle Ed25519 签名通过。
- [最终 PR CI](https://github.com/Kamisato-Yuna/TableViewer/actions/runs/34200589993) 和 [合并后 CI](https://github.com/Kamisato-Yuna/TableViewer/actions/runs/34200648811) 的 source / macOS build and tests 均成功。
- [Pages 部署](https://github.com/Kamisato-Yuna/TableViewer/actions/runs/34200864111) 成功；公开产品页面包含 0.5.2 DMG 下载入口，线上 appcast 与 Release 资产逐字节一致，版本为 0.5.2 / build 8。

公开产物和更新源验证不等同于生产客户端自动安装重启全链路，范围限制仍如上所述。
