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
   - `device` 选 `msg1500-x00`（默认，RAISECOM MSG1500 X.00）或 `k2p-32m`（Phicomm K2P 32MB 闪存版）
   - `wifi_driver` 选 `mt7615d`（闭源，默认）或 `mt7615e`（开源兜底；k2p-32m 建议保持默认 mt7615d）
3. 首次编译约 1.5～2.5 小时；完成后在 Artifacts 下载 `msg1500-x00-padavanonly-fw`
   （sysupgrade.bin + sha256sums）
4. 失败时 Artifacts 里会有 `msg1500-x00-padavanonly-build-logs`（logs + .config）用于定位

刷机：原厂 / Breed 下刷 sysupgrade.bin；MSG1500 为 NAND 机型，**首次建议不带配置刷入**。

## 编译结果 & 刷机验证

### 首次构建已通过（2026-09-03）

| 项 | 值 |
|---|---|
| Run | `33698619330` → **success** |
| 产物 | `msg1500-x00-padavanonly-fw`（≈23.4 MB，未过期） |
| 拉取方式 | GitHub Web UI → Actions → 该 Run → Artifacts 下载（沙箱内无法直接拉取 artifact，见下） |

### 三次失败根因链（已全修）

1. **Run 33636539309**：升级 golang 后 host build 3 秒崩 → 过时补丁 `001-cmd-link-use-gold-on-ARM-ARM64...` 在 go1.21 上 `Hunk FAILED`。
   **修**：`scripts/35-remove-golang-patch.sh` 在 `feeds install -a` 后物理删补丁。
2. **Run 33644993096**：frp/ngrokc 等 Go 模块拉取失败 `GOPROXY list is not the empty string, but contains no entries` → `golang-values.mk` 的 `GOPROXY` 在 `# Unmodified` 段、继承 runner 坏环境值。
   **修**：`scripts/36-fix-golang-proxy.sh` 强制注入 `proxy.golang.org,goproxy.cn,direct` + `GOSUMDB=off`，并在 workflow `env` 加双保险。
3. **Run 33698619330（本次）**：两处修复同时命中 → **成功**。

### 刷机后验证清单

```sh
# 1. 闭源驱动双频 dat 齐全（MTK_CHIP_MT7615E_DBDC 双频）
ls /etc/wireless/mt7615/          # 应有 2G / 5G 两个 .dat

# 2. 内核模块已加载
lsmod | grep mt_wifi              # 应出现 mt_wifi

# 3. 无线用 mt7615 闭源驱动而非 mt76 开源
uci show wireless                 # 确认 ifname 走 mt7615，无 mt76x2 之类

# 4. 选中的 Luci app 在位
opkg list-installed | grep -E "luci-app-(frpc|ngrokc|autoreboot|mtwifi|ssr-plus)"
```

> 注：MSG1500 为 NAND 机型，首次建议「不带配置（不保留设置）」刷入 sysupgrade.bin。

### 关于 artifact 下载

GitHub Actions 产物走 Azure blob 存储，本沙箱环境对大二进制下载会返回「HTTP 200 但 0 字节」（与 GitHub tarball 被掐同类），**无法在沙箱内直接拉取核验**。
判定成功以 GitHub API 的 `conclusion=success` + `artifacts[].size_in_bytes` 非空为准；最终固件请在 GitHub Web UI 下载。

## 发布到 Release（可选）

仓库附带 `release.yml`：本地给仓库打 `v*` tag 并推送后，会自动把最新 Run 的固件产物发布到一个 GitHub Release，
无需每次编译都刷 release。用法：

```sh
git tag v1.0.0 && git push origin v1.0.0
```

## 目录结构

```
├── .github/workflows/build.yml    # 主 workflow（拉源码→加helloworld→patch无线→升go→删rust→install→编译→上传）
├── .github/workflows/release.yml  # 打 v* tag 时触发，重跑构建并把固件发到 GitHub Release（不污染日常编译）
├── config/msg1500-x00.config
├── config/k2p-32m.config          # K2P-32M 种子配置（32MB 闪存）      # 种子配置（defconfig 自动补全）
└── scripts/
    ├── 10-add-feeds.sh            # 追加 helloworld master feed，feeds update
    ├── 20-patch-wireless.sh
    ├── 25-add-k2p-32m.sh          # 把 Phicomm K2P 改成 32MB 闪存版 K2P-32M（IMAGE_SIZE + DTS 分区）       # 把 MSG1500 无线从开源 kmod-mt7615e 改成闭源 kmod-mt7615d + luci-app-mtwifi
    ├── 30-upgrade-go.sh           # golang 1.20.2 → 1.27.1（引导器换预编译 go1.26.8，以编 helloworld master 的 go1.26 包）
    ├── 35-remove-golang-patch.sh  # feeds install 后删过时 gold 补丁（go1.21+ 已自带修复，否则 host build Hunk FAILED）
    ├── 36-fix-golang-proxy.sh     # 强制注入有效 GOPROXY（修 frp/ngrokc 等 Go 模块拉取失败）
    └── 40-remove-rust.sh          # 物理剔除 3 个 rust 包（缺一即报错退出）
```

脚本顺序：**feeds update → patch 无线 → 升 go → 删 rust → feeds install -a → 35 删补丁 → 36 注 GOPROXY → 写 .config → defconfig**。

> 注：xray-core 直接用 helloworld master 默认版本（26.5.9，需 go1.26），由升到 1.27.1 的 Go 工具链编译，不再钉旧版。

## 关键技术点

