// Power Query (M) —— Excel 工作簿模板
//
// 用法：把下面 DataFolder 改成你自己的数据目录，整段贴进 Desktop 的高级编辑器。
// 在 Power Query 里把它定义成「参数」更好（管理参数 → 新建），换机器只改一处。
//
// ⚠️ 路径是「打开报表的那台机器」上的路径，不是生成工程的那台。
//    Desktop 刷新数据时读的是本地文件。

let
    DataFolder = "C:\path\to\pbi-workspace\data",
    Source = Excel.Workbook(File.Contents(DataFolder & "\orders.xlsx"), null, true),
    Sheet = Source{[Item = "Sheet1", Kind = "Sheet"]}[Data],
    #"Promoted Headers" = Table.PromoteHeaders(Sheet, [PromoteAllScalars = true]),
    #"Changed Types" = Table.TransformColumnTypes(#"Promoted Headers", {
        {"order_date", type date},
        {"region", type text},
        {"amount", type number}
    })
in
    #"Changed Types"
