## 1. JSON 格式化

### JSON-FMT-01 · 正确短 JSON

类型：正常

```json
{"id":1,"name":"Alice","active":true,"tags":["dev","ops"],"meta":null}
```

检查点：

- 能缩进对象和数组。
- 保留 `null`、布尔值、数字类型。

### JSON-FMT-02 · 正确长 JSON：嵌套、Unicode、转义字符、空对象、空数组

类型：复杂/压力

```json
{"project":{"id":"toolkit-001","name":"开发者工具箱","version":"2.4.0","createdAt":"2026-07-07T09:30:45+08:00","enabled":true,"limits":{"maxItems":5000,"timeoutMs":120000,"ratio":0.875},"owners":[{"id":101,"name":"Rena","roles":["admin","developer"],"contact":{"email":"rena@example.com","phone":"+86-10-8888-6666"}},{"id":102,"name":"QA 用户","roles":["tester"],"contact":{"email":"qa@example.com","phone":null}}],"features":{"jsonFormatter":{"enabled":true,"options":{"indent":2,"sortKeys":false}},"sqlFormatter":{"enabled":true,"dialects":["postgresql","mysql","sqlite"]},"htmlToMarkdown":{"enabled":true,"preserveTables":true}},"samples":[{"type":"string","value":"包含中文、emoji 🙂、换行\\n、制表符\\t、引号\\\"、反斜杠\\\\"},{"type":"number","value":1234567890.12345},{"type":"emptyObject","value":{}},{"type":"emptyArray","value":[]}]},"audit":{"updatedBy":"system","history":[{"at":"2026-07-01T00:00:00Z","action":"created"},{"at":"2026-07-06T18:22:11Z","action":"updated"}]}}
```

检查点：

- 转义字符不能被错误展开或丢失。
- Unicode 文本应保持可读。
- 大对象格式化后层级清楚。

### JSON-FMT-03 · 正确 JSON 数组顶层

类型：正常

```json
[{"id":1,"score":99.5},{"id":2,"score":0},{"id":3,"score":-42}]
```

### JSON-FMT-04 · 错误 JSON：尾逗号

类型：错误

```json
{"id":1,"name":"Alice",}
```

### JSON-FMT-05 · 错误 JSON：单引号、未加引号的 key

类型：错误

```json
{id: 1}
```

```json
{"name": 'Alice'}
```

预期：两个输入分别提示对象 key 未使用双引号、字符串使用了单引号；不得用第一个首错代表两个分支都已覆盖。

### JSON-FMT-06 · 错误 JSON：注释和 NaN

类型：错误

```json
{
  // JSON 标准不允许注释
  "value": 1
}
```

```json
{"value": NaN}
```

预期：两个输入分别提示 JSON 不支持注释、JSON 不支持 NaN。

### JSON-FMT-07 · 错误 JSON：括号缺失

类型：错误

```json
{"user":{"id":1,"name":"missing end"}
```

### JSON-FMT-08 · 边界 JSON：重复 key

类型：边界

```json
{"id":1,"name":"first","name":"second"}
```

检查点：

- 格式化器保留两个 `name` 成员，不静默覆盖其中一个。
- 页面显示重复 key warning，并说明不同解析器可能只保留最后一个值。

### JSON-FMT-09 · 边界 JSON：空顶层和顶层标量

类型：边界

空对象：

```json
{}
```

空数组：

```json
[]
```

顶层字符串：

```json
"just a string"
```

顶层数字：

```json
-123.45e+6
```

顶层布尔与 null：

```json
true
```

```json
false
```

```json
null
```

检查点：

- 空对象、空数组不应被展开成多行噪音。
- 本工具支持 JSON 顶层标量，应正确格式化或压缩字符串、数字、布尔值和 `null`。

### JSON-FMT-10 · 格式化选项：键排序、缩进、压缩

类型：选项

```json
{"z":3,"a":{"b":2,"a":1},"m":[{"d":4,"c":3}]}
```

检查点：

- 默认格式化应保留输入 key 顺序。
- 开启“键排序”后，同一对象层级内的 key 应按字典序排列。
- 2 空格和 4 空格缩进切换应稳定。
- 压缩模式应移除非必要空白，但不能改写字符串内容。

### JSON-FMT-11 · 错误 JSON：非法数字

类型：错误

```json
{"leadingZero": 01}
```

```json
{"plus": +1}
```

```json
{"hex": 0x10}
```

```json
{"infinity": Infinity}
```

预期：四个输入分别提示前导零、前导加号、十六进制和 Infinity 不属于合法 JSON 数字；不能自动改成 `1`、`10` 或其他“猜测值”。

### JSON-FMT-12 · 错误 JSON：非法 Unicode 转义

类型：错误

```json
{"badEscape":"\uZZZZ"}
```

```json
{"badSurrogate":"\uD83D"}
```

```json
{"loneLowSurrogate":"\uDE00"}
```

预期：三个输入分别提示 Unicode 转义不是 4 位十六进制、高位代理项后缺少低位代理项、低位代理项不能单独出现；不能输出损坏字符。

### JSON-FMT-13 · 未转义控制字符与非 ASCII 数字

类型：错误

未转义换行：

```json
{"message":"first line
second line"}
```

全角数字：

```json
{"count":１２,"zero":０}
```

预期：两者都应报 JSON 语法错误；不能把全角数字按本地化数字接受，也不能静默删除字符串中的真实换行。

### JSON-FMT-14 · 超大整数、小数精度与数字词法保真

类型：边界

```json
{"big":900719925474099312345678901234567890,"tiny":0.000000000000000000123456789,"negativeZero":-0,"exp":1.2300e+45}
```

检查点：

- 格式化、排序和压缩不能先转为浮点数再输出，避免精度丢失或指数形式被意外改写。
- `-0`、尾随零和指数形式如被规范化，工具应有一致且可解释的策略；不得输出无效 JSON。


### JSON-FMT-15 · 空输入与纯空白

类型：边界 / 交互

```json

```

```text
␠␠␠
\t\n
```

预期：

- 页面/FormatRunner 保持安静：不显示错误、不产生输出。
- 清空后旧输出、warning、加载态应复位。
- 自动化：`FormatRunner.run` 对 trim 后空串返回 `.empty`。

### JSON-FMT-16 · 错误诊断可读性（尾逗号样本）

类型：错误 / 诊断

复用 `JSON-FMT-04` 输入。

预期诊断应至少满足：

- 直接说明实际错误，例如“对象末尾多了逗号”；默认错误卡不显示格式名、行号和列号前缀。
- 不得清空用户原输入。
- 不得输出“看起来合法”的修复结果。

### JSON-FMT-17 · 错误 JSON：数组尾逗号、重复逗号、对象重复逗号

类型：错误 / 诊断

数组尾逗号：

```json
[1, 2, 3,]
```

数组重复逗号：

```json
[1,,2]
```

对象重复逗号：

```json
{"a":1,, "b":2}
```

预期：

- 数组尾逗号应提示“数组末尾多了逗号”。
- 数组重复逗号应提示“数组元素之间多了逗号或缺少元素”。
- 对象重复逗号应提示“对象成员之间多了逗号或缺少成员”。
- 三者不得退化成“对象键必须使用双引号”等无关诊断。

### JSON-FMT-18 · 错误 JSON：根值后额外内容

类型：错误 / 诊断

```json
{"a":1}{"b":2}
```

```json
true false
```

预期：应提示一个 JSON 文档只能有一个根值；不能只格式化第一段后静默丢弃后续内容。

### JSON-FMT-19 · 错误 JSON：数字词法细分

类型：错误 / 诊断

前导加号：

```json
{"plus": +1}
```

十六进制：

```json
{"hex": 0x10}
```

小数部分使用非 ASCII 数字：

```json
{"n":1.٢}
```

指数部分使用非 ASCII 数字：

```json
{"n":1e٢}
```

预期：

- 分别提示“数字前不能写加号”、“不支持十六进制数字”、“小数/指数部分只能使用半角数字”。
- 不得把这些错误误判为缺少逗号、未加引号 key 或其他结构错误。

### JSON-FMT-20 · 错误 JSON：对象键缺少值

类型：错误 / 诊断

```json
{"a":}
```

```json
{"a":, "b": 1}
```

预期：两个输入都应提示“对象键后缺少值”；不能退化成“对象没有完整闭合”或“对象键必须使用双引号包裹”。

## 2. SQL 格式化

### SQL-FMT-01 · 正确短 SQL

类型：正常

```sql
select id,name,email from users where active=1 order by created_at desc limit 10;
```

### SQL-FMT-02 · 正确长 SQL：CTE、JOIN、窗口函数、CASE、聚合

类型：复杂/压力

