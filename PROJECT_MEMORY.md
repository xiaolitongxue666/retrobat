# Project Memory (Compact)
1) 控制面是 Windows Terminal 里的 Git Bash。调用 Windows 用 cmd.exe；cmd 会进 MSYS 的 /usr/bin/cmd。支持 Windows 10（10.0 build < 22000）和 Windows 11（build >= 22000）。doctor 打印 10 或 11，下载和配置不按系统分叉。当前这台是 10.0.22631。中文 ver 的“版本”是 GBK，windows_release 只保留数字和点。
2) ROM 库和 BIOS 库只由仓库根 .env 的 RETROBAT_ROMS、RETROBAT_BIOS 指定。相对路径是被忽略的仓库目录；绝对路径做成仓库根目录联接。.env 不提交。这台 Win11 的 RETROBAT_ROMS 是 D:/Download/Game-ROMS，RETROBAT_BIOS 是 bios。
3) 脚本只扫描 nes、megadrive、snes、psx。Game-ROMS 的展示名是 Nintendo、SEGA Genesis、Super Nintendo、Playstation，库根用同名目录联接指过去。仓库 roms 联接到库根。缓存在库的 .cache，不进 git。Python os.walk 会进入联接，MSYS find 不会。PowerShell 的 Target 是 Windows 路径，必须先 cygpath -u。
4) 不下载商业 ROM 或 PS1 BIOS，不把盗版站 URL 写进文档或脚本。本地已有文件可以使用。需要代理时在 .env 写 HTTP_PROXY 和 HTTPS_PROXY，load_env 会导出，curl 沿用。这台机器是 http://127.0.0.1:7890。
5) 不改 system/templates 和 build.ini。运行时配置写到 build/config 和已安装的 emulators 目录。manage 是旧的 Fusion、FCEUX、Snes9x 流程，已忽略，不要执行。
6) bios 同时是 .gitmodules 里的 retrobat-bios 子模块 gitlink。/bios/ 只挡住未跟踪 dump，不要 git rm 这个子模块。
7) PS1 BIOS 必须恰好 524288 字节。DuckStation 只按 MD5 识别。哈希表是 scripts/ps1-bios-hashes.csv。模拟器不打开 zip。4 MiB 的 PS2 BIOS 不能放进这个库。这台机器的四份 dump 来自 D:/Download/ps1-bios-pack.zip，放在 bios 根目录：scph5500.bin 为 NTSC-J，scph5501.bin 与 SCPH1001.BIN 为 NTSC-U，scph5502.bin 为 PAL。
8) 校验脚本的区域行是 NTSC-U 加两个空格再加 [ok]，因为 %-7s 会补空格。门闩要用 NTSC-U[[:space:]]+\[ok\]。
9) 缓存的 PS1 测试盘是 Metal Slug X (USA)，SLUS-01212，NTSC-U，来自扩展名为 zip、文件头为 7z 的包。对应 BIOS 是 scph5501.bin。DuckStation 显示 SCPH-5501, 5503, 7003 (v3.0 11-18-96 A)。SwanStation 成功日志含 Console Region: NTSC-U。Beetle 的成功日志是 Firmware found。PCSX ReARMed 的成功日志是 found BIOS file。
10) RetroArch 核心在 system_directory 找 BIOS。已安装的 retroarch.cfg 默认是 :\system，append 配置必须覆盖成仓库 bios。SwanStation 使用 2x 和 PGXP，BIOS 文件名为 scph5500.bin、scph5501.bin、scph5502.bin。
11) DuckStation 的 SearchDirectory 是 ..\..\bios。SetupWizardIncomplete 必须为 false，否则首次向导不读盘、不选 BIOS。确认 BIOS 要看 duckstation.log 的 Using BIOS 和 BIOS Region。进程还在不代表已选中 BIOS。需要 LogToFile=true。-earlyconsole 的输出不进 Start-Process 重定向。
12) RetroArch 自动化测试把配置合并成一份 appendconfig。同一文件里重复键以先出现的为准；多份 --appendconfig 只有最后一份生效。测试用 UDP 55355 发送 SAVE_STATE 和 QUIT。存档目录按核心分开。savestate_auto_load=false 必须是合并配置的第一项。加载成功的中文日志是「正在加载游戏文件」。没接手柄记为 SKIP。
13) zip 用 Python zipfile 解压。7zr 只解 7z。头是 7z 的 PS1 游戏包即使扩展名是 zip 也走 7zr。
14) Mesen 2.2.1 的父进程会马上以 0 退出，留下名为 Mesen 的子进程。启动是否成功要看残留进程。
15) 模拟器版本钉在 scripts/emulators.manifest：RetroArch 1.22.2、MesenCE 2.2.1、DuckStation portable 的 latest 通道，以及清单里的 libretro 核心。入口是 ./scripts/retro.bash，子命令为 doctor、link、sync、config、roms、test、play。简体中文的 user_language 是 12，核心宽高比是 22。2026-10-12 在这台 Win11 上，这些核心、duckstation cue 和 mesen exe 的 test 通过。
16) 从仓库目录启动 GPU 程序时，驱动可能留下空的 NVIDIA Corporation/umdlogs。该目录已忽略。
17) D:/Game 只留 RetroBat、PS2、Switch。PS2 和 Switch 不进入 retro.bash。旧的 MD、NES、SNES 模拟器目录已删除。多出来的卡带 zip 在 Game-ROMS 展示名目录里。两份 Streets of Rage 2 的内部镜像相同，库里保留原来的那份 zip。
