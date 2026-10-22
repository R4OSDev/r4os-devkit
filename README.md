# R4OS DevKit

The R4OS DevKit bootstraps a local development environment without committing
downloaded toolchains or installed source checkouts.

    SDK/Core/         Installed R4OS SDK
    SDK/Contract/     Matching platform Contract
    Setup/            Host-specific setup scripts
    Toolchains/Zig/   Zig toolchain
    Toolchains/Rust/  Isolated, pinned Rust/Cargo toolchain
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
checksum-pinned Zig 0.16.0, Rust 1.99.0 and Limine 12.0.1, prepares QEMU 11.0.x, installs
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

## Rust preparation

Install only the Rust toolchain from the workspace root:

    ./DevKit/Setup/Rust.sh setup
    DevKit\Setup\Rust.bat setup

`Setup/ZigToolchain.json` is the shared Zig version/URL/hash source read by
setup and exported SDK capability metadata. No compiler version changed.

`Setup/RustToolchain.json` pins Rust 1.99.0 and rustup 1.29.1, the release
manifest and both bootstrap checksums. The minimal host toolchain includes
rustc/Cargo and adds rustfmt, Clippy, LLVM tools, Rust sources and the
`x86_64-unknown-none` target. Its `rust-lld` links the freestanding kernel;
LLVM readobj/objdump/objcopy/nm/size inspect ELF output. The production kernel
uses this pinned stable toolchain;
other modules and the separate Recovery kernel retain Zig. Use the kernel
Build.sh/Build.bat to enforce its checked profile and link contract.

Use the launcher for each invocation so the isolated Cargo/rustup homes and
the exact toolchain are selected together, independent of system Rust:

    ./DevKit/Setup/Rust.sh rustc --version
    ./DevKit/Setup/Rust.sh cargo build --target x86_64-unknown-none
    ./DevKit/Setup/Rust.sh cargo fmt -- --check
    ./DevKit/Setup/Rust.sh cargo clippy --target x86_64-unknown-none
    ./DevKit/Setup/Rust.sh llvm-readobj --file-headers path/to/kernel.elf
    ./DevKit/Setup/Rust.sh describe

On Windows use `DevKit\Setup\Rust.bat` with the same arguments. Cargo commands
run from a Rust crate directory or use `--manifest-path <Cargo.toml>`.
The shared PowerShell launcher restores process environment variables when it returns
and makes no shell-profile or persistent PATH changes. Compiler homes,
downloads and installation metadata stay in ignored DevKit directories.
Native Windows host programs additionally require the MSVC/Windows SDK
prerequisites; the freestanding target uses the bundled linker. This setup
has been exercised on Linux; Windows execution is not claimed.

## Independent SDK Rust tools

Release exports hash/copy canonical files from the pinned Git revisions,
matching source archives independently of checkout CRLF/LF filters. Technical
exports use the current working files and remain explicitly marked technical.

`Setup/RustToolchain.json` also defines `r4os-rust-tools-v1`. Select the minimal
SDK tool profile without changing any version pins:

    ./Setup/Rust.sh --profile sdk --root /absolute/install --cache-root /absolute/cache setup
    ./Setup/Rust.sh --profile sdk --root /absolute/install check

Put the options before the command. Paths containing spaces are supported;
relative roots resolve from the toolset directory. The SDK profile requires
LLVM tools and the bare target, together with rustc/Cargo. `rust-src` is not
needed. `--development-tools` adds optional rustfmt/Clippy. The legacy default
DevKit profile and its extra components remain available.

The producer exports a separately usable toolset from clean source repositories:

    pwsh -File Setup/Export-RustTools.ps1 -Destination /absolute/toolset -PackagerLinux /path/r4xbuilder -PackagerWindows /path/r4xbuilder.exe -CatalogLinux /path/module-catalog -CatalogWindows /path/module-catalog.exe -HeapRuntime /path/r4sdk_heap.o

The SDK packagers are built by the publisher with pinned Zig; users receive
ELF64/PE32+ x86_64 executables and do not need Zig for these tools. The exporter
copies this same installer and thin launchers, the single toolchain pin, exact
Rust release component URLs/hashes, CPU baseline, both packagers and both ModuleCatalog executables. The
versioned `RustToolsProfile.json` records source commits, SDK/Contract versions,
required versus optional components and every input file hash. From0.86.36 it
also binds the selected SDK builder/runtime/profile and Contract binding inputs;
the SDK driver rejects a mismatched source package. Exported Profile/Templates
are copied from canonical SDK templates and included in file hashes; this is
no independently maintained template set. `-Technical`
marks development exports with potentially dirty sources; it is not a release.

Run the exported `Setup/Rust.sh` or `Setup\Rust.bat` without the rest of DevKit.
`describe` emits JSON; `check` emits the same JSON and exits nonzero for missing,
wrong or partial tools. Output includes actual Cargo version, installed
components, profile/pin hashes and the selected linker's SHA256. A complete
export and installed compiler are separate facts (`toolset_metadata_present`
and `complete_toolset`). The raw tool runner is not the module build driver:
Cargo.lock, offline dependencies and rejection of project/global profile or
flag overrides and explicit SDK release settings are specified in
Contract/Module/RustModuleV2.txt and enforced
by the matched SDK module builder.

Linux qualification in 0.86.34 used an empty installation root with spaces and
an independent cache: five required components installed; no optional tools,
Rust sources, complete DevKit or global Rust configuration were needed.
Missing rustup, a missing exported packager and a corrupted exported packager
were rejected. The Windows packager was cross-built and its PE header checked;
Windows execution remains unqualified. This is host tool work without normal
R4OS runtime effect and requires no STANDARD benchmark.

## License

Original DevKit scripts are licensed under Apache License 2.0. Downloaded tools
retain their upstream licenses; see `THIRD_PARTY_NOTICES.md`.