```sql
with recent_orders as (select o.id,o.user_id,o.total,o.status,o.created_at from orders o where o.created_at>=date_trunc('month',current_date)-interval '3 months'), ranked_orders as (select ro.*,row_number() over(partition by ro.user_id order by ro.created_at desc) as rn from recent_orders ro) select u.id as user_id,u.name,u.email,count(ro.id) as order_count,coalesce(sum(ro.total),0) as total_spent,max(ro.created_at) as last_order_at,case when count(ro.id)=0 then 'inactive' when sum(ro.total)>10000 then 'vip' else 'standard' end as segment from users u left join ranked_orders ro on ro.user_id=u.id and ro.rn<=5 where u.deleted_at is null and (u.email like '%@example.com' or u.locale in ('zh-CN','en-US')) group by u.id,u.name,u.email having count(ro.id)>=0 order by total_spent desc,u.id asc;
```

检查点：

- CTE 应换行清晰。
- JOIN、WHERE、GROUP BY、HAVING、ORDER BY 应分段。
- 字符串里的 `%@example.com` 不能被改写。

### SQL-FMT-03 · 正确 SQL：DDL 和 INSERT

类型：正常

```sql
create table audit_logs(id bigserial primary key,actor_id bigint not null,action varchar(64) not null,payload jsonb not null default '{}'::jsonb,created_at timestamptz not null default now()); insert into audit_logs(actor_id,action,payload) values (101,'tool.format','{"tool":"json","success":true}'::jsonb),(102,'tool.compare','{"left":3,"right":4,"diff":1}'::jsonb);
```

### SQL-FMT-04 · SQL 方言样本：MySQL 反引号、PostgreSQL JSON、SQLite 引号

类型：正常

```sql
select `user`.id, `user`.`name` from `user` where json_extract(`settings`, '$.theme') = 'dark' limit 20 offset 10;
select id, payload->>'tool' as tool_name from audit_logs where payload @> '{"success": true}'::jsonb;
select "id", "name" from "users" where "name" like 'A%';
```

### SQL-FMT-05 · 错误 SQL：未闭合字符串

类型：错误

```sql
select id, name from users where email = 'alice@example.com;
```

### SQL-FMT-06 · 错误 SQL：结构不完整

类型：错误

```sql
select from where order by;
```

### SQL-FMT-07 · 边界 SQL：注释、复杂表达式、保留字作为列名

类型：边界

```sql
-- 单行注释应保留
select
  id,
  "order",
  /* 块注释应保留 */
  case when score >= 90 then 'A' when score >= 60 then 'B' else 'C' end as grade
from exam_results
where created_at between '2026-01-01' and '2026-12-31';
```

### SQL-FMT-08 · 正确 SQL：多语句脚本

类型：正常

```sql
begin; insert into logs(event, payload) values ('start', '{"ok":true}'); update users set last_seen_at = now() where id in (1,2,3); delete from sessions where expires_at < now(); commit;
```

检查点：

- 多个语句之间应有清晰分隔。
- `BEGIN`、`COMMIT` 不应被误当作普通标识符。
- JSON 字符串中的 `{}`、冒号和逗号不能影响 SQL 格式化。

### SQL-FMT-09 · 边界 SQL：转义字符串和转义标识符

类型：边界

```sql
select 'it''s ok' as message, "quoted""identifier" as ident, `quoted``identifier` as mysql_ident from "order" where note = '-- not a comment' and path like 'C:\\temp\\%';
```

检查点：

- SQL 字符串里的 `''`、`--`、反斜杠不能被误拆。
- 双引号标识符和 MySQL 反引号标识符应保留。
- `order` 作为保留字列名时不应被去掉引号。

### SQL-FMT-10 · 错误 SQL：括号不平衡

类型：错误

```sql
select * from users where id in (1, 2, 3;
```

预期：应直接提示括号未闭合；默认错误卡不显示 SQL 格式名、行号和列号前缀。

### SQL-FMT-11 · 错误 SQL：ORDER BY 缺少表达式

类型：错误

```sql
select id, name from users order by;
```

预期：应提示结构不完整，不能输出看似合法的格式化 SQL。

### SQL-FMT-12 · 选项 SQL：关键字大小写

类型：选项

```sql
select distinct id,name from users where active = 1 group by id,name order by name asc;
```

检查点：

- 大写模式应输出 `SELECT DISTINCT`、`WHERE`、`GROUP BY`、`ORDER BY`。
- 小写模式应输出 `select distinct`、`where`、`group by`、`order by`。
- 表名、字段名和字符串内容大小写不应被改写。

### SQL-FMT-13 · 方言边界：PostgreSQL dollar-quoted 字符串

类型：边界

```sql
do $$
begin
  raise notice 'hello; world';
end
$$;
select $tag$line 1;
line 2; -- this is text inside the literal
$tag$ as body;
```

预期：当前工具不支持 PostgreSQL dollar-quoted 字符串，应明确提示该方言边界；不能把字符串正文拆成多条 SQL 后伪成功。


### SQL-FMT-14 · 空输入与纯空白

类型：边界 / 交互

```sql

```

预期：安静（无错误、无输出）；`FormatRunner` → `.empty`。

### SQL-FMT-15 · 错误诊断关键语义

类型：错误 / 诊断

| 案例 | 输入摘要 | 预期诊断语义（关键词） |
|---|---|---|
| SQL-FMT-05 | 未闭合字符串 | 字符串/引号未闭合或词法错误 |
| SQL-FMT-06 | `select from where order by;` | 结构不完整 / 缺少表达式或表 |
| SQL-FMT-10 | 括号不平衡 | 括号不匹配 |
| SQL-FMT-11 | `order by;` | ORDER BY 缺少表达式 |

预期：抛出 `SQLFormatting.ValidationError`，展示中文 `FormatDiagnostic.displayMessage`；不得伪造成功格式化。

### SQL-FMT-16 · 选项 SQL：缩进宽度与前导逗号

类型：选项 / 核心覆盖

输入：

```sql
select id,name,email from users where id=1 and deleted_at is null
```

选项：

```text
keywordCase = lower
indentWidth = 4
commaStyle = leading
```

预期输出形态：

```sql
select
    id
  , name
  , email
from
    users
where
    id = 1
    and deleted_at is null
```

检查点：

- 缩进宽度应按 4 空格生效。
- 前导逗号只应用于顶层列表换行，不应破坏函数参数或字符串内容。
- 页面当前可固定为 2 空格和行尾逗号，但 Core 选项行为需要稳定。

## 3. XML 格式化

### XML-FMT-01 · 正确短 XML

类型：正常

```xml
<user id="1"><name>Alice</name><active>true</active></user>
```

### XML-FMT-02 · 正确长 XML：命名空间、CDATA、实体、属性

类型：复杂/压力

```xml
<?xml version="1.0" encoding="UTF-8"?><feed xmlns="https://example.com/feed" xmlns:app="https://example.com/app" version="1.0"><title>开发者工具箱 &amp; 测试数据</title><entry id="post-001" app:type="article"><title>JSON &lt;Formatter&gt;</title><author name="Rena" email="rena@example.com"/><content><![CDATA[<p>这里是不会被解析的 HTML 片段。</p><code>{"a":1}</code>]]></content><tags><tag>json</tag><tag>format</tag><tag>unicode-🙂</tag></tags></entry><entry id="post-002" app:type="note"><title>空节点测试</title><summary/><content>包含换行&#10;和实体 &quot;quote&quot;</content></entry></feed>
```

### XML-FMT-03 · 正确 XML：空节点和混合内容

类型：正常

```xml
<article><p>Hello <strong>world</strong>, this is <em>mixed</em> content.</p><br/><img src="/logo.png" alt="Logo"/></article>
```

### XML-FMT-04 · 错误 XML：标签不匹配

类型：错误

```xml
<root><item>one</items></root>
```

### XML-FMT-05 · 错误 XML：属性重复

类型：错误

```xml
<user id="1" id="2"><name>Alice</name></user>
```

### XML-FMT-06 · 错误 XML：未转义 &

类型：错误

```xml
<root><title>Tom & Jerry</title></root>
```

### XML-FMT-07 · 错误 XML：属性引号缺失

类型：错误

```xml
<root><item id=123>bad attribute</item></root>
```

### XML-FMT-08 · 正确 XML：注释、处理指令、空节点

类型：正常

```xml
<?xml version="1.0" encoding="UTF-8"?><root><?xml-stylesheet type="text/xsl" href="style.xsl"?><!-- keep this comment --><empty/><item enabled="true">value</item></root>
```

检查点：

- XML 声明、处理指令和注释应保留。
- 空节点可格式化为 `<empty/>` 或 `<empty></empty>`，但语义不能改变。

### XML-FMT-09 · 边界 XML：DOCTYPE 和外部实体安全

类型：安全

```xml
<!DOCTYPE root [
  <!ENTITY ext SYSTEM "file:///etc/passwd">
]>
<root>&ext;</root>
```

预期：当前工具直接拒绝 DOCTYPE，并提示“不支持 DOCTYPE 声明”；不能读取本地文件或展开外部实体。

### XML-FMT-10 · 错误 XML：多个根节点

类型：错误

```xml
<one>1</one><two>2</two>
```

预期：应提示 XML 文档只能有一个根节点。


### XML-FMT-11 · 空输入与纯空白

类型：边界 / 交互

预期：安静；`FormatRunner` → `.empty`。

### XML-FMT-12 · 错误诊断关键语义

