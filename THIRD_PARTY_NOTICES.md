# Third-Party Notices

The tracked DevKit repository contains R4OS bootstrap scripts only. Setup
downloads and verifies the following pinned external tools (host-dependent):

| Component | Version | License | Source |
| --- | --- | --- | --- |
| Zig | 0.16.0 | MIT | https://ziglang.org/download/ |
| Rust / Cargo / rustfmt / Clippy / Rust sources | 1.99.0 toolchain | Apache-2.0 OR MIT, with separately licensed dependencies | https://www.rust-lang.org/ |
| rustup | 1.29.1 | Apache-2.0 OR MIT | https://github.com/rust-lang/rustup |
| Bundled LLD and LLVM tools | Version supplied by Rust 1.99.0 | Apache-2.0 WITH LLVM-exception, with separately licensed parts | https://llvm.org/ |
| Limine | 12.0.1 | BSD-2-Clause | https://github.com/limine-bootloader/limine |
| QEMU | 11.0.0 Windows build | GPL-2.0 with separately licensed parts | https://www.qemu.org/ |
| 7-Zip | 26.02 | LGPL-2.1-or-later for most code, with the upstream unRAR restriction for affected parts | https://www.7-zip.org/ |

These downloads and the installed Contract, SDK, Distribution, and HostTools
checkouts are ignored and are not redistributed by this Git repository. Each
installed component retains the license files and terms supplied by its
upstream project.
