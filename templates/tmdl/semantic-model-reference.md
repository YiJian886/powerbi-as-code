# TMDL 语义模型参考(表/列/度量 + M 分区)

> ⚠️ 本文件是**语法参考**，不是规范。TMDL 的具体形态随 Desktop 版本变化。
> 首次使用前，建议新建一个最小 pbip（含一张小表），用你 Desktop 生成的 TMDL 校正本文件。

## 目录布局(.SemanticModel/)
```
MyReport.SemanticModel/
├── definition.pbism              # 模型入口:{"version":"4.x","settings":{}} 等
├── definition/                   # TMDL 定义(推荐,与 model.bim 二选一)
│   ├── database.tmdl             # 模型级:文化/语言、注释、默认
│   ├── tables/
│   │   ├── Orders.tmdl           # 每表一个文件:列 + 度量 + 分区(M 表达式)
│   │   └── DimDate.tmdl
│   ├── relationships.tmdl        # 关系(可选文件,取决于 Desktop 生成习惯)
│   └── cultures/…(视生成情况)
└── .pbi/
    ├── cache.abf                 # 数据缓存（应 gitignore，可删）
    └── localSettings.json        # 本机设置（应 gitignore）
```

## TMDL 语法片段(参考)

### 表:列 + M 导入分区
```tmdl
table 'Orders'
    // 列定义(标量列)
    column 'OrderDate'
        dataType: dateTime
        formatString: 'yyyy-MM-dd'
        isHidden: false

    column 'Amount'
        dataType: double
        formatString: '\$#,##0.00'

    column 'Region'
        dataType: string

    // 度量
    measure 'Total Amount' = SUM ( 'Orders'[Amount] )
        formatString: '\$#,##0.00'

    // M 分区(数据入口):mode: Import
    partition 'Orders' = m
        mode: Import
        source =
            let
                Source = Csv.Document(File.Contents("C:\path\to\pbi-workspace\data\orders.csv"),
                         [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
                #"Promoted Headers" = Table.PromoteHeaders(Source, [PromoteAllScalars=true])
            in
                #"Promoted Headers"
```

### 日期表(计算表,供时间智能用)
```tmdl
table 'Date' = CALENDAR(DATE(2020,1,1), DATE(2026,12,31))
    column 'Year'
        dataType: int64
        expression: YEAR('Date'[Date])
    column 'MonthNo'
        dataType: int64
        expression: MONTH('Date'[Date])
    column 'Date'
        dataType: dateTime
```

### 关系
```tmdl
relationship 'Orders'->'Date' = many-to-one singleDirection on 'Orders'[OrderDate] to 'Date'[Date]
```

## 注意事项
- 分区语法 `partition <名> = m` + `source =` 为 Desktop 生成的形态；若有出入以你自己导出的工程为准。
- `cache.abf` 不含在交付内;删除后工程照常打开(空数据),用户刷新即拉数。
- M 表达式引用外部文件/DB 时，路径在**打开报表的那台机器**上必须有效。
- MySQL M 模板见 `m-queries/mysql.pq`;CSV/Excel 模板见同目录。