类型：错误 / 诊断

| 案例 | 预期 |
|---|---|
| XML-FMT-04 标签不匹配 | 失败 + 标签不匹配诊断 |
| XML-FMT-05 属性重复 | 失败 |
| XML-FMT-06 未转义 `&` | 失败 |
| XML-FMT-07 属性缺引号 | 失败 |
| XML-FMT-10 多根 | 失败 |

预期：不得输出“修好后”的 XML；原输入保留。

## 4. YAML 格式化

### YAML-FMT-01 · 正确短 YAML

类型：正常

```yaml
id: 1
name: Alice
active: true
tags: [dev, ops]
```

### YAML-FMT-02 · 正确长 YAML：锚点、别名、多行字符串、列表、嵌套对象

类型：复杂/压力

```yaml
defaults: &defaults
  retries: 3
  timeout_ms: 120000
  headers:
    Accept: application/json
    X-Trace: "toolkit-test"

services:
  api:
    <<: *defaults
    image: example/api:2.4.0
    ports:
      - "8080:8080"
    environment:
      NODE_ENV: production
      FEATURE_FLAGS: "json,sql,xml,yaml"
    command:
      - node
      - server.js
  worker:
    <<: *defaults
    image: example/worker:2.4.0
    replicas: 2

release_notes: |
  第一行保持原样。
  第二行也保持换行。
  JSON 示例：{"id":1,"ok":true}

folded_text: >
  这段文字会被折叠成一行，
  但段落之间的空行需要保留。

numbers:
  int: 42
  float: 3.14159
  negative: -7
  quoted_number: "00123"

empty_values:
  empty_string: ""
  explicit_null: null
  tilde_null: ~
  empty_array: []
  empty_object: {}
```

### YAML-FMT-03 · YAML 边界：容易被解析成布尔值或日期

类型：边界

```yaml
values:
  yes_unquoted: yes
  no_unquoted: no
  on_unquoted: on
  off_unquoted: off
  date_unquoted: 2026-07-07
  quoted_yes: "yes"
  quoted_date: "2026-07-07"
```

预期：格式化结果保持这些标量的原始文本和引号状态，不把 `yes/no/on/off/date` 重新序列化成其他值。

### YAML-FMT-04 · 错误 YAML：缩进错误

类型：错误

```yaml
user:
  id: 1
 name: Alice
```

### YAML-FMT-05 · 错误 YAML：tab 缩进

类型：错误

```yaml
user:
	id: 1
	name: Alice
```

### YAML-FMT-06 · 错误 YAML：缺少冒号

类型：错误

```yaml
user
  id: 1
```

### YAML-FMT-07 · 错误 YAML：未定义别名

类型：错误

```yaml
service:
  <<: *missing_defaults
  image: nginx
```

### YAML-FMT-08 · 正确 YAML：流程风格对象和数组

类型：正常

```yaml
inline:
  list: [json, sql, xml]
  object: {enabled: true, retries: 3, path: "/tmp/a:b"}
  nested: [{name: api, ports: ["8080:80"]}, {name: worker, replicas: 2}]
```

检查点：

- 流程风格中的冒号、逗号、方括号不能被错误改写。
- 引号内的 `/tmp/a:b` 应保持原样。

### YAML-FMT-09 · 正确 YAML：块标量中的冒号、缩进和 shell

类型：正常

```yaml
script: |
  echo "start: $(date)"
  curl -H "Accept: application/json" https://example.com/api
  cat <<'JSON'
  {"id":1,"ok":true}
  JSON
next: value
```

检查点：

- `script` 块中的冒号、多空格、引号和缩进应原样保留。
- `next` 不能被误判为块标量内容。

### YAML-FMT-10 · 错误 YAML：引号未闭合

类型：错误

```yaml
name: "Alice
```

### YAML-FMT-11 · 错误 YAML：多个文档

类型：错误

```yaml
first: 1
---
second: 2
```

预期：当前工具只支持单文档 YAML，应明确提示只允许一个 YAML 文档。

### YAML-FMT-12 · 边界 YAML：重复 key

类型：边界

```yaml
service:
  image: nginx:1.25
  image: nginx:1.26
```

检查点：

- 当前 Yams parser 拒绝重复 key，页面应显示重复键诊断。
- 不能静默让用户误以为两个 `image` 都会生效。


### YAML-FMT-13 · 空输入与纯空白

类型：边界 / 交互

预期：安静；`FormatRunner` → `.empty`。

### YAML-FMT-14 · 错误诊断关键语义

类型：错误 / 诊断

| 案例 | 预期 |
|---|---|
| YAML-FMT-04 缩进错误 | 失败，诊断含缩进/扫描问题语义 |
| YAML-FMT-05 tab 缩进 | 失败（tab 作缩进） |
| YAML-FMT-07 未定义别名 | 失败 |
| YAML-FMT-10 引号未闭合 | 失败 |
| YAML-FMT-11 多文档 | 失败（本工具不支持多文档） |
| YAML-FMT-12 重复 key | 失败 |

预期：使用 `YAMLPrettifier.formatValidated`；`format` 兜底路径不得在页面上静默吞掉错误。

## 5. JSON 对比

### JSON-DIFF-01 · 结构相同，仅格式不同

类型：正常

左侧：

```json
{"id":1,"name":"Alice","roles":["admin","dev"],"profile":{"age":30,"city":"Shanghai"}}
```

右侧：

```json
{
  "id": 1,
  "name": "Alice",
  "roles": [
    "admin",
    "dev"
  ],
  "profile": {
    "age": 30,
    "city": "Shanghai"
  }
}
```

预期：结构化对比应判定无差异；纯文本对比会显示格式差异。

### JSON-DIFF-02 · 值变更、字段新增、字段删除

类型：正常

左侧：

```json
{
  "id": 1,
  "name": "Alice",
  "active": true,
  "plan": "free",
  "quota": 100,
  "profile": {
    "city": "Shanghai",
    "timezone": "Asia/Shanghai"
  }
}
```

右侧：

```json
{
  "id": 1,
  "name": "Alice Zhang",
  "active": false,
  "plan": "pro",
  "profile": {
    "city": "Beijing"
  },
  "lastLoginAt": "2026-07-07T10:00:00+08:00"
}
```

预期：

- `name`、`active`、`plan` 值不同。
- `quota`、`profile.timezone` 只在左侧存在。
- `lastLoginAt` 只在右侧存在。

### JSON-DIFF-03 · 数组顺序变化

类型：正常

左侧：

```json
{"ids":[1,2,3,4],"tags":["json","sql","xml"]}
```

右侧：

```json
{"ids":[4,3,2,1],"tags":["sql","json","xml"]}
```

预期：当前工具按数组位置比较，应显示多个位置差异；不提供忽略数组顺序的集合模式。

### JSON-DIFF-04 · 类型不同但显示相近

类型：正常

左侧：

```json
{"count":1,"enabled":true,"empty":null,"id":"001"}
```

右侧：

```json
{"count":"1","enabled":"true","empty":"","id":1}
```

预期：应识别数字、字符串、布尔、null 的类型差异。

### JSON-DIFF-05 · 深层嵌套差异

类型：正常

左侧：

```json
{
  "a": {
    "b": {
      "c": {
        "d": {
          "value": "left",
          "items": [
            {"id": 1, "ok": true},
            {"id": 2, "ok": true}
          ]
        }
      }
    }
  }
}
```

右侧：

```json
{
  "a": {
    "b": {
      "c": {
        "d": {
          "value": "right",
          "items": [
            {"id": 1, "ok": true},
            {"id": 2, "ok": false},
            {"id": 3, "ok": true}
          ]
        }
      }
    }
  }
}
```

### JSON-DIFF-06 · 错误 JSON 对比：右侧非法

类型：错误

左侧：

```json
{"id":1,"name":"Alice"}
```

右侧：

```json
{"id":1,"name":"Alice",}
```

预期：应指出右侧 JSON 解析失败，而不是输出误导性 diff。

### JSON-DIFF-07 · 错误 JSON 对比：左侧非法

类型：错误

左侧：

```json
{"id":1,"name":"Alice"
```

右侧：

```json
{"id":1,"name":"Alice"}
```

预期：应指出左侧 JSON 解析失败，并保留用户原始输入方便修正。

### JSON-DIFF-08 · 结构相同，key 顺序不同

类型：正常

左侧：

```json
{"a":1,"b":2,"c":{"x":10,"y":20}}
```

右侧：

```json
{"c":{"y":20,"x":10},"b":2,"a":1}
```

预期：结构化 JSON 对比应判定无差异；不能把对象 key 顺序变化当成数据差异。

### JSON-DIFF-09 · 边界 JSON 对比：重复 key

类型：边界

左侧：

```json
{"name":"first","name":"second"}
```

右侧：

```json
{"name":"second"}
```

预期：应提示重复 key 风险，或明确说明比较策略；不能无提示地按最后一个值吞掉差异。

### JSON-DIFF-10 · 大数组局部差异

类型：复杂/压力

左侧：

