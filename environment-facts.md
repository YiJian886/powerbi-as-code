# 工程决策记录与踩坑结论

> 这份文件记录的是**为什么这么做**，以及**为什么没走别的路**。
> 新接手的人（或未来的我）先读这里，能省掉几天重复试错。

## 起点：目标是什么

让「写一份需求 → 直接产出 Power BI 报表」这条路可以自动化、可以版本控制、可以离线跑。

`.pbix` 是二进制包，不能 diff、不能 code review、多人协作必冲突。这是 BI 行业抱怨了
很多年的问题：**报表资产没法像代码一样管理**。

所以目标定为：把报表变成**纯文本工程**。

## 试过、确认不可行的路（不要重复）

按投入产出比排过序，以下都实际验证过：

| 路径 | 结果 | 结论 |
|---|---|---|
| 命名管道桥（自建 JSON-RPC 管道，用于查询引擎状态 / 触发重载 / 截图） | 管道存在，但完整权限、同账号同会话下连接仍超时 | 服务端未放行，放弃 |
| XMLA 端点 / 本地分析服务 TCP 端口 | 本机引擎进程**没有监听 TCP 端口** | 拿不到实时模型接口 |
| GUI 自动化（模拟点击、按键、UI Automation） | 目标程序是自绘界面，控件树不可用；且会与用户的真实操作抢焦点 | 不投入 |
| 直接启动商店版引擎进程当后端用 | 静默退出 | 有启动校验，放弃 |
| 逆向分析模型缓存文件的私有压缩格式 | 属于研究性工作，与目标无关 | 不做 |
| 联网安装官方命令行桥接工具 | 环境无外网；且子进程 spawn 受限 | 不可行 |

**这张表本身是这套方案的一部分** —— 它说明了为什么最后落到"文本工程"这条路：
不是没想到别的，是都试过了。

## 可行路径（唯一主线）

**PBIP 文本工程流水线**：

1. 报表 = 纯文本：
   - `<工程>.pbip` —— 工程根文件
   - `<工程>.Report/` —— PBIR JSON：页面 / 视觉 / 筛选
   - `<工程>.SemanticModel/` —— TMDL：表 / 列 / 度量 + M 分区
2. 所有文件由本仓库的模板 + 脚本生成和修改，**可离线、可校验、可 diff**；
3. 用 Desktop 打开工程：缺 `cache.abf` 时模型空载打开；有数据源则点「刷新」拉数；
4. 迭代 = 打开 / 刷新 / 截图反馈 → 改文件 → 重开。

## 关键事实（踩出来的）

- **`.SemanticModel/.pbi/cache.abf` 是本地数据缓存**：必须 gitignore，不能提交；
  删掉后工程照常打开（只是没数据）。
- `.pbip` 根文件、`.Report/definition.pbir`、`.SemanticModel/definition.pbism`
  都可以单独用来打开工程。
- **`reportExtensions.json` 在没有扩展度量时必须整个文件删掉** —— 留着空的 `entities`
  会导致 Desktop 打不开工程。这个坑排查了很久。
- PBIR 当前目录结构：
  `definition/` 内含 `version.json`、`report.json`、`pages/pages.json`、
  `pages/<页>/page.json`、`pages/<页>/visuals/<视觉>/visual.json`。
- **schema 版本一旦冻结就别手改**：改版本号会让 Desktop 拒绝加载或静默丢内容。
  正确做法是从你自己 Desktop 导出的基准工程里抄版本号。
- **复制优先**：新增视觉时，复制一个结构最接近的现成 `visual.json` 再改字段，
  比从零写可靠得多（投影和查询结构最容易写错）。
- **TMDL 侧新增表**需要：表定义（列 + M 分区 `mode: Import`），
  可能还需要 relationships / 文化信息。语法以你自己导出的基准工程为准。

## 关于「基准工程」

这套模板的 schema 是照着**一份真实的 Desktop 导出**冻结的，但那份导出里含真实业务数据，
不适合放进公开仓库，所以**没有随仓库提供**。

你需要自己生成一份：

1. 在 Power BI Desktop 里随便打开一个报表（或新建一个，放一张小表）；
2. 另存为 **Power BI 项目（.pbip）**，选一个无关紧要的目录；
3. 打开 `.Report/definition/version.json`、`report.json`、`pages/pages.json`、
   `page.json`、`visual.json`，把里面的 `$schema` 版本号抄进
   `templates/pbir/NOTES.md` 的版本表；
4. 顺便把 `StaticResources/SharedResources/BaseThemes/` 下的主题文件复制到
   `templates/pbir/MyReport.Report/StaticResources/SharedResources/BaseThemes/`。

这样模板就和你的 Desktop 版本对齐了。**版本对不上是这套东西最常见的故障原因。**

## 版本基线

本仓库模板冻结时依据的 Desktop 版本：

| 组件 | 版本 |
|---|---|
| Power BI Desktop（Microsoft Store / MSIX 渠道） | 2.157 |
| `visualContainer` | 2.12.0 |
| `report` | 3.3.0 |
| `page` | 2.1.0 |
| `pagesMetadata` | 1.1.0 |
| `versionMetadata` | 2.0.0 |
| 默认主题 | Fluent2（随模板提供） |

**你的版本可能不同。** 以你自己导出的为准，这张表只是记录"这套模板是在什么版本上验证的"。
