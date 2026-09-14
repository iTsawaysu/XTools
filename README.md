<div align="center">

<img src="Assets/AppIcon/XToolsIcon.png" width="128" height="128" alt="XTools 应用图标"/>

# XTools

**原生 macOS 工具箱，收录日常开发与文本处理常用工具**

_An open-source, native macOS toolbox for everyday development and text processing._

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-black?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-3DA639)](LICENSE)

[下载](https://github.com/iTsawaysu/XTools/releases) · [工具列表](#工具列表) · [参与贡献](#参与贡献)

</div>

## 为什么做 XTools

写代码、处理文本时，总会遇到一些顺手就要用一下的小事：转个 Base64、格式化一段 JSON、看一眼时间戳、生成一个强密码……为了这些事反复开网页、装一堆零散软件，太重了。

XTools 把这些工具放进一个原生 macOS 应用，通过侧边栏分类浏览，也可以按 `⌘K` 搜索直达。常用转换在本地完成，读取网页等功能按需联网。

## 工具列表

共 46 个工具，分为 7 类。

| 分类 | 工具 |
|---|---|
| 编码与转换 | Base64 文件 · Base64 字符串 · URL 编解码 · ASCII / 二进制 · Unicode 转换 · 进制转换 · 罗马数字 · 大小写转换 |
| 加密与生成 | Hash 文本 · 文本加密 · 字符串遮蔽 · Token 生成器 · UUID 生成器 · 密码生成器 |
| 开发 | JSON 格式化 · SQL 格式化 · XML 格式化 · YAML 格式化 · JSON 对比 · 文本对比 · 正则测试 · Docker Run → Compose · HTML → Markdown · Crontab 生成 · 随机端口 · Chmod 计算器 |
| Web | JWT · Basic Auth · HTTP 状态码 · User-Agent 解析 · 键盘事件 |
| 图像与颜色 | 图片格式转换 · 智能压缩图片 · 图片水印 · 图片灰阶生成器 · Favicon 生成器 · 颜色转换 |
| 时间与日期 | 时间戳转换 · 时区查看器 · 日期计算 · 计时器 |
| 辅助工具 | 设备信息 · 文件类型探测 · 数学计算 · 文本统计 · Emoji 与符号 |

## 特性

- 使用 SwiftUI 构建，采用原生单窗口界面。
- 解析、转换和加解密在本地完成，无需上传待处理内容。
- 支持 `⌘K` 命令面板、工具收藏和最近使用记录。
- 核心逻辑独立在 `XToolsCore`，配套单元测试。

## 安装

**下载 App**：前往 [Releases](https://github.com/iTsawaysu/XTools/releases) 获取最新版本。

**从源码构建**（需要 macOS 13+ 和 Xcode 16+）：

```bash
git clone https://github.com/iTsawaysu/XTools.git
cd XTools
./build.sh           # 增量构建 + 打包 + 打开 App
./build.sh release   # Release 构建
swift test           # 运行完整测试
```

## 参与贡献

欢迎通过 Issue 反馈问题，或提交 PR 改进工具。提交前请运行 `swift test`，并遵循仓库内 `.trellis/` 的开发约定。

## License

[XTools](https://github.com/iTsawaysu/XTools) 基于 [MIT License](LICENSE) 开源发布。
