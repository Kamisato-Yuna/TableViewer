# 结果导出 / Result exports

导出只包含当前已加载、由调用者传入的结果（界面应传入当前筛选后可见行），不会再次运行查询，也不是全库备份。分页、截断仍适用。

Exports contain only the loaded result supplied by the caller, normally the currently visible filtered rows. They never rerun queries and are not full-database backups.

| 格式 / Format | 表示 / Representation |
| --- | --- |
| CSV / TXT | CSV 或带引号 TSV；未加引号 `\N` 为 NULL，`""` 为空串；BLOB 是 `base64:` 前缀文本。公式或危险控制字符开头的标题和值前置单引号，适合安全查看，不能承诺无损往返。 / Quoted CSV or TSV; unquoted `\N` means NULL, `""` means empty string. BLOBs use a `base64:` text prefix. Potential spreadsheet formulas are prefixed with an apostrophe. These are display exports, not lossless interchange formats. |
| JSON / YAML | 关系结果为 `columns` 元数据和 `rows` 二维数组，保留重复列名。NULL 为 null；文本始终为字符串；BLOB 为 `{type: "blob", base64: "…"}`。YAML 使用 YAML 1.2 支持的 JSON 语法。 / Relational results use column metadata and row arrays, retaining duplicate names. NULL is null, driver text stays a string, and BLOBs have a tagged base64 representation. YAML uses the JSON syntax supported by YAML 1.2. |
| MongoDB JSON / YAML | 完整原始 Extended JSON 文档数组；保留 BSON 类型标记和大整数文本。无完整文档时明确失败。 / Original Extended JSON documents retain BSON markers and number text. Export fails if complete documents are unavailable. |
| XML | `columns` 和 `rows`；NULL 用属性，空串保留空内容，BLOB 使用 base64。XML 1.0 不允许的文本字符以 UTF-8 base64 表示并标记。 / Columns and rows; NULL is explicit, empty text stays empty, BLOBs use base64. Text containing XML 1.0-invalid characters is tagged and encoded as UTF-8 base64. |
| INSERT SQL | 选择 SQLite/PostgreSQL 方言和目标表，目标表须已存在。标识符引用、文本转义、NULL 与 BLOB 按方言处理。PG text 无法表示 NUL，明确失败。 / Select SQLite/PostgreSQL and an existing target table. Identifiers, literals, NULL and BLOBs are dialect-aware; PostgreSQL text containing NUL is rejected. |

驱动模型目前将许多数值与日期表示为文本。导出不根据文本内容猜测数字或布尔值，保留 `databaseType` 供使用者解释。PostgreSQL `bytea` / OID 17 是明确的二进制类型，支持其 hex 与 escape 表示并导出为 BLOB。INSERT 中的文本保持引用，由目标列类型决定转换；跨库的日期、布尔、数组、JSON、生成列、默认值、约束等需要目标 schema 兼容，不属于自动迁移。MongoDB 文档不能直接导出 INSERT，应选择 JSON。

The driver represents many numbers and dates as text. Exports never infer numeric or boolean types from string content; `databaseType` records the available metadata. PostgreSQL bytea/OID 17 is decoded from hex or escape text into BLOBs. SQL text values remain quoted and target column types determine conversion. Cross-database dates, booleans, arrays, JSON, generated columns, defaults and constraints require compatible target schemas; this is not an automatic migration. MongoDB documents cannot be exported as INSERT SQL.

## 集成 / Integration

- `ResultExporter(format:sourceKind:sqlDialect:table:).encode(QueryResult)` 返回字符串或抛出错误；调用者选择保存路径并原子写入。 / Returns text or throws; the caller owns the save panel and atomic write.
- `DataGrid.selectedIDs` 和 `selectionChanged` 是完整选择集合；调用者应同步保存集合，避免旧单行状态覆盖多选。 / Persist the full selection set.
- `DataGrid.editCell` 提供行 UUID 和原始列索引，列重排不改变其含义。它是编辑尝试回调；调用者必须检查只读、主键、生成列、BLOB、权限和原始记录。未接新回调仍兼容旧双击回调。 / The edit-attempt callback identifies the row and original column even after reordering. The store must enforce read-only, primary-key, generated-column, BLOB and permission checks.

## 验证 / Validation

`Tests/ResultExporterTests.swift` 覆盖 SQLite 内存库 SQL 往返、NULL/空串/BLOB/NUL、字符串转义、CSV 公式防护、TXT、JSON/YAML、XML 解析、PG bytea 两种编码和 SQL 静态转义、MongoDB 原始文档保持。PostgreSQL 静态测试不代替真实 PostgreSQL 导入验收；DataGrid 类型检查不代替真实应用 Shift/Command/键盘/双击验收。

```sh
swiftc -module-cache-path /tmp/tableviewer-export-module-cache \
  TableViewer/Models/DatabaseModels.swift TableViewer/Services/ResultExporter.swift \
  Tests/ResultExporterTests.swift -o /tmp/tableviewer-export-tests
/tmp/tableviewer-export-tests
```
