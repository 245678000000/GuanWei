# 观微 · 系统监视器

一款简约美观的 macOS 菜单栏系统监视器，原生 SwiftUI 编写，界面全中文，支持浅色 / 深色 / 跟随系统。

## 功能

- **菜单栏**：实时显示 CPU、内存占用与网络上下行速率（可在设置中开关）
- **时钟**：时间、日期、农历、开机时长
- **处理器**：总占用、用户/系统历史柱状图、能效核心与性能核心逐核圆环、系统负载
- **内存**：内存压力、App 内存 / 联动内存 / 已压缩 / 可用、交换
- **磁盘**：容量占用、实时读写速率与波形
- **网络**：上传/下载速率与波形、Wi‑Fi 信号、内网 IP、公网 IP（点击查询）、本次累计流量
- **进程**：CPU 占用最高的 5 个进程（含图标与内存）
- **图形处理器 / 电池**：GPU 占用；电量、充电状态、剩余时间、健康度、循环次数
- **外观**：跟随系统 / 浅色 / 深色；支持登录时启动
- **检查更新**：基于 GitHub Releases，自动（每 6 小时）或手动检查，一键下载、替换并重启

## 安装

从 [Releases](https://github.com/245678000000/GuanWei/releases) 下载 `GuanWei-x.y.z.zip`，解压后将 `观微.app` 拖入「应用程序」。
应用为临时签名，首次打开如被拦截，请右键 →「打开」，或在「系统设置 → 隐私与安全性」中允许。

## 构建

需要 macOS 14+ 与 Swift 工具链（Xcode 或 Command Line Tools 均可）。

```bash
./build.sh            # 生成 build/观微.app
open build/观微.app
```

将 `观微.app` 拖入「应用程序」文件夹后再开启「登录时启动」。

发布新版本（更新 `VERSION`、打包、打 tag 并创建 GitHub Release）：

```bash
./release.sh 1.1.0 "更新说明"
```

调试时可用普通窗口预览面板：

```bash
swift build
.build/debug/GuanWei --window --appearance light   # light / dark / system
```

## 说明

- 公网 IP 仅在点击「点击查询」时请求 `api.ipify.org`。
- 新版 macOS 读取 Wi‑Fi 名称需要定位权限，因此只显示信号强度。
- 暂不支持 CPU 温度与风扇转速（Apple 芯片需读取 SMC）。