```json
{"items":[{"id":1,"status":"ok"},{"id":2,"status":"ok"},{"id":3,"status":"ok"},{"id":4,"status":"ok"},{"id":5,"status":"ok"}]}
```

右侧：

```json
{"items":[{"id":1,"status":"ok"},{"id":2,"status":"ok"},{"id":3,"status":"failed"},{"id":4,"status":"ok"},{"id":6,"status":"new"}]}
```

预期：应能定位到 `items[2].status` 和 `items[4].id/status` 的差异，不应只显示整段数组不同。

### JSON-DIFF-11 · 对比计算预算：超大多行数组

类型：压力/安全

生成左右输入（每侧约 3500 个数组元素，右侧只改最后一个值）：

```python
import json
left = {"items": list(range(3500))}
right = {"items": list(range(3499)) + [999999]}
print(json.dumps(left, ensure_ascii=False))
print(json.dumps(right, ensure_ascii=False))
```

预期：工具应在计算量超过预算时停止并显示“对比内容过大”一类诊断，不得长时间无响应或闪退；诊断后清空任一侧应能恢复正常使用。


### JSON-DIFF-12 · 双侧空输入

类型：边界 / 交互

左侧：

```json

```

右侧：

```json

```

预期：`JSONDiffValidation` / `JSONStructuralDiff` 为 `.empty`；页面不报错、不显示假差异。

### JSON-DIFF-13 · 错误文案含侧别标签

类型：错误 / 诊断

复用 `JSON-DIFF-06` / `JSON-DIFF-07`。

预期：

- 非法侧失败时消息能区分左侧/右侧（标签或“JSON A/B / Original/Compared”语义）。
- 合法侧内容不被清空。

### JSON-DIFF-14 · 顶层标量、空对象、空数组对比

类型：边界

顶层布尔差异：

左侧：

```json
true
```

右侧：

```json
false
```

顶层 null 与字符串差异：

左侧：

```json
null
```

右侧：

```json
"null"
```

空容器等价：

左侧：

```json
{"items":[],"meta":{}}
```

右侧：

```json
{"meta":{},"items":[]}
```

预期：

- 顶层标量是合法 JSON，应进入结构化 JSON 对比，而不是被当作空输入或非法输入。
- `null` 与 `"null"` 必须显示类型差异。
- 空对象、空数组和 key 顺序变化不应产生假差异。

## 6. 文本对比

### TEXT-DIFF-01 · 完全相同

类型：正常

左侧：

```text
Hello world
This line is unchanged.
最后一行中文。
```

右侧：

```text
Hello world
This line is unchanged.
最后一行中文。
```

### TEXT-DIFF-02 · 空格和大小写差异

类型：正常

左侧：

```text
Hello World
name: Alice
path: /Users/sun/project
```

右侧：

```text
hello world
name:  Alice
path:/Users/sun/project
```

### TEXT-DIFF-03 · 行新增、删除、移动

类型：正常

左侧：

```text
line 1: keep
line 2: remove me
line 3: move later
line 4: keep
```

右侧：

```text
line 1: keep
line 4: keep
line 3: move later
line 5: new line
```

### TEXT-DIFF-04 · 长文本差异

类型：正常

左侧：

```text
开发者工具应优先给出清晰、可恢复、可理解的错误信息。格式化工具尤其不能在输入非法时伪造成功结果，因为这会让用户把错误数据复制到生产配置中。对于较长文本，差异视图需要保持滚动同步、行号稳定，并且不要因为一行很长就破坏整体布局。
```

右侧：

```text
开发者工具应优先给出清晰、可恢复、可理解的错误信息。格式化工具不能在输入非法时伪造成功结果，因为这会让用户把错误数据复制到生产配置中。对于较长文本，差异视图需要保持滚动同步、行号稳定，并且不要因为某一行特别长就破坏整体布局。
```

### TEXT-DIFF-05 · 空文本和非空文本

类型：边界

左侧：

```text
```

右侧：

```text
only on right
```

### TEXT-DIFF-06 · 换行符边界

类型：边界

左侧内容使用 LF：

```text
one
two
three
```

右侧内容使用 CRLF，文本内容同样为：

```text
one
two
three
```

预期：当前按行对比会把 LF 和 CRLF 视为相同的行分隔方式，不产生内容差异；不能残留 `\r` 字符。

### TEXT-DIFF-07 · 行尾空格和尾随换行

类型：边界

左侧（`␠` 是可见标记；粘贴后把它替换成一个普通空格）：

```text
alpha
beta␠
gamma
```

右侧：

```text
alpha
beta
gamma
```

操作：右侧粘贴完成后，在 `gamma` 后再按一次回车，使右侧比左侧多一个尾随换行。

检查点：

- `beta` 行尾空格应可见或至少被计入差异。
- 文件末尾是否多一个换行应可识别。

### TEXT-DIFF-08 · Unicode 组合字符和 emoji

类型：正常

左侧：

```text
café
emoji: 👨‍💻
中文标点：，。
```

右侧：

```text
café
emoji: 👩‍💻
中文标点: ，。
```

检查点：

- `é` 的预组合字符和组合字符差异应稳定展示。
- emoji 不能导致索引错乱或崩溃。

### TEXT-DIFF-09 · 超长单行文本

类型：复杂/压力

左侧：

```text
token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

右侧：

```text
token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

检查点：

- 长行应自动换行或提供可读的横向浏览方式，不能把页面撑坏。
- 差异位置应能被找到。

### TEXT-DIFF-10 · 控制字符和 tab

类型：正常

左侧：

```text
col1	col2	col3
line with bell: 
```

右侧：

```text
col1    col2    col3
line with bell:
```

检查点：tab、空格和不可见控制字符差异应被安全处理。

### TEXT-DIFF-11 · 对比计算预算与恢复

类型：压力/安全

生成左右各 3500 行：

```python
left = "\n".join(f"line-{i}" for i in range(3500))
right = "\n".join(f"line-{i}" if i != 3499 else "line-changed" for i in range(3500))
print(left)
print("---RIGHT---")
print(right)
```

预期：超过 LCS 计算预算时应显示可理解诊断并停止计算，不得卡死或闪退；替换为短文本后错误应消失并恢复差异结果。


### TEXT-DIFF-12 · 双侧空文本

类型：边界

左侧与右侧均为空。

预期：`LineDiffer.diff` 返回空串，`safeAlignedDiff` 返回空数组；页面安静，不报错。

### TEXT-DIFF-13 · 预算错误文案

类型：压力 / 诊断

复用 `TEXT-DIFF-11` 的超大行数构造（自动化可用约 4000×4000 行合成数据触发 LCS 预算）。

预期错误文案包含：

```text
对比内容过大，无法计算
```

页面应将此写入非遮挡诊断区（ADR 0007）。

## 7. 正则测试

### REGEX-01 · 邮箱提取

类型：正常

Pattern:

```regex
\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b
```

Flags:

```text
g
```

Text:

```text
Contact: alice@example.com, bob.smith+dev@sub.example.co.uk, invalid@, @missing.local, qa@test.io.
```

预期匹配：

- `alice@example.com`
- `bob.smith+dev@sub.example.co.uk`
- `qa@test.io`

### REGEX-02 · 命名捕获组：日期

类型：正常

Pattern:

```regex
(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})
```

Flags:

```text
g
```

Text:

```text
release=2026-07-07, invalid=2026-7-7, next=2026-12-31
```

### REGEX-03 · 多行匹配

类型：正常

Pattern:

```regex
^ERROR\s+\[(.+?)\]\s+(.*)$
```

Flags:

```text
gm
```

Text:

```text
INFO [api] started
ERROR [worker] job failed
WARN [api] slow request
ERROR [db] connection timeout
```

### REGEX-04 · 贪婪与非贪婪

类型：正常

Pattern:

```regex
<tag>.*?</tag>
```

Flags:

```text
g
```

Text:

```text
<tag>one</tag><tag>two</tag><tag>three</tag>
```

### REGEX-05 · 前瞻：密码校验

类型：正常

Pattern:

```regex
^(?=.*[A-Z])(?=.*[a-z])(?=.*\d).{8,}$
```

Flags:

```text
gm
```

Text:

```text
Passw0rd
password
PASSWORD1
Short1
ValidPwd2026
```

预期：通过 `m` 按行应用锚点并通过 `g` 返回全部结果，匹配 `Passw0rd`、`ValidPwd2026`，其余三行不匹配。

### REGEX-06 · Unicode 字符

类型：正常

Pattern:

```regex
[\u4E00-\u9FFF]+
```

Flags:

```text
g
```

Text:

```text
Hello 世界, JSON 格式化, emoji 🙂, kana カタカナ
```

预期：应匹配 `世界`、`格式化` 等中文片段。

### REGEX-07 · 错误正则：括号未闭合

类型：错误

Pattern:

```regex
(abc
```

Text:

```text
abc abc
```

### REGEX-08 · 兼容性边界：变长后顾

类型：边界

Pattern:

```regex
(?<=\d{2,})abc
```

Text:

```text
1abc 12abc 123abc
```

预期：部分 JavaScript 正则引擎会报错，因为后顾长度不是固定值。

