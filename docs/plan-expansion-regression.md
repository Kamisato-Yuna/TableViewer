# 计划估算展开崩溃回归

2026-09-08，macOS 27.0（26A5425a），Apple Silicon。

## 复现与修复

安装版 0.4.0（5）在 PostgreSQL 数据表中点击“计划估算”展开按钮后退出。
本轮在 payments 表实际复现；系统日志记录窗口约束更新计数达到 1039，
随后抛出 AppKit 异常。用户提供的同日崩溃记录也指向
`NSHostingView.SizeConstraints.update` / `SplitViewChildController`。

展开内容原为直接参与分栏尺寸计算的可选择多行 Text。
现在使用 160 pt 高的双向 ScrollView 容纳完整计划，文本保持原始换行、
可选择，不让计划长度决定分栏的最小尺寸。改动仅限数据浏览页。

## 已执行

- `./script/build_and_run.sh --build`：Debug 构建通过。
- 从构建生成的 `.app` 启动，连接现有 PostgreSQL E2E 测试库。
- orders 表（估算 50000 行、成本 1666）：展开后显示完整计划文本；
  向下滚动到末尾成功，数据表仍可见。
- 连续三轮收起、展开：六次操作均成功，应用未退出。
- 保持计划展开时打开、关闭右侧记录详情栏：均成功。
- `git diff --check`：通过。

这是本机原生界面的定向回归，不代表 Release 打包、公证或发布验收；
未替换 `/Applications/TableViewer.app`。未执行无关数据库写入测试。
