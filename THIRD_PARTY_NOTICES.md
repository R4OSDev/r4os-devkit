# Third-Party Notices

The tracked DevKit repository contains R4OS bootstrap scripts only. The Windows
setup downloads and verifies the following pinned external tools:

| Component | Version | License | Source |
| --- | --- | --- | --- |
| Zig | 0.16.0 | MIT | https://ziglang.org/download/ |
| Limine | 12.0.1 | BSD-2-Clause | https://github.com/limine-bootloader/limine |
| QEMU | 11.0.0 Windows build | GPL-2.0 with separately licensed parts | https://www.qemu.org/ |
| 7-Zip | 26.02 | LGPL-2.1-or-later for most code, with the upstream unRAR restriction for affected parts | https://www.7-zip.org/ |

These downloads and the installed Contract, SDK, Distribution, and HostTools
checkouts are ignored and are not redistributed by this Git repository. Each
installed component retains the license files and terms supplied by its
upstream project.