### REGEX-09 · 错误正则：不支持的 flag

类型：错误

Pattern:

```regex
abc
```

Flags:

```text
uy
```

Text:

```text
abc ABC
```

预期：当前工具若只支持 `gimsx`，应提示 `u` 或 `y` 不支持；不应先尝试编译正则。

### REGEX-10 · flag 行为：大小写、dotall、扩展注释

类型：正常

Pattern:

```regex
a . c # allow spaces and comments
```

Flags:

```text
isx
```

Text:

```text
A
C
abc
```

检查点：

- `i` 应忽略大小写。
- `s` 应允许 `.` 匹配换行。
- `x` 应忽略模式中的空白和 `#` 注释。

### REGEX-11 · 全局与首个匹配

类型：正常

Pattern:

```regex
\d+
```

Flags:

```text

```

Text:

```text
a1 b22 c333
```

预期：无 `g` 时只返回第一个匹配 `1`；加 `g` 后返回 `1`、`22`、`333`。

### REGEX-12 · 零长度匹配和空模式

类型：正常

Pattern:

```regex
(?=\w)
```

Flags:

```text
g
```

Text:

```text
ab cd
```

检查点：零长度匹配应显示范围且不能进入死循环。空 pattern 应显示 0 处匹配或明确提示。


### REGEX-13 · 空 pattern 与空测试文本

类型：边界

- pattern 为空、flags=`g`、文本任意：应返回 0 匹配，不报错。
- pattern 合法、测试文本为空：0 匹配，统计为 0。
- 页面不应把“0 匹配”显示为语法错误。

### REGEX-14 · 支持的 flags 集合与错误文案

类型：错误 / 诊断

支持：`g` `i` `m` `s` `x`（及组合）。

重复或带空白的 flags：

```text
 g i g
 i
```

预期：应规范化为 `gi`，不应因为空白或重复 flag 报错。

不支持示例：`u`、`y`、`A`。

预期错误：

```text
不支持的正则标志：u。当前支持 g、i、m、s、x。
```

非法 pattern 预期：

```text
括号未闭合。
```

### REGEX-15 · 错误正则：字符组范围顺序颠倒

类型：错误 / 诊断

Pattern:

```regex
[z-a]
```

Text:

```text
za
```

预期错误：

```text
字符组范围顺序无效。
```

### REGEX-16 · 错误正则：量词前缺少可重复内容

类型：错误 / 诊断

Pattern:

```regex
*abc
```

Text:

```text
abc
```

预期错误：

```text
量词前缺少表达式。
```

### REGEX-17 · 错误正则：量词下界缺失

类型：错误 / 诊断

Pattern:

```regex
a{,2}
```

Text:

```text
aa
```

预期错误：

```text
量词写法不完整。
```

### REGEX-18 · 捕获组、命名组与复制摘要

类型：正常 / 交互

Pattern:

```regex
(?<word>\w+)-(\d+)
```

Flags:

```text
g
```

Text:

```text
item-42 order-100 bad-item
```

预期：

- 匹配 `item-42`、`order-100`。
- 每个匹配应显示完整范围、普通捕获组 1/2 和命名组 `word`。
- 复制摘要应包含匹配数量、匹配范围、捕获组范围和命名组内容；不能只复制匹配文本。

### REGEX-19 · 常用预设按钮与示例文本

类型：交互 / 覆盖

操作：依次点击常用预设：

```text
手机号
邮箱
URL
HTML 标签
IPv4
强密码
日期
重复单词
UUID
Hex 颜色
```

检查点：

- 点击预设后，pattern、flags 和测试文本应立即替换为该预设的样例。
- 当前预设 chip 应呈选中态，切换预设后旧错误应清除或被新结果替代。
- 每个预设的正例应匹配，反例不应匹配。
- `重复单词` 预设应验证反向引用和 `gi` flag：`The the answer.` 匹配，`The theory is sound.` 不匹配。
- `HTML 标签` 预设应验证普通捕获组和反向引用：`<div>ok</div>` 匹配，`<div>bad</span>` 不匹配。

## 8. Docker Run → Compose

### DOCKER-01 · 最短命令

类型：正常

```bash
docker run nginx
```

预期 Compose 重点：

- `image: nginx`
- 默认服务名可自动生成。

### DOCKER-02 · 常见 Web 服务：端口、环境变量、卷、名称、后台运行

类型：正常

```bash
docker run -d --name dev-api -p 8080:80 -e NODE_ENV=production -e LOG_LEVEL=info -v /Users/sun/data:/app/data --restart unless-stopped example/api:2.4.0
```

预期 Compose 重点：

- `container_name: dev-api`
- `ports: ["8080:80"]`
- `environment` 包含两个变量。
- `volumes` 保留绝对路径。
- `restart: unless-stopped`

### DOCKER-03 · 命令参数、entrypoint、工作目录、用户

类型：正常

```bash
docker run --rm -it --name job-runner --entrypoint /bin/sh -w /workspace -u 1000:1000 -v "$PWD":/workspace node:22-alpine -lc "npm ci && npm test"
```

检查点：

- `--rm` 应记录为不可直接转换的结构化 warning；页面只显示统一主摘要，不列选项或处理过程。
- `-it` 可映射为 `stdin_open: true`、`tty: true`。
- 镜像后的 `-lc "npm ci && npm test"` 应完整保留为 command，不能丢失 `&&` 或拆错参数。

### DOCKER-04 · 网络、别名、hosts、DNS

类型：正常

```bash
docker run -d --name postgres-client --network dev-net --network-alias db-client --add-host host.docker.internal:host-gateway --dns 1.1.1.1 postgres:16 psql -h db -U app
```

检查点：

- network 名称应出现在 `networks`。
- `extra_hosts`、`dns` 应被保留。
- 镜像后的 `psql -h db -U app` 应进入 command。

### DOCKER-05 · 资源、权限、设备、健康检查、标签

类型：正常

```bash
docker run -d --name gpu-worker --gpus all --privileged --cap-add NET_ADMIN --device /dev/fuse:/dev/fuse --memory 2g --cpus 1.5 --health-cmd "curl -f http://localhost:9000/health || exit 1" --health-interval 30s --label com.example.role=worker example/gpu-worker:latest
```

检查点：

- `privileged`、`cap_add`、`device`、`memory`、`cpus`、label 和 healthcheck 应写入对应 Compose 字段。
- `--gpus all` 应转换为 GPU reservation；本案例不应产生 warning。
- healthcheck 的命令和 `interval: 30s` 应保留。

### DOCKER-06 · 复杂环境变量：空值、引号、等号

类型：正常

```bash
docker run --name env-test -e EMPTY= -e TOKEN="abc=123==xyz" -e JSON='{"enabled":true,"count":3}' alpine:3.20 env
```

检查点：

- `EMPTY` 应保留为空字符串。
- 包含等号的值不能被截断。
- JSON 字符串不能被错误拆分。

### DOCKER-07 · 错误 Docker 命令：缺少镜像

类型：错误

```bash
docker run -d --name missing-image -p 8080:80
```

### DOCKER-08 · 错误 Docker 命令：未知或拼写错误 flag

类型：错误

```bash
docker run --naem typo-nginx -p 8080:80 nginx
```

### DOCKER-09 · 错误 Docker 命令：引号未闭合

类型：错误

```bash
docker run -e MESSAGE="hello nginx
```

### DOCKER-10 · Docker：env-file、hostname、expose、只读和 init

类型：正常

```bash
docker run --name web --hostname web-1 --env-file .env --env-file ./secrets.env --expose 9000 --read-only --init nginx:1.25
```

检查点：

- `env_file` 应包含两个文件。
- `hostname`、`expose`、`read_only`、`init` 应分别写入对应 Compose 字段。
- 相对路径不能被错误改成绝对路径。

### DOCKER-11 · Docker：--mount、tmpfs、命名卷和端口协议

类型：正常

```bash
docker run --name storage -p 127.0.0.1:8080:80/tcp -p 53:53/udp --mount type=bind,source=$(pwd)/site,target=/usr/share/nginx/html,readonly --mount type=volume,source=cache-data,target=/cache --tmpfs /run:size=64m nginx
```

检查点：

- `127.0.0.1:8080:80/tcp` 可去掉默认 `/tcp`，但 UDP 端口必须保留 `/udp`。
- bind mount 应转换为卷映射并保留只读。
- 命名卷应出现在服务 `volumes`，必要时声明顶层 `volumes`。
- tmpfs 应进入 `tmpfs`。

### DOCKER-12 · Docker：inline flag 和组合短 flag

类型：正常

```bash
docker run -itd --name=inline -p8080:80 -eAPP_ENV=prod -v$(pwd)/data:/data:ro --restart=on-failure:3 alpine:3.20 sh
```

检查点：

- `-itd` 应拆成交互、TTY、后台运行边界提示。
- `--name=inline`、`-p8080:80`、`-eAPP_ENV=prod`、`-v...` 应正确解析。
- `--restart=on-failure:3` 应写入唯一的 `deploy.restart_policy.condition: on-failure` 和 `max_attempts: 3`，不能生成重复 `deploy:`。

