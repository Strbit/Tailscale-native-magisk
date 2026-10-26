[English](README.md) · [简体中文](README.zh-CN.md)

# Magisk 版原生 Tailscale TUN

**在 OpenAI 的协助下创建**

一个实验性的 ARM64 Magisk 引导（bootstrap）模块：它把打过补丁的
[`android-kxxt/external_tailscale_prebuilt`](https://github.com/android-kxxt/external_tailscale_prebuilt)
`tailscaled` 守护进程作为 root 原生（root-native）的 `tailscale0` 接口运行。
由于不经过 Android 的 `VpnService`，Android 的 VPN 槽位仍可留给另一个 VPN 使用。

> [!WARNING]
> 本项目是独立的社区项目，与 Tailscale Inc.、android-kxxt、Magisk 及 OpenAI
> 均无隶属关系，也未获其背书。在 root 层改动网络可能中断联网；请务必保留恢复
> 手段，并提前做好当前备份。

## Fork 与中文化说明

本仓库是
[`Iridule/Tailscale-native-magisk`](https://github.com/Iridule/Tailscale-native-magisk)
的 fork，由
[`Strbit/Tailscale-native-magisk`](https://github.com/Strbit/Tailscale-native-magisk)
维护。模块代码、脚本与安全模型的行为与上游保持一致，本 fork 在其之上增加了完整的
简体中文（`zh-CN`）本地化。

本 fork 新增的内容：

- 双语离线仪表盘，页头内即可切换语言；选择结果写入
  `/data/adb/tailscale-native/ui-language`，并与 shell 层共享；
- 模块自身脚本输出的本地化，包括 Magisk 安装器（安装器消息附带英文括注，确保在
  recovery 环境下中文缺失时仍可读懂）；
- `tools/check-i18n.js` 一致性校验工具，检查词典键、`%s` 占位符、文件编码、模块
  元数据与发布包；以及
- 以 `0.5.0-zh` 作为版本号、指向本 fork 的 `update.json`，并统一使用 LF 换行。

英文仍是默认回退语言。系统语言以 `zh` 开头的设备会自动选用 `zh-CN`，也可随时在
仪表盘内切换。中文文档即本文件；英文文档见 [README.md](README.md)。

与上游同步：

```sh
git remote add upstream https://github.com/Iridule/Tailscale-native-magisk.git
git fetch upstream
git merge upstream/main
```

## 需求

- 已获取 root 权限的 ARM64 Android 设备
- 支持模块的 Magisk
- 可正常工作的 `/dev/tun`
- 安装过程中可访问互联网
- 已断开官方 Android Tailscale 应用

引导包（bootstrap ZIP）**不**内置 Tailscale 可执行文件。安装时，它会从
android-kxxt 仓库下载安装当时的 ARM64 `tailscale` 与 `tailscaled` 二进制，校验
其 ELF 头，确认 `tailscaled --version` 可以执行，并在下载途中上游源码标记发生
变化时中止本次下载。

模块版本号标识的是这些引导脚本，而不是所下载的 Tailscale 版本。因此同一个模块
ZIP 在之后仍可用于安装更新的 Tailscale 构建。

## 安装

1. 从 [Releases](../../releases) 下载
   `native-tailscale-magisk-bootstrap-v0.5.0-zh.zip`。
2. 断开官方 Android Tailscale 应用。
3. 打开 **Magisk → 模块 → 从本地安装**，选择该 ZIP。
4. 重启。
5. 如尚未安装，请安装 KsuWebUIStandalone。
6. 打开 **Magisk → 模块**，点击本模块的 **操作（Action）** 按钮。
7. 在仪表盘中点击 **登录（Sign in）**，再点击 **打开 Tailscale 登录页**。

## 可选仪表盘

Magisk 用户可以安装
[`KsuWebUIStandalone`](https://github.com/KOWX712/KsuWebUIStandalone)
来打开模块内置的仪表盘。它离线可用，提供：

- 连接、守护进程、TUN 接口、版本与上游修订状态；
- 两个已安装二进制的 SHA-256 完整性记录状态；
- 子网路由（subnet routes）、屏蔽模式（shields-up）与主机名偏好设置；
- 登录、启动、停止、重启、完整性校验与原生二进制更新操作；
- 一键在设备浏览器中打开官方 Tailscale Machines 页面；
- 可刷新、可清空的历史守护进程日志与实时诊断；以及
- 本地赛博终端（cyber-terminal）风格主题，状态指示对比度高，不加载任何外部
  字体或资源。

仪表盘提供英文与简体中文，可在页头的语言控件中切换；该设置会被持久化，并同样
作用于模块的 shell 输出。`tailscale` / `tailscaled` 的原始输出始终按守护进程
实际打印的内容显示。

原生 Android 构建无法通过 Tailscale 常规的系统配置器读取或替换 Android 的基础
DNS，因此模块保持 `accept-dns` 关闭，Android 继续使用其原有 DNS。诊断
（Diagnostics）会对旧版配置或手动配置后可能残留的低严重度警告作出解释。Tailnet
IP 路由与子网路由不受此限制影响。

仪表盘只调用模块白名单内的 helper 操作，不提供任意命令输入框，也不存储认证凭据。

Magisk 通过 `update.json` 检查更新，并以其常规模块界面显示模块发布通知；仪表盘
不重复提供模块更新功能。

如果本设备此前已通过独立的原生方案完成配置，模块会复用：

```text
/data/adb/tailscale-native/tailscaled.state
```

操作（Action）按钮仅用于打开仪表盘。你也可以在 root shell 中完成认证：

```sh
su -c '/data/adb/modules/native_tailscale/bin/tailscale \
  --socket=/data/adb/tailscale-native/tailscaled.sock up'
```

## 状态检查

```sh
su -c '/data/adb/modules/native_tailscale/bin/tailscale \
  --socket=/data/adb/tailscale-native/tailscaled.sock status'
```

```sh
su -c '/data/adb/modules/native_tailscale/bin/tailscaled --version'
```

```sh
su -c 'ip addr show tailscale0'
```

日志文件：

```text
/data/adb/tailscale-native/tailscaled.log
```

## 更新原生二进制

打开仪表盘并点击 **更新 Tailscale（Update Tailscale）**。更新为手动操作，绝不
在开机时自动执行。更新器会：

- 比较已安装与上游的源码提交标记；
- 下载新的 ARM64 二进制；
- 复查该标记，若下载期间上游发生变更则中止；
- 校验 ELF 格式与可执行性；
- 记录 SHA-256 哈希；
- 备份当前二进制；
- 重启守护进程；以及
- 若新守护进程启动失败则自动回滚。

## 安全模型

上游预编译仓库目前只提供原始二进制，没有带签名的发布包或带签名的校验清单。因此
安装与更新依赖对 HTTPS、GitHub 以及 android-kxxt 仓库的信任。若这一信任模型不
符合你的需求，请在安装或点击 **更新 Tailscale（Update Tailscale）** 之前先审查
上游变更。记录的 SHA-256 哈希只用于留档「当时下载了什么」，并不会与独立可信的
上游清单做比对。

## 已知限制

- 仅支持 ARM64。
- 这是实验性模块，仅在有限数量的设备上测试过。
- 原生守护进程运行期间，官方 Android Tailscale 应用必须保持断开。
- 让 Android 的 `VpnService` 槽位保持空闲，并不能保证第二个 VPN 一定能与之共存：
  DNS 设置、路由、终止开关（kill switch）以及另一个 VPN 自身的策略仍可能冲突。
- 上游二进制是从上游仓库可变下载的，受上述信任模型约束。

## 恢复

若原生 Tailscale 导致启动或联网问题，请在 Magisk 中停用或移除本模块，然后重启。
卸载会保留 `/data/adb/tailscale-native`，因此重新安装通常能复用已认证的节点身份。
仅当你确实想抹掉该身份时，才删除这个目录。

## 卸载

移除模块会停止其守护进程，但会刻意保留 `/data/adb/tailscale-native`，其中包含
已认证的节点身份与日志。仅当你同时想抹掉身份时，才需要手动删除该目录。

## v0.2.1 迁移修复

更早的独立启动脚本会从 `/data/adb/service.d` 移动到
`/data/adb/service.d-disabled`。仅仅改掉脚本文件名的后缀并不能禁用它——只要它
仍具可执行权限：Magisk 会执行 `service.d` 中所有可执行文件，与后缀无关。模块在
重建 socket 之前还会先停止旧版守护进程。

## 验证

该校验值仅用于验证引导 ZIP，不验证安装或更新过程中随后下载的 Tailscale 二进制。

当前 `v0.5.0-zh` 发布包的校验值公布在 [SHA256SUMS](SHA256SUMS) 中，并随后续
GitHub Release 一并附上。上一个 `v0.4.6-bootstrap` 发布包的校验值为：

```text
82e53e0326c30c4efec6b629b30abc2cfeafdf99fd71108b205020ab7a1efe1e  native-tailscale-magisk-bootstrap-v0.4.6.zip
```

更多细节见 [SECURITY.md](SECURITY.md)、[CHANGELOG.md](CHANGELOG.md) 与
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
