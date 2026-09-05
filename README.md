# R4OS DevKit

The R4OS DevKit bootstraps a local development environment without committing
downloaded toolchains or installed source checkouts.

    SDK/Core/         Installed R4OS SDK
    SDK/Contract/     Matching platform Contract
    Setup/            Host-specific setup scripts
    Toolchains/Zig/   Zig toolchain
    Boot/Limine/      Limine bootloader and host tool
    Emulation/QEMU/   QEMU for system tests
    HostTools/bin/    Built R4OS host tools
    HostTools/Source/ Installed host-tool sources

## Setup

Windows:

    Setup/Setup_Windows.bat

Debian Linux:

    ./Setup/Setup_Linux.sh

Both launchers call the shared PowerShell 7 setup. It installs
checksum-pinned Zig 0.16.0 and Limine 12.0.1, prepares QEMU 11.0.x, installs
the matching Contract, SDK, Libraries, and Distribution checkouts, and builds
the R4OS host tools. Windows uses the portable QEMU package; Debian uses QEMU
from its backports repository and places only host-specific links below the
DevKit.

PowerShell 7 must already be available. Windows also requires Git and curl.
On Debian the setup installs missing Git, curl, compiler, QEMU and OVMF packages
with root or sudo privileges. Repository updates are fast-forward only and
locally modified installed checkouts are never overwritten.

OVMF provides the matching UEFI code/variable images for Recovery boot tests.
Windows uses the firmware bundled with QEMU or an explicitly selected matching
OVMF code/variable pair.

Contract, SDK, Libraries, and Distribution are cloned from their public HTTPS
repositories. The setup does not load a GitHub API token, disables interactive
authentication, and ignores local Git credential helpers for these checkouts.

The installed checkouts are consumers, not canonical editing locations.
Changes belong in the corresponding source repository.

The canonical DevKit repository participates in the workspace-wide
`Tools/Github.bat -push -changed` or `./Tools/Github.sh -push -changed`
workflow from the R4OS project root.
Installed toolchains and source checkouts remain excluded from that push.

## License

Original DevKit scripts are licensed under Apache License 2.0. Downloaded tools
retain their upstream licenses; see `THIRD_PARTY_NOTICES.md`.
