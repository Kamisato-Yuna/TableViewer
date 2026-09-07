# Agent 0.4.0 验收隔离与整合

关联 #17。本说明记录开发接口和合成验收方法，不表示真实服务或正式分发物已经验收。

## 执行与审批

每个会话保存 `approvalMode`，旧会话缺省为手动。仅敏感模式自动选择结构检查和保守的只读查询候选；词法判断不是权限，执行器必须强制只读，阻止 SELECT 函数、CTE 等间接写入。完全自动模式按用户选择批准工具调用，仍遵守工作台只读、驱动和数据库权限。`ask_user` 始终由用户回答。三种模式都不自动分享结果。

`AgentSession.onAutomaticActions` 仅在本次模型完整返回时通知新动作 ID 与 `requiresReadOnly`，恢复磁盘历史不触发回调。WorkspaceStore 应为所有会话绑定回调，按 ID 串行调用执行方法，同时重查连接、忙碌状态和修改草稿。敏感模式下未知或较大估算应回到人工确认。将估算摘要存入 `AgentAction.executionEstimate` 可使执行卡片保留其说明。结果完成后继续保留“发送结果并继续”按钮。

AgentToolExecutor 接收 `readOnly: Bool = false`，整合者传工作台只读 OR 回调的强制只读值。数据库引擎的 `run(_:readOnly:)` 负责实际执行约束。

## 安全隔离真实应用

构建验收专用 bundle，例如 `local.yuna.TableViewer.Acceptance040`，使用独立 DerivedData 和 `.app` 路径，通过 `open -n /absolute/path/TableViewer.app` 启动，不能运行裸可执行文件替代 GUI 验收。

- Keychain 服务名由 bundle ID 加 `.connections` 得到，固定 Agent UUID 因此不会读取正式服务。正式 bundle `local.yuna.TableViewer` 保持原服务名不变。
- 非正式 bundle 的 LocalWorkspace 使用 bundle ID 目录，避免接触正式连接、Studio 和会话文件。
- `UserDefaults.standard` 使用当前应用 bundle 的偏好域，API 配置不读取正式 bundle 的配置。
- 验收时只创建合成数据库和专用 API 设置。空配置引导不需要读取或删除原用户 Keychain 项。不得把用户真实服务密钥复制到 fixture。
- 使用现有稳定签名身份构建仍需遵守正常 Keychain 授权；隔离命名不扩大 ACL。

依次验收空配置进入、配置保存、三档审批、SELECT/写入/结构检查/ask_user、新执行首行、长命令折叠、超长命令浮窗与复制、结果共享确认、历史恢复不执行。覆盖浅深色、小尺寸、键盘焦点和 Escape。真实服务可用性由整合验收单独记录；本地 HTTP fixture 只证明受控协议与状态链。

## 本地验证

`script/test_agent.sh` 包含审批回调、驱动只读要求标志、旧会话默认手动迁移、不代答、不自动分享、Keychain 命名及原 HTTP fixture 回归。使用 Xcode 宏插件需要在支持其沙箱进程的环境运行；临时工作区应统一使用 `/private/tmp` 路径，避免 Swift 模块缓存同时出现 `/tmp` 别名。