### DOCKER-13 · Docker：不支持但已知的 flag

类型：正常

```bash
docker run --cidfile /tmp/nginx.cid --publish-all nginx
```

预期：应生成 `image: nginx`，保留 `--cidfile`、`--publish-all` 的结构化 warning，并显示统一主摘要；不能把 `/tmp/nginx.cid` 当成镜像。

### DOCKER-14 · 错误 Docker 命令：多个 docker run 粘贴在一起

类型：错误

```bash
docker run --rm alpine sh docker run --rm alpine sh
```

预期：应提示输入包含多个命令，不能把第二个 `docker run` 当作第一个容器的 command。

### DOCKER-15 · Docker：YAML 转义边界

类型：边界

```bash
docker run --env WIN=C:\Temp\new --env "CTRL=line	break" --label note="A # B: C" nginx
```

检查点：

- 反斜杠、tab、`#`、冒号应被正确 YAML 转义。
- 输出的 Compose YAML 不应产生语法错误。


### DOCKER-16 · 错误诊断与 warning 文案（页面映射）

类型：错误 / 警告 / 诊断

| 场景 | Core 错误/警告 | 页面预期文案关键词 |
|---|---|---|
| 非 docker run | `invalidCommand` | 仅支持单条 docker run 命令 |
| 多命令 | `multipleCommands` | 一次只能转换一条 docker run 命令 |
| 缺镜像 | `missingImage` | docker run 命令缺少镜像名称 |
| 缺选项值 | `missingOptionValue` | 选项缺少参数值 |
| 未闭合引号 | `unterminatedQuote` | 未闭合的引号 |
| `-d` 等 | `notTranslatable` | 部分 Docker 选项无法转换 |
| `--cidfile`、`--publish-all` 等 | `notImplemented` 或同类 | 部分 Docker 选项无法转换 |
| `--naem` | `unknownFlag` | 部分 Docker 选项无法转换 |

### DOCKER-17 · 输入过长（页面预算）

类型：压力 / 安全

构造 trim 后长度 > `200_000` 的输入（页面常量 `maxInputCharacters`）。

预期：

```text
输入内容过长，最多支持 200000 个字符。
```

- 不调用或不等待超长成功输出。
- 缩短输入后应恢复可转换。

说明：Core `convert` 本身未必实现同一字符上限；此案例验收 **页面层** 保护。

### DOCKER-18 · 空输入

类型：边界

空或纯空白：安静，清空输出与 warning/error。

### DOCKER-19 · Docker：Compose 已支持的 platform 与禁用 healthcheck

类型：正常

```bash
docker run --platform linux/amd64 --no-healthcheck nginx
```

检查点：

- 应生成 `image: nginx`。
- 应生成 `platform: linux/amd64`。
- 应生成：

```yaml
healthcheck:
  disable: true
```

- 不应再把 `--platform`、`--no-healthcheck` 作为“不支持”或“暂未实现” warning。

### DOCKER-20 · Docker：其余已支持 flag 覆盖矩阵

类型：正常 / 覆盖

```bash
docker run --name matrix --user 1000:1000 --workdir /workspace --entrypoint /bin/sh --network dev-net --network-alias matrix --dns 1.1.1.1 --dns-opt ndots:1 --dns-search example.com --ip 172.20.0.10 --ip6 2001:db8::10 --mac-address 02:42:ac:11:00:02 --pid host --uts host --ipc host --cap-add NET_ADMIN --cap-drop ALL --security-opt no-new-privileges --userns host --group-add 1001 --sysctl net.ipv4.ip_forward=1 --ulimit nofile=1024:2048 --device /dev/fuse:/dev/fuse --device-read-bps /dev/sda:1mb --device-write-bps /dev/sda:2mb --device-read-iops /dev/sdb:100 --device-write-iops /dev/sdb:200 --cpuset-cpus 0-3 --cpu-shares 512 --cpu-period 100000 --cpu-quota 50000 --memory 512m --memory-reservation 256m --memory-swap 1g --memory-swappiness 10 --pids-limit 128 --blkio-weight 300 --shm-size 64m --oom-score-adj -500 --log-driver json-file --log-opt max-size=10m --stop-signal SIGTERM --stop-timeout 15 --gpus all --init --oom-kill-disable alpine:3.20
```

host 网络专用样本：

```bash
docker run --network host nginx
```

检查点：

- 自定义网络样本应保留 `networks`、网络别名、静态 IPv4/IPv6 和 MAC 地址。
- host 网络专用样本应转成 `network_mode: host`。
- `--dns`、`--dns-opt`、`--dns-search`、`--pid`、`--uts`、`--ipc` 应各自落到对应 Compose 字段。
- `--cap-add`、`--cap-drop`、`--security-opt`、`--userns`、`--group-add`、`--sysctl`、`--ulimit`、`--device*`、`--cpu*`、`--memory*`、`--pids-limit`、`--blkio-weight`、`--shm-size`、`--oom-score-adj`、`--log-*`、`--stop-signal`、`--stop-timeout`、`--gpus`、`--init`、`--oom-kill-disable` 应都能保留或得到明确 warning。
- 生成结果必须通过 `docker compose config --quiet`；`blkio_config.weight` 等数值字段不能错误输出成字符串。
- 这一组用于确认转换器覆盖了除最常见 Web 服务以外的资源、网络、安全和日志 flag，不得只在“常见命令”样本里看起来正常。

## 9. HTML → Markdown

### HTML-MD-01 · 简单 HTML

类型：正常

```html
<h1>Title</h1><p>Hello <strong>world</strong>. Visit <a href="https://example.com">Example</a>.</p>
```

预期 Markdown：

- `# Title`
- `**world**`
- `[Example](https://example.com)`

### HTML-MD-02 · 长 HTML：标题、段落、列表、表格、代码、引用、图片

类型：复杂/压力

```html
<article>
  <h1>开发者工具箱发布说明</h1>
  <p>这个版本改进了 <strong>JSON 格式化</strong>、<em>文本对比</em> 和 <code>Docker Run → Compose</code>。</p>
  <h2>功能列表</h2>
  <ul>
    <li>支持 Unicode 文本。</li>
    <li>保留代码块和链接。</li>
    <li>尽量转换表格。</li>
  </ul>
  <h2>对比表</h2>
  <table>
    <thead>
      <tr><th>工具</th><th>输入</th><th>输出</th></tr>
    </thead>
    <tbody>
      <tr><td>JSON</td><td>压缩 JSON</td><td>格式化 JSON</td></tr>
      <tr><td>HTML</td><td>HTML 文档</td><td>Markdown</td></tr>
    </tbody>
  </table>
  <blockquote>
    <p>错误输入不能伪装成成功输出。</p>
  </blockquote>
  <pre><code>const ok = true;
console.log(JSON.stringify({ ok }, null, 2));</code></pre>
  <p><img src="/assets/toolkit.png" alt="工具箱截图" title="Toolkit"></p>
</article>
```

检查点：

- 标题层级应保留。
- 表格应转换为 Markdown 表格，或给出可理解的降级结果。
- 代码块不能丢失换行。
- 图片 alt、src、title 应尽量保留。

### HTML-MD-03 · HTML 实体、换行、空白

类型：正常

```html
<p>Tom &amp; Jerry &lt;Cartoon&gt; &quot;Quote&quot;</p>
<p>Line one<br>Line two<br/>Line three</p>
```

### HTML-MD-04 · 嵌套链接和强调边界

类型：边界

```html
<p><strong>Bold <em>and italic</em></strong> text with <a href="/docs"><code>/docs</code> link</a>.</p>
```

### HTML-MD-05 · 应忽略或安全处理的 script/style

类型：安全

```html
<style>
  body { color: red; }
</style>
<script>
  alert("xss");
</script>
<h1>Visible Title</h1>
<p>Visible paragraph.</p>
```

预期：Markdown 输出不应执行脚本；通常应忽略 `script` 和 `style` 内容，保留可见正文。

### HTML-MD-06 · 错误或不完整 HTML：标签未闭合、嵌套异常

类型：错误

```html
<div><h1>Broken HTML<p>Paragraph <strong>bold <em>italic</strong></p></div>
```

检查点：

- 转换器应尽量恢复正文。
- 不应崩溃或产生空输出。

### HTML-MD-07 · 表单元素和不常见标签

类型：正常

```html
<form action="/search" method="get">
  <label>Keyword <input name="q" value="json"></label>
  <button type="submit">Search</button>
</form>
<details open>
  <summary>More</summary>
  <p>Hidden by default in HTML, but should be visible in Markdown if converted.</p>
</details>
```

### HTML-MD-08 · 表格单元格包含管道符

类型：正常

```html
<table>
  <tr><th>Name</th><th>Value</th></tr>
  <tr><td>A | B</td><td><strong>1 | 2</strong></td></tr>
</table>
```

预期：Markdown 表格单元格里的 `|` 应转义为 `\|`，否则会破坏列数。

### HTML-MD-09 · 注释、水平线、有序列表、删除线

类型：正常

