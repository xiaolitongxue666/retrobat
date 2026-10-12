# RetroBat 路径约定（BIOS / ROMS）

> 本文记录 RetroBat 安装目录的**固定相对结构**，用于脚本、启动器（emulatorlauncher / configgen）和排障时快速定位资源。
> 证据来源：`system/configgen/retrobat_tree.lst`、`system/configgen/systems_names.lst`、`system/es_menu/*.menu`、`system/resources/retrobat_template.ini`。

## 1. 结论：两个核心地址

| 用途 | 相对路径（相对 RetroBat 安装根目录） | 说明 |
|---|---|---|
| **BIOS** | `bios\` | 所有模拟器固件 / BIOS 镜像的统一存放点，按模拟器或系统分子目录 |
| **ROMS** | `roms\<system>\` | 每个系统一个子目录，目录名即 EmulationStation 的 system id |

安装根目录（即 `RetroBat.exe` 所在目录）下同时包含：

```
RetroBat\
├── bios\                  <- BIOS 地址
├── roms\                  <- ROMS 地址（每个系统一个子目录）
├── cheats\                <- 金手指
├── decorations\           <- 边框 / bezels
├── emulationstation\      <- 前端（.emulationstation\themes、gamelist 等）
├── emulators\             <- 各独立模拟器（retroarch、mame、duckstation ...）
├── library\  records\     <- 库 / 运行记录
├── saves\                 <- 存档、记忆卡、nvram、sstates
├── screenshots\           <- 截图
├── sounds\                <- 音效
├── system\                <- configgen / templates / shaders / tools（本仓库内容）
└── user\                  <- 用户覆盖配置（apikey、inputmapping、customratio ...）
```

**关键点：RetroBat 没有在 `retrobat.ini` 中提供 roms/bios 路径配置项**（`system/resources/retrobat_template.ini` 仅有 `[RetroBat]`、`[SplashScreen]`、`[EmulationStation]` 段）。
路径的两种改变方式：

1. **Portable Mode**：把整个 RetroBat 目录放到外置盘，所有路径随根目录整体迁移。
2. **符号链接（symlink）**：官方 CHANGELOG 明确支持 `roms` 文件夹为 symlink（卸载商店游戏时不会破坏链接）。例如把 `roms\` 指向大容量磁盘。

## 2. 模拟器如何引用这些地址

启动器以**相对路径**从模拟器目录向上两级回退到根目录调用，例如 `system/es_menu/mame.menu`：

```
..\..\roms\mame;..\..\bios                    # -rp ROM 路径 + BIOS 路径
-sp ..\..\bios\mame\samples                   # 采样音
-artpath ..\..\bios\mame\artwork;artwork;..\..\saves\mame\artwork
-inipath ..\..\bios\mame\ini
-hash ..\..\bios\mame\hash
-state_directory ..\..\saves\mame\states
-nvram_directory ..\..\saves\mame\nvram
```

其它样例：

- `dosbox_pure_libretro.menu`: `.\..\..\roms\dos`
- `pico8.menu`: `-root_path .\..\..\roms\pico8`

即约定为：**`emulators\<emu>\` → `..\..\roms\` / `..\..\bios\`**。

## 3. bios 子目录（部分）

`bios\` 下与系统名不完全一一对应，常见形态（完整清单见 `system/configgen/retrobat_tree.lst` 第 1~80 行）：

```
bios\dc            bios\fbneo        bios\mame\samples   bios\openmsx\share\systemroms
bios\dinothawr     bios\fmtowns      bios\mame\artwork   bios\pcsx2\bios
bios\dolphin-emu   bios\hatari\tos   bios\neocd          bios\PPSSPP
bios\eka2l1\data\roms                bios\same_cdi\bios  bios\supermodel
```

注意 `bios\pcsx2\bios`、`bios\same_cdi\bios` 等存在**两级同名目录**（模拟器内部再套一层 `bios` 目录）。

## 4. roms 子目录

- 大多数系统名 = `roms\<system>\`，系统 id 清单见 `system/configgen/systems_names.lst`（当前 241 项）。
- 少数系统在 roms 下有**固定子结构**（见 `retrobat_tree.lst` 第 306~330 行）：

```
roms\cgenius\games
roms\quake\{id1,rogue,hipnotic}
roms\quake2\{baseq2,rogue,xatrix,zaero}
roms\singe
roms\sonic-mania
roms\sonicretro\{sonic1,sonic2,soniccd}
roms\switchupdates
roms\vpinball\roms
roms\halflife\{valve,bshift,cstrike,gearbox}
```

## 5. 快速定位（脚本）

### 5.1 路径查询 `retrobat-paths.sh` / `.cmd`

```bash
# 在 RetroBat 安装根目录执行
bash scripts/retrobat-paths.sh                 # 打印 bios / roms / saves 等绝对路径
bash scripts/retrobat-paths.sh roms psx        # 打印某个系统的 ROM 目录
bash scripts/retrobat-paths.sh check mame      # 检查 mame 的 roms + bios\mame 是否存在
```

Windows 用户可直接运行 `scripts\retrobat-paths.cmd`（同样支持 `roms <system>` / `check <system>`）。

### 5.2 PS1 BIOS 校验 `ps1-bios-verify.sh` / `.cmd`

```bash
bash scripts/ps1-bios-verify.sh                # 扫描 RetroBat\bios 并对照 DuckStation 官方哈希表
bash scripts/ps1-bios-verify.sh /path/to/bios  # 扫描指定目录
```

两个脚本都自动向上探测 RetroBat 根目录，可用 `RETROBAT_ROOT` 覆盖。

## 6. PS1 BIOS 校验（DuckStation）

### 6.1 投放位置

`system/templates/duckstation/settings.ini` 的 `[BIOS]` 段：

```ini
[BIOS]
SearchDirectory = ..\..\bios
```

即 **`RetroBat\bios\` 根目录**（不是 `bios\duckstation\`）。

**DuckStation 只按内容哈希识别 BIOS，不依赖文件名**——`scph1001.bin`、`ps-30a.bin` 或任意名字都能用，只要 MD5 命中已知版本。

### 6.2 合法来源

PS1 BIOS 是 Sony 的受版权保护固件。唯一合法来源是**从你自己拥有的 PS1 主机 dump**。
禁止从第三方镜像站（`pcsx2bios.online`、各类 "bios pack" zip）获取：既侵权，也是恶意软件的常见载体。
RetroBat 官方 README 对此有明确禁令。

### 6.3 校验你的 dump

```bash
bash scripts/ps1-bios-verify.sh
```

输出示例：

```
[ok]   scph5501.bin        SCPH-5501/5503/7003 (v3.0A, NTSC-U)
[??]   unknown.bin         unrecognized
       md5=...  size=262144
       note: PS1 BIOS must be exactly 524288 bytes (512 KiB); size looks wrong

