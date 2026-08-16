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

## Windows setup

Run:

    Setup/Setup_Windows.bat

The script installs checksum-pinned Zig 0.16.0, Limine 12.0.1, and QEMU
11.0.0. Portable 7-Zip 26.02 tools are used temporarily to extract QEMU. It
then installs the matching Contract, SDK, and Distribution checkouts and
builds the R4OS host tools.

Git, curl, and Windows PowerShell must already be available. All generated
files remain within the DevKit. Repository updates are fast-forward only and
locally modified installed checkouts are never overwritten.

Contract, SDK, Libraries, and Distribution are cloned from their public HTTPS
repositories. The setup does not load a GitHub API token, disables interactive
authentication, and ignores local Git credential helpers for these checkouts.

The installed checkouts are consumers, not canonical editing locations.
Changes belong in the corresponding source repository.

## License

Original DevKit scripts are licensed under Apache License 2.0. Downloaded tools
retain their upstream licenses; see `THIRD_PARTY_NOTICES.md`.
