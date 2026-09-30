// Power Query (M) —— MySQL 数据源模板
// 用法:粘贴到 TMDL 分区的 source 或 Desktop 高级编辑器;刷新时 Desktop 会提示输入凭据。
// ⚠️ host/port/database 按实际替换;凭据不要在文件里明文保存。

let
    Source = MySql.Database("127.0.0.1:3306", "your_database"),
    Orders = Source{[Schema = "your_schema", Item = "orders"]}[Data]
in
    Orders

// 若需直接在 SQL 层过滤/聚合(减轻 Desktop 负担):
// let
//     Source = MySql.Database("127.0.0.1:3306", "your_database"),
//     Query = Value.NativeQuery(Source, "SELECT order_date, region, SUM(amount) AS amount FROM orders GROUP BY order_date, region", null, [EnableFolding = true])
// in
//     Query
