# QingTie

QingTie 是一款本地运行的 macOS 菜单栏剪贴板工具，支持历史记录、搜索、固定和内容预览。

**[下载 macOS 通用版 DMG](https://github.com/yizhongre/qingtie/releases/latest/download/QingTie-universal.dmg)**

适用于 macOS 14 及更新版本，支持 Apple M 系列和 Intel Mac。[所有版本](https://github.com/yizhongre/qingtie/releases) · [SHA-256 校验值](https://github.com/yizhongre/qingtie/releases/latest/download/SHA256SUMS.txt)

## 功能

- 保存文本、富文本、图片和文件引用，保留原始剪贴板格式。
- 按文本、图片、链接筛选，搜索内容、来源应用和文件名。
- 固定常用内容，默认保留最近 200 条未固定记录，数量可在设置中调整。
- 预览文字和图片，通过 macOS Quick Look 预览本地文件。
- 显示来源应用图标，支持深色外观和系统「减少动态效果」设置。
- 支持全局快捷键、可选自动粘贴、登录启动、暂停记录和忽略指定应用。

## 安装与使用

1. 下载并打开 `QingTie-universal.dmg`。
2. 将 `QingTie.app` 拖入「应用程序」文件夹。
3. 从「应用程序」打开 QingTie，点击菜单栏图标或按 `⇧⌘V` 查看历史记录。

当前下载包未使用 Apple Developer ID 证书签名，也未经过 Apple 公证。首次尝试打开后，如果 macOS 阻止运行，请先确认下载来自本仓库的[发布页面](https://github.com/yizhongre/qingtie/releases)，且来源可信，再按照 [Apple 官方指引](https://support.apple.com/zh-cn/102445)，在「系统设置 → 隐私与安全性」中选择「仍要打开」，并在提示中确认打开。

打开面板后可直接输入搜索，使用方向键选择记录，按回车或点击记录复制内容。自动粘贴需要在系统设置中授予辅助功能权限；未授权时，复制后回到目标应用按 `⌘V` 即可。

| 快捷键 | 操作 |
| --- | --- |
| `⇧⌘V` | 打开或隐藏面板，可在设置中更改 |
| `↑` / `↓` | 选择记录 |
| `Return` | 使用选中的记录 |
| `⌘1`–`⌘9` | 使用当前列表前九条记录 |
| `⌘F` | 聚焦搜索 |
| `⌘Y` | 显示或隐藏预览 |
| `⌥P` | 固定或取消固定 |
| `⌥⌫` | 删除选中的记录 |
| `Esc` | 先关闭预览，再关闭面板 |

右键菜单也可固定、删除或复制记录。预览开关会自动保存。

## 隐私与数据

剪贴板历史只保存在本机，没有云同步、遥测或自动更新。应用会忽略带有保密、临时或自动生成标记的剪贴板内容；也可以在设置中暂停记录或按应用标识符排除来源。

历史文件位于 `~/Library/Application Support/QingTie/History-v2.json`，保存时限制为当前用户读写。文件未加密，请按个人需要管理和备份。文件损坏或写入失败时会提示错误，并保留原文件。

文件记录保存的是引用，原文件移动或删除后可能无法预览，剪贴板历史不能代替文件备份。单次复制内容超过 25 MB 时不记录。

## 从源码构建

需要 Swift 5.10 或更新版本、macOS SDK、Python 3 和 Xcode Command Line Tools。项目只使用 Apple 系统框架，无外部软件包依赖。

获取源码并构建当前 Mac 架构的应用。

```sh
git clone https://github.com/yizhongre/qingtie.git
cd qingtie
./scripts/build-app.sh
```

产物位于 `dist/QingTie.app`。构建脚本会生成应用图标并使用本地 ad-hoc 签名；此签名不包含 Apple 公证。

如需构建同时支持 Apple M 系列和 Intel Mac 的通用应用，并生成 DMG 与 SHA-256 校验值，运行以下命令。

```sh
./scripts/build-release.sh
```

## 运行检查

```sh
./scripts/test-core.sh
./scripts/test-panel.sh
./scripts/test-watcher.sh
./scripts/test-source-icons.sh
python3 Tests/PackagingChecks.py
python3 scripts/check-package.py
python3 scripts/check-release.py
```

`check-package.py` 需先完成应用构建，用于验证软件包依赖、应用元数据、资源和系统库链接。`check-release.py` 需先运行 `./scripts/build-release.sh`，用于检查发布产物。

测试使用私有剪贴板、合成数据和临时文件，不读取或改写系统剪贴板及实际历史记录。图标检查读取系统已安装应用的元数据。

可运行 `open -n dist/QingTie.app --args --demo` 查看使用临时数据和私有剪贴板的演示界面，运行 `open -n dist/QingTie.app --args --show-about` 查看关于窗口。

## 许可证

QingTie 使用 [MIT 许可证](LICENSE)。
