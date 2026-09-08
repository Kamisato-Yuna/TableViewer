# Agent 输入区与用量展示

2026-09-08。

输入区使用系统 GlassEffectContainer / glassEffect 圆角浮层，底行包含结构附带菜单、审批选择、当前模型/API 设置入口、停止和发送操作。现有配置仍为单个 OpenAI-compatible API 配置，未新增多供应商账户存储。审批禁用和共享确认规则保留。

右侧最近会话改为时间线便签，移除右侧底部新建与所有会话按钮，顶部原入口保留。

assistant 气泡悬停时显示供应商返回的本次请求输入、输出、合计 tokens；缺失字段不补数，旧历史或供应商没有返回 usage 时显示“未提供用量”。用量由普通响应或 SSE 尾部 usage-only 数据获取。流式请求设置 stream_options.include_usage。用量只保存在本地 StoredAgentMessage，不进入后续发送的消息历史。

验证：

- `./script/test_workbench040.sh --agent-usage-only` 五项通过：流式末尾统计、普通部分统计、本地保存往返、旧历史兼容、请求历史不包含用量。
- Debug 构建通过，中英文 620 项校验通过，git diff --check 通过。
- 原生界面截图检查输入浮层、控件排版、右侧时间线；打开既有历史正常。未发送真实 API 请求，未对实际供应商的 usage 返回做验收。
