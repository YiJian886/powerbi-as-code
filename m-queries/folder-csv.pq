// Power Query (M) —— CSV / 文件夹模板
//
// 用法：改 DataFolder，整段贴进 Desktop 的高级编辑器。
// ⚠️ 路径是「打开报表的那台机器」上的路径。

// ─────────────────────────────────────────────────────────
// 1) 单个 CSV（第一行是表头）
// ─────────────────────────────────────────────────────────
let
    DataFolder = "C:\path\to\data",
    Source = Csv.Document(
        File.Contents(DataFolder & "\orders.csv"),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    #"Promoted Headers" = Table.PromoteHeaders(Source, [PromoteAllScalars = true])
in
    #"Promoted Headers"

// ─────────────────────────────────────────────────────────
// 2) 合并整个文件夹里所有同结构的 CSV（按月分文件时很有用）
//    把上面那段注释掉，用这段
// ─────────────────────────────────────────────────────────
// let
//     DataFolder = "C:\path\to\data",
//     Source = Folder.Files(DataFolder),
//     Filtered = Table.SelectRows(Source, each Text.EndsWith([Name], ".csv")),
//     #"Added Custom" = Table.AddColumn(Filtered, "Content2", each Csv.Document([Content], [Delimiter = ",", Encoding = 65001])),
//     Expanded = Table.ExpandTableColumn(#"Added Custom", "Content2", Table.ColumnNames(#"Added Custom"[Content2]{0})),
//     Promoted = Table.PromoteHeaders(Expanded, [PromoteAllScalars = true])
// in
//     Promoted
//
// 注意：这样合并出来的表没有「来自哪个文件」这一列。要追溯数据来源的话，
// 在 Filtered 之后加一列 [Name] 作为 SourceFile 再展开。
