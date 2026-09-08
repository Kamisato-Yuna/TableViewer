# 0.5.0 开发与发布验收

版本：0.5.0（6），关联 [Issue #21](https://github.com/Kamisato-Yuna/TableViewer/issues/21)。

## 本次改动

- 将计划详情约束在固定高度滚动区域，修复展开估算时的窗口布局崩溃。
- 保证 MongoDB explain 内层 find 命令字段在首位，保留 queryPlanner 与扫描提示。
- 自动估算提供全局默认开关和工作区临时显示开关；隐藏后不再发起后续估算，在途结果不会恢复隐藏区域。
- 最近十个脚本下拉入口和全部脚本窗口；Agent 按当前数据库恢复会话，对象概览示例仅创建草稿。
- Liquid Glass 输入区整合审批与 API 设置；悬停显示供应商返回的 token 用量，仅新用户消息改变会话历史排序。
- 独立 NSHostingView 承载侧栏和 Agent 阅读列，由 AppKit 整体移动，避免开合过程中重复折行。保留 Markdown 解析缓存；撤回会触发辅助功能断言的懒布局实验。

## 验证证据

来源工作目录全部 24 个修改/未跟踪文件在本次工作树逐字节一致后开始发布，未复制构建缓存、密钥或用户数据。纳入远程 main 的现有文档更新。所有测试仅覆盖本次改动和既有分发检查。

- 621 条英文与简体中文资源检查、8 项更新清单测试通过。
- Agent Experience（本地合成 HTTP）、Agent 导航与历史排序、token 用量持久化、自动估算隐藏及在途结果、真实专用 MongoDB COLLSCAN/IXSCAN queryPlanner 回归通过。
- Markdown 缓存复用、流式替换和清空通过；该测试耗时不作为动画性能证明。
- Developer ID Release 构建通过；沙箱、Hardened Runtime 保留，未包含 get-task-allow；Sparkle 嵌套代码按现有流程签名，深层严格签名验证通过。
- 正式包资源的独立签名沙箱探针通过 en / zh-Hans 两种语言检查。

源 Debug 真实 GUI 与 Instruments 的测量详见 [侧栏报告](sidebar-performance.md) 和 [脱敏数据](sidebar-animation-measurements.json)：Agent、记录详情各八次完整开合，动画区间最大 hitch 分别为 33.333 / 8.333 ms。页面切换仍有动画区间外长延迟；不宣称所有场景零卡顿或稳定 60/120 FPS。本次未重新采集 Release Instruments 数据。原始 trace、TOC 和本机诊断上下文不公开。

最终 app 与 DMG 公证均为 Accepted，分别为 `7ed548c9-e839-4473-a18f-2fd75374cb12`、`18a57c21-e15d-4003-85aa-12092a0f111a`；两者 staple validate 和 Gatekeeper 通过（Notarized Developer ID）。最终 DMG 的 Sparkle 清单生成完成，版本 0.5.0 / build 6。

真实 GUI 回归使用最终 Release 包复制并重签的独立 `Release050QA` 应用，未重新编译；仅变更测试标识、测试更新设置与签名，以隔离本地存储和 Keychain。它不是公开下载原包，GUI 结果不替代原包的签名与公证证明。已实际启动并验证 Studio、计划展开和记录详情同时显示、自动估算隐藏/恢复、Agent 示例草稿、最近会话开合与导航恢复；新脚本执行 `SELECT 40 + 2 AS release_check` 返回 42，脚本历史菜单显示最近脚本与更多历史入口。未发送真实 API 请求或操作用户数据库。

公开下载和线上流水线结果在发布后补记。本机环境为 Apple Silicon、macOS 27 beta、Xcode 27 beta 6；最低声明 macOS 26，macOS 26 真机运行未在本轮验证。合成 HTTP 回归不代表本轮真实模型供应商调用验收。
