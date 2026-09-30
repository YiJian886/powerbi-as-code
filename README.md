# pbi-workspace

把 Power BI 报表变成**纯文本工程**：可 diff、可 code review、可进 CI。

---

## 为什么要做这个

`.pbix` 是一个二进制包。这意味着报表资产没法像代码一样管理：

- 改了一版报表，`git diff` 出来是 `Binary files differ`，评审的人看不到你改了什么
- 两个人同时改同一个报表，只能靠"你先别动，我改完你再动"
- 没有分支、没有回滚、没有 blame

这是 BI 行业抱怨了很多年的问题。微软后来推出了 **PBIP**（Power BI Project）格式，
把报表拆成磁盘上的文本文件——但大部分人还没用起来，公开的工具链也很少。

这个仓库就是围绕 PBIP 搭的一套工具链。

---

## 它解决什么

PBIP 的目录形态：

```
<工程>.pbip                          # 工程入口
<工程>.Report/
  definition/
    version.json                     # schema 版本
    report.json
    pages/pages.json                 # 页面顺序
    pages/<页>/page.json             # 单个页面
    pages/<页>/visuals/<视觉>/visual.json   # 单个图表（最大的文件）
<工程>.SemanticModel/
  definition/
    database.tmdl                    # 模型级设置
    tables/<表>.tmdl                 # 表定义：列 + 度量 + M 分区
    relationships.tmdl
```

本仓库提供：

| 能力 | 脚本 | 状态 |
|---|---|---|
| 从模板脚手架出完整工程 | `scripts/new-project.ps1` | ✅ 可用 |
| 校验工程内所有 JSON + 结构自检 | `scripts/validate-json.ps1` | ✅ 可用 |
| 打印工程结构摘要（页面/视觉/度量） | `scripts/inspect-project.ps1` | ✅ 可用 |
| 从你的导出提取 schema 版本与主题 | `scripts/setup-from-export.ps1` | ✅ 可用 |
| 从 YAML 需求声明生成工程 | `scripts/build-from-spec.ps1` | 🚧 开发中 |
| 自动化测试 | `tests/` | 🚧 开发中 |

模板库（`templates/`）冻结了一套经过实测的 schema 版本和真实视觉样例，
**这是整个仓库最有价值的部分**——它避免了从零摸索 PBIR 的 JSON 结构。

---

## 快速开始

### 1. 准备你自己的基准工程

模板里的 schema 版本是照着**一份真实导出**冻结的，但那份导出含真实业务数据，
没有随仓库提供。你需要自己生成一份：

1. Power BI Desktop 里新建一个报表，随便放一张小表；
2. 另存为 **Power BI 项目（.pbip）**；
3. 运行下面这行，它会自动比对五个 schema 版本号、复制主题文件：

   ```powershell
   .\scripts\setup-from-export.ps1 -ExportPath 'C:\你的导出目录\MyReport'
   ```

**版本对不上是这套东西最常见的故障原因。**

### 2. 脚手架一个工程

```powershell
.\scripts\new-project.ps1 -Name SalesDash
.\scripts\validate-json.ps1 -Project .\projects\SalesDash
.\scripts\inspect-project.ps1 -Project .\projects\SalesDash
```

### 3. 在 Desktop 里打开

双击 `projects\SalesDash\SalesDash.pbip`。如果数据源需要拉数，点「刷新」。

---

## 设计取舍

### 为什么不直接操作 `.pbix`

详细记录见 [`environment-facts.md`](environment-facts.md)。简短版 —— 以下路径都实际验证过，不可行：

| 路径 | 结果 |
|---|---|
| 自建命名管道桥接 Desktop（查状态 / 重载 / 截图） | 管道存在但连接超时，服务端未放行 |
| XMLA 端点 / 本地分析服务 TCP | 本机引擎**不监听 TCP 端口** |
| GUI 自动化（模拟点击、UI Automation） | 目标程序自绘界面，控件树不可用；且会跟用户抢焦点 |
| 直接启动商店版引擎进程当后端 | 有启动校验，静默退出 |
| 逆向模型缓存的私有压缩格式 | 研究性工作，与目标无关 |

**所以唯一可靠的自动化路径就是「编辑文本工程 + 用户在 Desktop 里打开刷新」。**
这个结论是花时间试出来的，也是这个仓库存在的理由。

### 关键约束（踩过的坑）

- **`cache.abf` 是本地数据缓存**，必须 gitignore。删掉后工程照常打开，只是没数据。
- **没有扩展度量时 `reportExtensions.json` 必须整个删掉** —— 留着空的 `entities`
  会让 Desktop 直接打不开工程。
- **schema 版本不能手改**。以你自己 Desktop 导出的为准。
- **新增视觉时复制现成的 `visual.json` 再改**，不要从零写 —— 投影和查询结构极易写错。

---

## 已验证 / 未验证

诚实清单。**没验证的不要当成能用。**

**已验证：**

- 脚手架生成的工程结构完整（`Report` + `SemanticModel` + `.pbip`）
- 全部 JSON 可被解析器接受
- PBIR schema 版本对齐一份真实的 Desktop 2.157 导出
- 真实 `visual.json` 样例（15KB，含投影 / 查询 / 筛选的完整结构）已脱敏，可直接参考

**未验证：**

- 生成的工程没有在真实 Desktop 里逐个打开验证过（这一步需要人工操作）
- TMDL 侧语法参考来自文档整理，**未逐条实测**
- 没有 CI，没有自动化测试 ← 正在补

---

## 目录结构

```
pbi-workspace/
├── README.md                     # 本文件
├── environment-facts.md          # 工程决策记录与踩坑结论（先读这个）
├── requirements.md               # 需求采集模板
├── data/                         # 中间数据（gitignore）
├── projects/                     # 生成的工程（gitignore）
├── templates/
│   ├── pbir/                     # 报表侧模板
│   │   ├── NOTES.md              # schema 版本表 + 复制优先工作法
│   │   ├── MyReport.*            # 可用的空白工程骨架
│   │   └── examples/             # 真实视觉样例（已脱敏）
│   └── tmdl/                     # 语义模型 TMDL 参考
├── m-queries/                    # Power Query 模板（Excel / CSV / MySQL）
└── scripts/                      # PowerShell 工具
```

---

## 开发

### 环境要求

- Windows
- Windows PowerShell 5.1（**不是** PowerShell 7 —— 有些参数不通用）
- 执行策略默认是 Restricted，跑脚本要带 `-ExecutionPolicy Bypass`

### 两条硬性规则

1. **`.ps1` 必须存成 UTF-8 带 BOM。** 不是风格问题：PS 5.1 读 `.ps1` 是按
   ANSI(GBK) 解码的，不带 BOM 的中文会全变乱码，而且是语法级报错，
   连报错信息本身都是乱码，极难定位。
2. **JSON 一律 UTF-8 无 BOM。** Power BI 的解析器不认 BOM。

`.gitattributes` 已按这两条配好换行处理。

---

## License

MIT
