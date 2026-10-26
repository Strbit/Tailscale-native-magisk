# Native Tailscale TUN v0.5.0-zh

This release adds a complete Simplified Chinese localization to the module and
publishes it from the `Strbit` fork. Module behaviour, scripts, and the
security model are unchanged from `0.4.6-bootstrap`.

## 中文

本次发布为模块加入完整的简体中文本地化，并由 `Strbit` fork 发布。模块行为、
脚本与安全模型与 `0.4.6-bootstrap` 保持一致。

### 新增

- 离线双语仪表盘（英文 / 简体中文），页头语言切换按钮即时生效，无需刷新页面。
- 语言设置持久化到 `/data/adb/tailscale-native/ui-language`，Web 层与 shell 层
  共用同一事实源；未设置时按系统语言判定，默认回退英文。
- 模块自身脚本输出（含 Magisk 安装器）全部本地化；安装器每条中文提示附带英文
  括注，recovery 环境缺中文字体时仍可读。
- 新增 `tools/check-i18n.js` 校验工具，覆盖词典键与占位符对齐、HTML/JS 键引用、
  shell 字典与 `%s` 一致性、模块元数据与发布包结构。

### 修复与变更

- 所有文本文件统一为 LF 且无 BOM，修复 Android shell 因 CRLF 无法执行的问题。
- 版本号改为 `0.5.0-zh`（versionCode `500`）；`update.json`、`module.prop` 的
  `updateJson` 与发布资产链接均指向 `Strbit/Tailscale-native-magisk`。
- 语言设置不会改动任何逻辑判断：`BackendState`、`integrity`、`interface` 等字段
  仍以英文原值参与比较，仅在显示层翻译。
- `tailscale` / `tailscaled` 的原始输出保持原文，不做翻译。

## English

### Added

- An offline bilingual dashboard (English / Simplified Chinese) with a header
  language switch that applies immediately, without a page reload.
- A persisted language setting in
  `/data/adb/tailscale-native/ui-language`, shared by the web and shell layers.
  Without a stored value it follows the system language and falls back to
  English.
- Full localization of the module's own script output, including the Magisk
  installer. Each Chinese installer message keeps an English gloss in
  parentheses so it stays readable when recovery lacks Chinese fonts.
- `tools/check-i18n.js`, a consistency checker for dictionary keys and
  placeholders, referenced HTML/JS keys, shell dictionary and `%s` alignment,
  module metadata, and release archive structure.

### Fixed and changed

- All text files are LF and BOM-free, fixing Android shell scripts that could
  fail to execute with CRLF line endings.
- Version is now `0.5.0-zh` (versionCode `500`); `update.json`, the
  `updateJson` entry in `module.prop`, and release asset URLs point at
  `Strbit/Tailscale-native-magisk`.
- Localization never changes logic: `BackendState`, `integrity`, and
  `interface` values are still compared in their original English form and
  translated only for display.
- Raw `tailscale` / `tailscaled` output is passed through untranslated.

## Validation

- `node tools/check-i18n.js` reports zero errors for the documentation,
  metadata, shell, and web areas.
- Dictionary keys and `%s` placeholders match between `en` and `zh-CN`.
- Shell syntax, JavaScript syntax, mobile WebUI regression, archive comparison,
  and release checksum checks pass.

## 验证

- `node tools/check-i18n.js` 在文档、元数据、shell 与 Web 领域均无 error。
- `en` 与 `zh-CN` 的词典键及 `%s` 占位符完全对齐。
- shell 语法、JavaScript 语法、移动端 WebUI 回归、归档比对与发布校验和均通过。

## Important

- ARM64 only.
- Reboot after installing so Magisk activates every updated module script.
- Disconnect the official Android Tailscale app before using the native daemon.
- Existing identity under `/data/adb/tailscale-native` remains preserved.
- Installing this fork replaces the upstream module of the same module ID
  (`native_tailscale`); your saved identity is kept.

## 重要说明

- 仅支持 ARM64。
- 安装后请重启，以便 Magisk 激活全部更新后的模块脚本。
- 使用原生守护进程前，请先断开官方 Android Tailscale 应用。
- `/data/adb/tailscale-native` 中已有的身份会被保留。
- 本 fork 与上游模块 ID 相同（`native_tailscale`），安装本 fork 会替换上游模块；
  已保存的身份不受影响。

## SHA-256

The checksum of this release archive is published in `SHA256SUMS` and attached
to the GitHub release. Verify it after downloading:

本次发布包的校验值公布在 `SHA256SUMS` 中，并随后续 GitHub Release 一并附上。
下载后请核对：

```sh
sha256sum --check SHA256SUMS
```
