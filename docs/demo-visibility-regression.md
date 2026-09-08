# 示例数据库侧栏可见性

本需求为 0.5.0 发布后的改动；工作树继承的版本配置仍显示 0.4.0，本任务不更改版本或发布。

新增非示例连接（包括 SQLite）保存且连接成功后，在侧栏提示隐藏或继续显示。编辑、取消、失败不触发。任一选择持久保存，后续添加不重复打扰。隐藏仅筛选侧栏，保留示例连接和文件；隐藏时提供恢复入口。删除最后一个用户连接或仅剩示例时启动，自动恢复示例。删除当前连接会选择剩余可见连接并清理对象及页面状态。

## 验证

运行 bash script/test_demo_visibility.sh：独立随机 bundle 标识，全新隔离 Application Support 目录和合成 SQLite，拒绝真实目录及已有连接文件，保留测试产物，不访问远程数据库或 Keychain。

通过：首次显示、成功添加 SQLite 提示、保留选择且不重复、隐藏保留数据、新 Store 启动持久化、多个连接删除部分仍隐藏、删除最后一个恢复并选中示例、仅示例启动修正、连接失败不提示。

真实 GUI：启动 /tmp/TableViewer-DemoVisibility.app，标识 local.yuna.TableViewer.DemoVisibilityGUI，使用 /private/tmp/tableviewer-demo-visibility-qa.sqlite。实际点击确认取消不提示、添加成功提示、选择隐藏、恢复入口出现、移除最后一个连接自动回到 Studio 概览。最终构建再次启动后，只有示例的状态正确。

限制：GUI 未逐项重复继续显示、多连接删除部分及隐藏状态的完整进程重启；这些由真实 WorkspaceStore 集成回归覆盖。未验证远程 PostgreSQL / MongoDB，外部连接分类使用统一 isDemo 语义。主应用未终止，真实连接未改动。

原工作树已有多项未提交改动。本任务以独立补丁交付，未提交、推送或发布。查询 GitHub 所有 Issue 后未发现本需求匹配的开放 Issue。