- **为什么 padavanonly 自带闭源驱动**：其 `package/emortal/mt-drivers/` 下有 `mt7603e / mt7612e / mt7615d / mt_wifi / mtkhqos_util`，
  `kmod-mt7615d` 即 MTK 官方 `mt_wifi` 闭源驱动（编译产物 `mt_wifi.ko`），`luci-app-mtwifi` 提供管理界面。
  MSG1500 的 MT7621 单芯片 MT7615 DBDC 与 K2P 同源，可直接套用 K2P 的 `kmod-mt7615d luci-app-mtwifi` 写法。
- **为什么不勾 luci-ssl**：纯 HTTP LuCI 更省心，且避免 `libustream-openssl` / `libustream-mbedtls` 抢同名
  `libustream-ssl.so` 的安装冲突（lede 版曾踩过，最终也是去 luci-ssl）。
- **golang 升到 1.27.1（预编译引导器方案）**：padavanonly 18.06 的 `lang/golang/golang/Makefile` 是**源码两段式引导**（`go1.4` 源码 → `go1.17.13` 源码 → 主版本），Go 引导规则「N 版本需 N-2 引导器」意味着 go1.17.13 最多只能编出 **go1.21**，不能靠改版本号直接到 1.26+。helloworld master 当前 xray-core=26.5.9 的 go.mod 要求 **go1.26**，
  **修法**：把第二段引导器 `BOOTSTRAP_1_17` 从「go1.17.13 源码」换成「go1.26.8 预编译二进制」直接当 `GOROOT_BOOTSTRAP`，主版本即可 `make.bash` 编到 1.27.1；预编译包无 `src/make.bash`，须把 `GoCompiler/Bootstrap-1.17/Make` 用空 define 覆盖成 no-op。权威 hash：go1.27.1 src=`4e408abae…238b1`、go1.26.8 预编译=`d0f743b3…f8b57b`（go.dev/dl）。
- **rust 判定**：不只按目录名，还 grep Makefile 里的 `rust-package.mk` / `rust/host` / `Cargo.toml`
  （`shadow-tls` 名字不带 rust，靠这个标记抓出）。`luci-app-ssr-plus` 本体只在可选项里提到 rust 包名，有白名单保护不会被误删。

## 风险与回退

| 风险 | 概率 | 回退 |
|---|---|---|
| padavanonly 18.06 基线在 ubuntu-22.04 (gcc11) 上编内核/工具链异常 | 低-中 | job 加 `container: debian:11` |
| `kmod-mt7615d`（padavanonly 版）在 18.06/5.4 内核上编译失败 | 低-中 | workflow 选 `mt7615e` 开源模式重跑 |
| helloworld master 后续更进新内核 API，某包在 18.06 上失败 | 随时间上升 | 定位失败包后钉旧版本号，或把 helloworld 换成其旧 tag |
| golang 1.27.1 仍不够新导致 helloworld master 某 Go 包编译失败 | 低 | 进一步升到更新的 go1.2x（同步抬高预编译引导器到 ≥1.24.2），或把 helloworld 换成旧 tag |

已知取舍：padavanonly/immortalwrt 是 18.06 时代的长期维护 fork，自带 MTK 闭源驱动全家桶 + 国内优化，
适合"开箱即用的老设备闭源无线"；但整体比 lede 20251001 老。如需更新的内核/工具链，请回 lede 版 `msg1500-actions`。

## 增加机型：Phicomm K2P-32M（32MB 闪存）

在原有 MSG1500 X.00 基础上新增 **Phicomm K2P（mt7621）的 32MB 闪存版**。K2P 原厂为 16MB SPI NOR，
本仓库通过 `scripts/25-add-k2p-32m.sh` 在编译期改造 `padavanonly/immortalwrt` 自带的 K2P 定义：

| 改造项 | 改前（padavanonly 原值） | 改后 |
|---|---|---|
| `mt7621.mk` 设备块 `IMAGE_SIZE` | `16064k` | `32128k`（仅 K2P 设备块，范围 sed，不动其余 35 个 16064k 机型） |
| DTS `model` | `Phicomm K2P` | `Phicomm K2P-32M` |
| DTS `spi-max-frequency` 之后 | — | 新增 `broken-flash-reset;`（部分 32MB 闪存需要软件 reset） |
| DTS firmware 分区 `reg` | `<0x50000 0xfb0000>`（≈15.7MB） | `<0x50000 0x1fb0000>`（占满 32MB） |

> ⚠️ 网上流传的 K2P 32M 改法（`s/15744k/32128k/g`、`s/<0xa0000 0xf60000>/<0xa0000 0x1f60000>/`）是针对**官方 OpenWrt / 老 lede** 的，
> 在 padavanonly/immortalwrt 上**不对症**：该底座 K2P 的 `IMAGE_SIZE` 是 `16064k`（且全文件出现 36 次，全局替换会改坏其他机型），
> firmware 分区是 `<0x50000 0xfb0000>` 而非 `<0xa0000 0xf60000>`。本仓库的 `25-add-k2p-32m.sh` 已按实际 base 修正。
> K2P 的 `DEVICE_PACKAGES` 默认即 `kmod-mt7615d luci-app-mtwifi`（闭源驱动同源），故无需再 patch 无线。

刷机：K2P 为 SPI NOR，Breed / 官方 Bootloader 下刷
`openwrt-ramips-mt7621-phicomm_k2p-squashfs-sysupgrade.bin` 即可（固件文件名含 `phicomm_k2p`）。

---
🐾 阿宝定制 · 2026-09-01 · 数据来源：GitHub API 实时核查（padavanonly/immortalwrt 各目录 / 包 Makefile / openwrt-23.05 golang）
