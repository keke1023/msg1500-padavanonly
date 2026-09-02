# MSG1500 X.00 · padavanonly/immortalwrt 自动编译

> RAISECOM MSG1500 X.00（别名 Nokia A-040W-Q）· MT7621A + MT7615 (DBDC) · GitHub Actions 云编译
> 底座 **padavanonly/immortalwrt @ master**（immortalwrt 18.06 基线，自带 MTK 闭源无线驱动）

## 与 lede 版（msg1500-actions）的核心差异

| 项 | lede 版 (msg1500-actions) | 本仓库 (padavanonly) |
|---|---|---|
| 源码 | coolsnowwolf/lede @ 20251001（内核 5.10，golang 1.27） | padavanonly/immortalwrt @ master（18.06 基线，自带闭源驱动） |
| MT7615 驱动来源 | `package/lean/mt/...` 闭源 | `package/emortal/mt-drivers/` 闭源（同源 MTK mt_wifi） |
| MSG1500 默认无线 | 设备不带驱动，config 手动加 `kmod-mt7615d` | 设备**默认带开源 `kmod-mt7615e`**，需 patch 改成闭源 |
| helloworld | feeds 里被注释，去注释启用 | feeds 里**没有**该行，脚本改为**追加** |
| golang | 自带 1.27，无需升级 | 自带 1.20.2，本仓库**升到 1.21.13**（脚本 `30-upgrade-go.sh`） |

## 需求实现清单

| 需求 | 实现方式 |
|---|---|
| 底座 padavanonly/immortalwrt | `git clone -b master --depth 1` |
| 加 helloworld master 源 | `scripts/10-add-feeds.sh` 在 feeds.conf.default **追加** `src-git helloworld ...;master` |
| 升级 go 版本 | `scripts/30-upgrade-go.sh` 把 golang 1.20.2 → **1.21.13**（仅改版本号+PKG_HASH，bootstrap 链不变） |
| 剔除 rust 相关包 | `scripts/40-remove-rust.sh` 物理删除 helloworld 里 shadowsocks-rust / dns2socks-rust / shadow-tls |
| 选中 luci-app-ngrokc / frpc / autoreboot | seed config 显式勾选（前两者来自 helloworld master，autoreboot 来自 luci feed） |
| 去默认 luci 包 / 纯 HTTP | seed 不勾 `luci-ssl`，defconfig 后再 sed 兜底去除，避免 libustream 后端冲突 |
| 对照 K2P 生成 MSG1500 闭源无线配置 | `scripts/20-patch-wireless.sh` 把 `mt7621.mk` 里 MSG1500 的 `kmod-mt7615e kmod-mt7615-firmware` 替换为 **`kmod-mt7615d luci-app-mtwifi`**（与 phicomm_k2p 同款） |

## 使用方法

1. 本目录即完整 GitHub Actions 项目，推到 `keke1023/msg1500-padavanonly`。
2. 仓库 **Actions** 页 → `Build MSG1500 X.00 (padavanonly/immortalwrt)` → **Run workflow**
   - `wifi_driver` 选 `mt7615d`（闭源，默认）或 `mt7615e`（开源兜底）
3. 首次编译约 1.5～2.5 小时；完成后在 Artifacts 下载 `msg1500-x00-padavanonly-fw`
   （sysupgrade.bin + sha256sums）
4. 失败时 Artifacts 里会有 `msg1500-x00-padavanonly-build-logs`（logs + .config）用于定位

刷机：原厂 / Breed 下刷 sysupgrade.bin；MSG1500 为 NAND 机型，**首次建议不带配置刷入**。

## 目录结构

```
├── .github/workflows/build.yml   # 主 workflow（拉源码→加helloworld→patch无线→升go→删rust→install→编译→上传）
├── config/msg1500-x00.config      # 种子配置（defconfig 自动补全）
└── scripts/
    ├── 10-add-feeds.sh            # 追加 helloworld master feed，feeds update
    ├── 20-patch-wireless.sh       # 把 MSG1500 无线从开源 kmod-mt7615e 改成闭源 kmod-mt7615d + luci-app-mtwifi
    ├── 30-upgrade-go.sh           # golang 1.20.2 → 1.21.13
    └── 40-remove-rust.sh          # 物理剔除 3 个 rust 包（缺一即报错退出）
```

脚本顺序：**feeds update → patch 无线 → 升 go → 删 rust → feeds install -a → 写 .config → defconfig**。

## 关键技术点

- **为什么 padavanonly 自带闭源驱动**：其 `package/emortal/mt-drivers/` 下有 `mt7603e / mt7612e / mt7615d / mt_wifi / mtkhqos_util`，
  `kmod-mt7615d` 即 MTK 官方 `mt_wifi` 闭源驱动（编译产物 `mt_wifi.ko`），`luci-app-mtwifi` 提供管理界面。
  MSG1500 的 MT7621 单芯片 MT7615 DBDC 与 K2P 同源，可直接套用 K2P 的 `kmod-mt7615d luci-app-mtwifi` 写法。
- **为什么不勾 luci-ssl**：纯 HTTP LuCI 更省心，且避免 `libustream-openssl` / `libustream-mbedtls` 抢同名
  `libustream-ssl.so` 的安装冲突（lede 版曾踩过，最终也是去 luci-ssl）。
- **golang 升级上限 1.21.x**：padavanonly 的 golang Makefile bootstrap 链是 go1.4 + go1.17.13，go1.17 只能 bootstrap 到 go1.21，
  强行升 1.22+ 会因 bootstrap 版本不足编译失败。1.21.13 的 PKG_HASH 取自 openwrt/packages 23.05 官方 Makefile（权威值）。
- **rust 判定**：不只按目录名，还 grep Makefile 里的 `rust-package.mk` / `rust/host` / `Cargo.toml`
  （`shadow-tls` 名字不带 rust，靠这个标记抓出）。`luci-app-ssr-plus` 本体只在可选项里提到 rust 包名，有白名单保护不会被误删。

## 风险与回退

| 风险 | 概率 | 回退 |
|---|---|---|
| padavanonly 18.06 基线在 ubuntu-22.04 (gcc11) 上编内核/工具链异常 | 低-中 | job 加 `container: debian:11` |
| `kmod-mt7615d`（padavanonly 版）在 18.06/5.4 内核上编译失败 | 低-中 | workflow 选 `mt7615e` 开源模式重跑 |
| helloworld master 后续更进新内核 API，某包在 18.06 上失败 | 随时间上升 | 定位失败包后钉旧版本号，或把 helloworld 换成其旧 tag |
| golang 1.21.13 仍不够新导致 frpc/ngrokc 编译失败 | 低 | 进一步升到 1.21 更新 patch 或换 packages 源 |

已知取舍：padavanonly/immortalwrt 是 18.06 时代的长期维护 fork，自带 MTK 闭源驱动全家桶 + 国内优化，
适合"开箱即用的老设备闭源无线"；但整体比 lede 20251001 老。如需更新的内核/工具链，请回 lede 版 `msg1500-actions`。

---
🐾 阿宝定制 · 2026-09-01 · 数据来源：GitHub API 实时核查（padavanonly/immortalwrt 各目录 / 包 Makefile / openwrt-23.05 golang）
