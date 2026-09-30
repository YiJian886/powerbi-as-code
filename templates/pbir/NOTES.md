# PBIR 模板使用规则(重要) — 已按 Desktop 2.157(2026.08,内部 2.157.151.0)基准冻结

## 当前基准(schema 版本,来自用户 seed.pbix,勿改)
| 文件 | $schema 版本 |
|---|---|
| definition/version.json | versionMetadata/1.0.0, `"version": "2.0.0"` |
| definition/report.json | report/**3.3.0** |
| definition/pages/pages.json | pagesMetadata/**1.1.0** |
| 页面 page.json | page/**2.1.0**,默认尺寸 1920×1080,FitToPage |
| 视觉 visual.json | visualContainer/**2.12.0** |
| 主题 | **Fluent2-CY26SU08**(文件已放在模板 StaticResources 下,引用路径 `BaseThemes/Fluent2-CY26SU08.json`) |

## 复制优先(核心工作法)
- 需要新视觉 = 从 `templates\pbir\examples\`(现有:clusteredBarChart.visual.json,来自真实 Desktop 导出)复制一个
  结构最接近的 visual.json 整段,然后只改:
  1. `name`(可读名,如 `chart_avg_1000m`)
  2. `position`(x/y/width/height)
  3. `visual.visualType`(如需换类型,再抄对应类型样例)
  4. `visual.query.queryState` 里各数据角色投影的字段(Entity=表名,Property=列名)
  5. `visual.filterConfig`(若不需要筛选,整个删掉)
- 投影字段真实语法(照抄此形状):
  - 裸列:`"field":{"Column":{"Expression":{"SourceRef":{"Entity":"表名"},"Property":"列名"}}}` + `"queryRef":"表名.列名"` + `"nativeQueryRef":"列名"` + `"active":true`(仅在需要的角色上)
  - 聚合列(如计数/求和):`"field":{"Aggregation":{"Expression":{"Column":{"Expression":{"SourceRef":{...}},"Property":"列名"}},"Function":N}}`,`Function` 枚举值以 examples 为准(5=Count)
- 新页面 = 复制页面文件夹(`definition/pages/<页名>/`),改 `page.json` 的 `name`/`displayName`,并同步 `pages/pages.json` 的 `pageOrder`/`activePageName`。

## 铁律
- 只改内容,不改 `$schema` 与 JSON 内部既有 `name`;schema 版本冻结值见上表。
- `reportExtensions.json`:没有扩展度量就**删除整个文件**(空 entities 会让 Desktop 打不开)。
- 页面/视觉文件夹用可读名(字母数字下划线);Desktop 保存保留;文件夹名与 JSON 内 `name` 可以不同,但别乱改内部 `name`。
- 生成的文件一律 UTF-8 无 BOM;不要用 GBK 写 JSON(脚本已统一 UTF8Encoding(false))。

## 常见 visualType(供对照;取准确 schema 以 examples/seed 为准)
table | matrix | lineChart | stackedColumnChart | clusteredColumnChart | clusteredBarChart | pieChart | card | advancedSlicerVisual | treemap | funnel | gauge | scatterChart | map / filledMap