```html
<!-- internal note should not appear -->
<h2>Steps</h2>
<ol>
  <li>Install</li>
  <li><del>Skip tests</del> Run tests</li>
</ol>
<hr>
```

检查点：

- 注释不应出现在 Markdown 正文。
- 有序列表编号应稳定。
- `<del>` 或 `<strike>` 应转换为删除线，或退化为可读文本。
- `<hr>` 应转换为分隔线。

### HTML-MD-10 · 链接、图片属性顺序和相对地址

类型：正常

```html
<p><a title="Docs" href="/docs/getting-started">Docs</a> and <a href="mailto:qa@example.com">Email QA</a></p>
<p><img alt="Logo" title="Brand" src="../assets/logo.svg"></p>
```

检查点：

- 相对链接、`mailto:` 链接应保留。
- 图片 `alt` 在 `src` 前时也应能识别。
- `title` 可保留或忽略，但不能破坏基本图片语法。

### HTML-MD-11 · 数字实体和未知实体

类型：正常

```html
<p>&#20320;&#22909; &#x1F600; &copy; &unknown;</p>
```

检查点：

- 十进制和十六进制实体应尽量解码。
- 未知实体应保留为文本或安全降级，不能丢失相邻内容。

### HTML-MD-12 · 嵌套列表与 GFM 任务项

类型：正常

```html
<ul>
  <li><input type="checkbox" checked> 已完成
    <ul><li>子任务 A</li></ul>
  </li>
  <li><input type="checkbox"> 未完成</li>
</ul>
<ol start="3"><li>第三项</li><li>第四项</li></ol>
```

检查点：

- checkbox 应转换成 `- [x]` / `- [ ]` 一类任务列表语法。
- 嵌套列表缩进必须保持层级，不能全部压成同级。
- 有序列表应保持稳定递增；若不支持 `start=3`，应明确这是降级边界。

### HTML-MD-13 · 代码语言提示、反引号与空白保真

类型：边界

```html
<p>Use <code>const value = `tick`;</code> inline.</p>
<pre><code class="language-swift">let value = "a  b"
print(value)
</code></pre>
```

检查点：

- 行内代码自身包含反引号时，Markdown delimiter 不应与内容冲突。
- fenced code block 应尽量保留 `swift` 语言提示、换行和代码内连续空格。
- HTML 实体应在代码语境中解码一次，不能二次转义。

### HTML-MD-14 · 不安全元素与不可等价媒体 warning

类型：安全

```html
<h1>Visible</h1>
<script>alert('xss')</script>
<style>body{display:none}</style>
<template><p>template-only</p></template>
<iframe src="https://example.com/embed"></iframe>
<video src="movie.mp4">Video fallback</video>
<audio src="sound.mp3">Audio fallback</audio>
<svg><text>Vector label</text></svg>
<p>Still visible</p>
```

预期：

- `script`、`style`、`template` 内容不得进入输出，并应出现去除类 warning。
- iframe/video/audio/svg 不得被当作可执行内容；若无法等价转换，应保留安全可见文本或给出不支持 warning。
- `Visible` 与 `Still visible` 必须保留。

### HTML-MD-15 · rowspan/colspan 表格降级

类型：边界

```html
<table>
  <tr><th rowspan="2">Name</th><th colspan="2">Scores</th></tr>
  <tr><th>Math</th><th>English</th></tr>
  <tr><td>Alice</td><td>95</td><td>88</td></tr>
</table>
```

预期：输出可以展平为普通 GFM 表格，但必须出现“rowspan/colspan 无法等价表达、已展平”一类 warning；不能静默声称完全等价。

### HTML-MD-16 · URL 输入：bare domain、成功获取与重定向后地址

类型：网络/交互

输入 URL：

```text
example.com
```

检查点：

- bare domain 应规范化为 `https://example.com`。
- 点击“获取”期间按钮应有明确加载/禁用状态，完成后 HTML 输入和 Markdown 输出一起更新。
- 使用重定向后的最终响应 URL 作为 base URL，而不是始终使用用户最初输入的 URL。
- 此案例依赖网络，只能作为手工烟测，不应作为离线自动化质量门。

### HTML-MD-17 · URL 响应中的相对链接与图片

类型：网络/边界

受控 HTTP fixture：最终响应 URL 为 `https://example.com/docs/page.html`，响应正文：

```html
<p><a href="../guide">Guide</a></p>
<p><img src="/assets/logo.png" alt="Logo"></p>
```

预期输出应包含：

```markdown
[Guide](https://example.com/guide)

![Logo](https://example.com/assets/logo.png)
```

检查点：只能用 URL 获取入口或核心 API 验证；直接粘贴 HTML 没有 base URL 时，相对地址保持相对形式是合理行为。

### HTML-MD-18 · URL 错误模型

类型：错误

依次验证：

```text
（空字符串）
file:///tmp/test.html
https://
https://example.com/404
```

预期：UI 中空 URL 时“获取”按钮应禁用；核心服务直接接收空字符串时应返回空 URL 错误。其余输入分别得到协议不支持、URL 无效、HTTP 状态不可接受等明确诊断。失败后不应保留上一次 URL 请求的输出，也不能让较早完成的请求覆盖较新的输入/清空操作。

### HTML-MD-19 · URL 响应编码、空响应与 5 MiB 上限

类型：边界/压力

使用受控 HTTP fixture 验证：

- `Content-Type: text/html; charset=iso-8859-1`，正文 bytes 对应 `café`，应正确解码。
- HTTP 200 但 body 为空，应显示空响应错误。
- body 超过 5 MiB，应中止读取并显示响应过大错误，而不是先完整加载到内存后再判断。

### HTML-MD-20 · 大 HTML 的实时转换与显式转换

类型：压力/交互

生成大于 512000 UTF-8 bytes 的 HTML，例如重复以下段落 20000 次：

```html
<p>large input 🙂 <strong>content</strong></p>
```

预期：

- 粘贴后暂停实时转换，输出清空，并提示点击“转换”。
- 点击显式“转换”后允许处理完整输入；期间界面不得卡死或错误显示旧输出。
- 将输入缩短到阈值以下后，应恢复实时转换，旧 warning 应被清除。

### HTML-MD-21 · 无可见正文

类型：边界

```html
<!doctype html>
<html><head><title>Only title</title><meta charset="utf-8"></head><body><!-- comment --></body></html>
```

预期：Markdown 输出为空，并显示“未检测到可见内容”一类 warning；不能把 `<title>` 或注释当正文输出。


### HTML-MD-22 · 空输入与无可见正文诊断

类型：边界

- 空/纯空白 HTML：应安静或产生空 Markdown，不得崩溃。
- 仅有 `<div></div>` / 仅 script·style：应出现 `emptyVisibleContent` 类 warning，或等价“无可见正文”提示（ADR 0008 best-effort）。

### HTML-MD-23 · warning 必须可见

类型：警告

复用含 `<script>`、`<video>`、rowspan 表格等样本。

预期：`HTMLToMarkdownConversionResult.warnings` 非空时，页面诊断区展示；不得只成功输出却完全隐藏边界信息。

## 10. 快速回归组合样本

这一段用于一次性覆盖多个工具的“容易误判”输入。

### CROSS-01 · 看起来像 JSON，但不是合法 JSON

类型：正常

```json
{
  "docker": "docker run -e JSON='{\"ok\":true}' nginx",
  "sql": "select * from users where name = 'Alice'",
  "yaml_like": yes,
}
```

### CROSS-02 · 看起来像 YAML，里面包含 JSON、SQL、HTML

类型：正常

```yaml
payloads:
  json: '{"id":1,"ok":true}'
  sql: "select id,name from users where active=1"
  html: "<p>Hello <strong>world</strong></p>"
  regex: "\\b\\w+@example\\.com\\b"
```

### CROSS-03 · 纯文本中包含多种格式片段

类型：正常

```text
用户输入：
{"id":1,"name":"Alice"}

SQL:
select * from users where id = 1;

HTML:
<p>Hello <strong>world</strong></p>

Docker:
docker run -p 8080:80 nginx
```

## 11. Crontab 生成

### CRON-01 · 常见表达式：每 5 分钟

类型：正常

```cron
*/5 * * * *
```

检查点：

- 应解释为每 5 分钟运行。
- 应给出接下来若干次运行时间。
- 分钟字段范围应限定在 `0-59`。

### CRON-02 · 常见表达式：工作日 9 点

类型：正常

```cron
0 9 * * 1-5
```

检查点：

- 应解释星期字段为周一到周五。
- 下次运行时间不应落在周六或周日。

### CRON-03 · 名称表达式：月份和星期英文缩写

类型：正常

```cron
30 8 1 JAN,MAR MON-FRI
```

检查点：

- `JAN`、`MAR`、`MON-FRI` 应被接受并解释。
- 大小写应尽量不敏感；如果只支持大写，应明确提示。

### CRON-04 · 特殊表达式：@reboot

类型：正常

```cron
@reboot
```

预期：应视为有效的启动时任务，但不应强行生成日历预览；说明区可以提示“没有固定日历预览”。

