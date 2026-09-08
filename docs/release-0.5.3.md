# 0.5.3 发布验收

版本 0.5.3（9），关联 [Issue #31](https://github.com/Kamisato-Yuna/TableViewer/issues/31) 和 [Issue #32](https://github.com/Kamisato-Yuna/TableViewer/issues/32)。在最新 main `ca099ca` 上合并两项已授权改动，统一发布；来源目录与旧版本标签、附件保持不变。

## 集成范围

- 字体与示例入口：从 `codex/font-picker-demo-visibility` 来源工作树精确移入两份源文件增量及 [实现验收说明](font-picker-demo-visibility.md)，包含最后的 Label `.gray` 与 Menu `.tint(.gray)`。
- 空状态布局：核验 `133b316199778a0a7b3999f684a334bea870e470` 及其实现提交 `0e27e0e` 的 GPG 签名，仅移入 QueryEditorView、ObjectBrowserView、WorkspaceView 源码增量。重写统一报告，不把单项构建当作组合包验收。
- 版本递增为 0.5.3 / build 9。

## 行为

字体设置使用本机可加载字体的原生下拉菜单，保留 SF Mono 与已有手输偏好。存在其他连接时，连接标题灰色省略号菜单持续提供示例显示/隐藏，示例连接右键也可隐藏；没有其他连接时不能隐藏。隐藏不删除连接或数据、不强制切换当前数据库，移除最后一个非示例连接仍自动恢复。

查询与实体关系内容填满剩余高度，空状态底栏贴底；无脚本的查询提示与创建按钮集中居中，实体关系说明/搜索保持顶部。保留 0.5.2 的编辑器边界与历史切换崩溃修复。

## 验收

组合包的正式构建、独立 GUI、公证及公开发行证据完成后补齐。实现任务旧 GUI 未包含最终灰色，不能替代本次最终组合包检查。

本轮不重复外部 PostgreSQL/MongoDB、真实模型、macOS 26 真机或生产客户端自动安装重启全链路；使用独立 bundle 与合成数据保护用户真实连接、Keychain 和窗口。