Region coverage (DuckStation needs a BIOS matching the disc region):
  NTSC-U  [ok]
  NTSC-J  [--]
  PAL     [ok]
```

哈希表：`scripts/ps1-bios-hashes.csv`（24 条 PS1 修订版），数据取自 DuckStation 上游
`src/core/bios.cpp` 的 `s_image_info_by_hash`。

### 6.4 关键约束

| 项 | 值 |
|---|---|
| PS1 BIOS 大小 | **必须恰好 524288 字节（512 KiB）**，其它大小一律无法加载 |
| PS2 BIOS 大小 | 4 MiB（`BIOS_SIZE_PS2`），用于 PCSX2，与 PS1 不同 |
| 区域匹配 | BIOS 区域须与光盘区域一致，否则 DuckStation 拒绝启动（`region_check`） |
| 推荐组合 | 至少 NTSC-U + NTSC-J 各一份；PAL 视游戏区码补充 |
| OpenBIOS | 开源替代品，无固定哈希，靠偏移 `0x78` 处的 `OpenBIOS` 签名识别；仅 bash 版脚本检测 |

## 7. `.env` 里的 ROM 库和 BIOS 库

模拟器仍然从安装根的 `bios\` 和 `roms\` 读取。这两个路径可以是仓库里的目录，也可以是指向别处的目录联接。位置写在仓库根的 `.env`：

```
RETROBAT_ROMS=roms
RETROBAT_BIOS=bios
```

模板是 `.env.example`。`.env`、`roms/`、`bios/`、`emulators/`、`saves/` 不提交。

- 值为 `roms` 或 `bios`：库就在仓库内部，由 `.gitignore` 排除。
- 值为其他绝对路径：`./scripts/retro.bash link` 把仓库里的同名目录做成联接，不复制文件。
- `retrobat-paths.sh` 在目录是联接时多打印一行 `->` 物理路径。
- `cmd_roms` 只遍历 `nes`、`megadrive`、`snes`、`psx`。库里若是展示名目录，在库根为这四个 id 做目录联接，文件仍留在展示名目录。
- 可选的 `HTTP_PROXY` 和 `HTTPS_PROXY` 写在 `.env`。`scripts/lib/common.bash` 的 `load_env` 会导出它们，`curl` 下载模拟器时沿用。不需要代理就不要设置。

换盘时只改 `.env`，再执行 `link`。

`windows_release` 用 `cmd.exe //c ver` 区分 Windows 10 和 11：`10.0` 的 build 小于 22000 为 10，否则为 11。中文系统的“版本”是 GBK，解析时只保留数字和点。下载和配置不按系统分叉。

## 8. 常见问题

| 现象 | 检查点 |
|---|---|
| BIOS 缺失告警 | 文件是否在 `bios\` 下，而非 `bios\<emu>\bios\`；注意两级同名目录；用 `ps1-bios-verify.sh` 验哈希 |
| 前端看不到游戏 | 文件是否在 `roms\<system>\`；`GameListOnly=1` 时需重新扫描 gamelist |
| 换了磁盘后失效 | 用 symlink 而非移动子目录；Portable Mode 需整体迁移根目录 |
| 存档不在预期位置 | 各模拟器用 `saves\` 而非 roms 同级目录，见上面的 `-state_directory` 参数 |