### CRON-05 · 边界表达式：星期日 0 和 7

类型：边界

```cron
0 0 * * 0
```

```cron
0 0 * * 7
```

检查点：两者都应表示星期日，不能把 `7` 当作越界。

### CRON-06 · 错误表达式：字段数量错误

类型：错误

```cron
*/5 * * *
```

预期：应提示 cron 表达式需要 5 个字段。

### CRON-07 · 错误表达式：字段超范围

类型：错误

```cron
60 24 32 13 8
```

预期：应提示字段超出范围或格式无效。

### CRON-08 · 错误表达式：步长为 0

类型：错误

```cron
*/0 * * * *
```

预期：应提示步长非法，不能进入无限循环。

### CRON-09 · 关键字宏：hourly / daily / weekly / monthly / yearly

类型：正常

依次输入：

```cron
@hourly
@daily
@midnight
@weekly
@monthly
@yearly
@annually
```

检查点：

- 应分别解析为标准五字段表达式并给出下一次运行时间。
- 关键字大小写应不敏感。
- `@yearly` 与 `@annually`、`@daily` 与 `@midnight` 应分别语义等价。


### CRON-10 · 空输入

类型：边界

空表达式：不应显示“下次运行”伪结果；可显示占位或要求输入。页面当前对非法/空有错误或空解释时，不得崩溃。

### CRON-11 · 错误提示关键词

类型：错误 / 诊断

| 输入 | 页面/逻辑预期 |
|---|---|
| `*/5 * * *`（4 字段） | 需要 5 个字段 / 无效 |
| `60 * * * *` | 超出范围或格式无效 |
| `*/0 * * * *` | 无效（步长 0） |

Core：`CronScheduler.parseFields` 对上述返回 `nil`。

### CRON-12 · 大小写名称、严格通配符和混合步长

类型：正常 / 错误

```cron
0/15 9-17/2 * feb-apr mon,wed,fri
```

检查点：

- 标准 Unix 五字段 crontab 只使用 `*` 作为通配符。
- 月份名称与星期名称大小写应不敏感。
- `0/15`、`9-17/2` 这类步长/范围组合应能解析。
- `mon,wed,fri` 应得到周一、周三、周五。
- `0 9 ? * 1` 必须报“日字段格式无效”；`?` 是 Quartz 扩展，不得静默兼容为 Unix crontab 通配符。

## 12. 可用端口

### PORT-01 · 基础分配

类型：交互

操作：打开“可用端口”，点击“重新生成”。

检查点：

- 输出应是 `1...65535` 内的整数 TCP 端口。
- 页面必须说明结果只是当前可用候选，socket 已释放且端口未保留占用。
- 成功时复制按钮复制端口数字；没有结果或分配失败时复制按钮禁用。

### PORT-02 · 连续分配

类型：交互

操作：连续点击“重新生成”20 次，记录输出。

检查点：

- 每次成功结果都来自系统对 TCP socket 绑定 port `0` 后返回的端口。
- 页面不应卡顿或保留旧错误状态。
- 系统可以再次分配相同端口；不得以“结果必须不同”作为正确性条件。

### PORT-03 · 失败与恢复

类型：错误 / 恢复

通过可注入 socket client 分别模拟：

- 创建 socket 失败；
- bind 失败；
- `getsockname` 失败；
- 系统返回无效端口。

检查点：

- Core 返回对应的 typed `AllocationError`，且已创建的 socket 在所有路径关闭。
- 页面显示稳定、事实性的诊断，不展示 `errno` 或底层错误文本。
- 失败后清空旧输出并禁用复制；下一次成功生成后清除错误并恢复复制。

### PORT-04 · 契约断言（自动化）

类型：契约

- `AvailableTCPPortAllocator` 依次执行 TCP socket 创建、port `0` bind、`getsockname` 和 close。
- ToolID 保持 `random-port-generator`；显示名为“可用端口”。
- 搜索关键词继续包含 `port`、`random` 和“随机端口”。
- 真实系统 smoke 只断言本次返回有效 TCP 端口候选，不断言 socket 释放后该端口持续空闲。

## 13. Chmod 计算器

### CHMOD-01 · 默认权限：644

类型：正常

选择：

```text
所有者: r=true, w=true, x=false
所属组: r=true, w=false, x=false
其他: r=true, w=false, x=false
```

预期：

```text
644
rw-r--r--
chmod 644
```

### CHMOD-02 · 可执行文件：755

类型：正常

选择：

```text
所有者: r=true, w=true, x=true
所属组: r=true, w=false, x=true
其他: r=true, w=false, x=true
```

预期：

```text
755
rwxr-xr-x
chmod 755
```

### CHMOD-03 · 私有密钥：600

类型：正常

选择：

```text
所有者: r=true, w=true, x=false
所属组: r=false, w=false, x=false
其他: r=false, w=false, x=false
```

预期：

```text
600
rw-------
chmod 600
```

### CHMOD-04 · 无权限：000

类型：正常

选择：

```text
所有者: r=false, w=false, x=false
所属组: r=false, w=false, x=false
其他: r=false, w=false, x=false
```

预期：

```text
000
---------
chmod 000
```

### CHMOD-05 · 全权限：777

类型：正常

选择：

```text
所有者: r=true, w=true, x=true
所属组: r=true, w=true, x=true
其他: r=true, w=true, x=true
```

预期：

```text
777
rwxrwxrwx
chmod 777
```

### CHMOD-06 · 执行位边界：111

类型：边界

选择：

```text
所有者: r=false, w=false, x=true
所属组: r=false, w=false, x=true
其他: r=false, w=false, x=true
```

预期：

```text
111
--x--x--x
chmod 111
```

### CHMOD-07 · 特殊权限位

类型：正常 / 边界

| 输入 | 特殊位 | 符号权限 |
|---|---|---|
| `4755` | setuid | `rwsr-xr-x` |
| `2750` | setgid | `rwxr-s---` |
| `1777` | sticky | `rwxrwxrwt` |
| `7644` | setuid + setgid + sticky，且执行位关闭 | `rwSr-Sr-T` |

检查点：

- 四位输入与 setuid/setgid/sticky 开关双向同步。
- 执行位开启时使用小写 `s/t`，关闭时使用大写 `S/T`。
- 结果保留有意义的特殊位前缀；普通 `0644` 规范化显示为 `644`。

### CHMOD-08 · 八进制输入与矩阵双向同步

类型：交互 / 状态

1. 输入 `4755`：矩阵和 setuid 必须原子更新。
2. 关闭所有者执行位：输入应回填为 `4655`，符号结果为 `rwSr-xr-x`。
3. 再输入 `1777`：sticky 与三组 rwx 应同步，旧错误清除。

检查点：

- 数字输入是完整 mode 的单一入口，不允许只更新部分矩阵。
- 任一开关变化后，八进制 draft 立即回填为规范化 mode。
- 结果复制使用当前完整八进制 mode。

### CHMOD-09 · 非法输入保持最后有效状态

类型：错误 / 恢复

| 输入 | 预期 |
|---|---|
| `64` / `06444` | 需要 3 位或 4 位 |
| `6a4` | 只能包含数字 |
| `684` | 每一位只能是 0–7 |

检查点：

- 非法 draft 保留在输入框中并显示事实性诊断。
- 权限矩阵与结果继续表示最后一个完整合法 mode，不进入部分无效状态。
- 改回合法 mode 后错误消失，输入、矩阵、特殊位和结果重新同步。

### CHMOD-10 · 符号与八进制一致性矩阵（抽样）

类型：正常 / 契约

对 `000`、`111`、`644`、`600`、`755`、`777`、`4755`、`2750`、`1777`、`7644`：

- `ChmodMode.octalString` 与 `symbolicString` 一致于 POSIX 特殊位表示。
- UI 展示 `chmod <octal>` 时数字、rwx 矩阵与特殊位开关同步。

## 附录 A：所有工具的通用交互回归

对每个适用页面至少执行一次：

1. 空输入打开页面：不应立即显示错误。
2. 输入合法短样本，再输入错误样本：旧成功输出应清空或明确失效。
3. 从错误样本改回合法样本：错误应消失，输出恢复。
4. 点击清空：输入、输出、错误、warning、加载状态全部复位。
5. 复制输出：剪贴板内容与当前完整输出一致；占位符或空输出时复制按钮应禁用或不复制无意义文本。
6. 重复快速操作：不会让早先的异步结果覆盖新输入；HTML URL 获取尤其需要验证。
7. 极长单行：内容可换行或在编辑器内部合理滚动，不造成整个页面横向溢出。
8. 窄窗口：控制区不遮挡编辑器，错误/warning 不覆盖正文或操作按钮。
9. 键盘编辑：撤销/重做、全选、复制、粘贴保持可用；输出只读但可选择。
10. 切换格式化选项或 flags：只改变对应行为，不应清空无关输入。

## 附录 B：结果记录模板

```text
案例编号：
工具：
环境 / commit：
结果：通过 / 失败 / 明确边界 / 环境未验证
复现步骤：
实际结果：
预期结果：
是否稳定复现：
截图或测试命令：
备注：
```
