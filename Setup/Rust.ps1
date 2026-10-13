param()

# Keep native switches, including Cargo's literal -- separator, unbound.
$Arguments = @($args)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$devKitRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pin = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'RustToolchain.json') -Raw | ConvertFrom-Json -AsHashtable
if ($pin.format -ne 1) { throw 'Unbekanntes Rust-Toolchainformat.' }
if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne [Runtime.InteropServices.Architecture]::X64) {
    throw 'Die Rust-Toolchain unterstuetzt derzeit x86_64-Hosts.'
}
$hostName = if ($IsWindows) { 'Windows' } elseif ($IsLinux) { 'Linux' } else { throw 'Rust-Setup unterstuetzt Windows und Linux.' }
$suffix = if ($IsWindows) { '.exe' } else { '' }
$hostTriple = $pin.hosts[$hostName].triple
$toolchainName = $pin.rust_version + '-' + $hostTriple
$rustRoot = Join-Path $devKitRoot 'Toolchains/Rust'
$cargoHome = Join-Path $rustRoot 'cargo'
$rustupHome = Join-Path $rustRoot 'rustup'
$cargoBin = Join-Path $cargoHome 'bin'
$rustupExe = Join-Path $cargoBin ('rustup' + $suffix)
$toolchainRoot = Join-Path $rustupHome ('toolchains/' + $toolchainName)
$llvmBin = Join-Path $toolchainRoot ('lib/rustlib/' + $hostTriple + '/bin')
$tool = if ($Arguments.Count -eq 0) { 'describe' } else { $Arguments[0] }
$toolArgs = @()
if ($Arguments.Count -gt 1) { $toolArgs = @($Arguments[1..($Arguments.Count - 1)]) }
$exitCode = 0
$environmentNames = @('RUSTUP_HOME', 'CARGO_HOME', 'RUSTUP_TOOLCHAIN', 'RUSTUP_AUTO_INSTALL',
    'RUSTUP_DIST_SERVER', 'RUSTUP_UPDATE_ROOT', 'RUSTUP_INIT_SKIP_PATH_CHECK', 'PATH')
$previousEnvironment = @{}
foreach ($name in $environmentNames) { $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }

function Invoke-RustNative([string]$Executable, [string[]]$NativeArguments) {
    & $Executable @NativeArguments
    if ($LASTEXITCODE -ne 0) { throw ('Rust-Werkzeug fehlgeschlagen: ' + [IO.Path]::GetFileName($Executable) + ', Exitcode ' + $LASTEXITCODE) }
}

function Get-RustOutput([string]$Executable, [string[]]$NativeArguments) {
    $result = @(& $Executable @NativeArguments)
    if ($LASTEXITCODE -ne 0) { throw ('Rust-Pruefung fehlgeschlagen: ' + [IO.Path]::GetFileName($Executable)) }
    return $result
}

function Test-RustReady {
    if (-not (Test-Path -LiteralPath $rustupExe -PathType Leaf)) { return $false }
    $rustcExe = Join-Path $toolchainRoot ('bin/rustc' + $suffix)
    if (-not (Test-Path -LiteralPath $rustcExe -PathType Leaf)) { return $false }
    $rustupVersion = (Get-RustOutput $rustupExe @('--version')) -join ' '
    $rustcVersion = (Get-RustOutput $rustcExe @('--version')) -join ' '
    if (-not $rustupVersion.StartsWith('rustup ' + $pin.rustup_version + ' ') -or
        -not $rustcVersion.StartsWith('rustc ' + $pin.rust_version + ' ')) { return $false }
    $components = @(Get-RustOutput $rustupExe @('component', 'list', '--toolchain', $toolchainName, '--installed'))
    foreach ($component in $pin.components) {
        $installedName = if ($component -eq 'rust-src') { 'rust-src' } else { $component.Replace('-preview', '') + '-' + $hostTriple }
        if ($installedName -notin $components) { return $false }
    }
    if (('rust-std-' + $pin.kernel_target) -notin $components) { return $false }
    foreach ($name in @('rust-lld', 'llvm-readobj', 'llvm-objdump', 'llvm-objcopy', 'llvm-nm', 'llvm-size')) {
        if (-not (Test-Path -LiteralPath (Join-Path $llvmBin ($name + $suffix)) -PathType Leaf)) { return $false }
    }
    return $true
}

function Get-RustDownload([string]$Url, [string]$Destination, [string]$ExpectedHash) {
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        if ((Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -ieq $ExpectedHash) { return }
    }
    $curl = Get-Command $(if ($IsWindows) { 'curl.exe' } else { 'curl' }) -ErrorAction Stop
    Write-Host ('Lade ' + [IO.Path]::GetFileName($Destination) + ' ...')
    Invoke-RustNative $curl.Source @('--fail', '--location', '--proto', '=https', '--tlsv1.2', '--retry', '3',
        '--connect-timeout', '30', '--max-time', '300', '--silent', '--show-error', '--output', $Destination, $Url)
    if ((Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -ine $ExpectedHash) {
        throw ('Rust-Pruefsumme stimmt nicht: ' + [IO.Path]::GetFileName($Destination))
    }
}

function Install-Rust {
    if (Test-RustReady) { Write-Host ('[OK] Rust ' + $pin.rust_version + ', Komponenten und Kerneltarget sind bereits installiert.'); return }
    $cacheRoot = Join-Path $devKitRoot '.Cache/Rust'
    [void](New-Item -ItemType Directory -Path $cacheRoot -Force)
    $manifest = Join-Path $cacheRoot ('channel-rust-' + $pin.rust_version + '.toml')
    Get-RustDownload ('https://static.rust-lang.org/dist/channel-rust-' + $pin.rust_version + '.toml') $manifest $pin.manifest_sha256
    $bootstrap = Join-Path $cacheRoot ('rustup-init-' + $pin.rustup_version + '-' + $hostTriple + $suffix)
    Get-RustDownload ('https://static.rust-lang.org/rustup/archive/' + $pin.rustup_version + '/' + $hostTriple + '/rustup-init' + $suffix) `
        $bootstrap $pin.hosts[$hostName].rustup_sha256
    if ($IsLinux) { Invoke-RustNative (Get-Command 'chmod' -ErrorAction Stop).Source @('755', $bootstrap) }
    Invoke-RustNative $bootstrap @('-y', '--no-modify-path', '--profile', 'minimal', '--default-host', $hostTriple, '--default-toolchain', 'none')
    Invoke-RustNative $rustupExe @('set', 'auto-self-update', 'disable')
    $installArgs = @('toolchain', 'install', $toolchainName, '--profile', 'minimal', '--target', $pin.kernel_target)
    foreach ($component in $pin.components) { $installArgs += @('--component', $component) }
    Invoke-RustNative $rustupExe $installArgs
    Invoke-RustNative $rustupExe @('default', $toolchainName)
    if (-not (Test-RustReady)) { throw 'Rust-Installation ist nicht vollstaendig oder hat eine unerwartete Version.' }
    [ordered]@{
        format = 1; host = $hostTriple; rust_version = $pin.rust_version; rustup_version = $pin.rustup_version
        kernel_target = $pin.kernel_target; components = $pin.components; manifest_sha256 = $pin.manifest_sha256
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $rustRoot 'installation.json') -Encoding utf8NoBOM
    Write-Host ('[OK] Rust ' + $pin.rust_version + ' installiert: ' + $rustRoot)
}

try {
    $env:RUSTUP_HOME = $rustupHome
    $env:CARGO_HOME = $cargoHome
    $env:RUSTUP_TOOLCHAIN = $toolchainName
    $env:RUSTUP_AUTO_INSTALL = '0'
    $env:RUSTUP_DIST_SERVER = 'https://static.rust-lang.org'
    $env:RUSTUP_UPDATE_ROOT = 'https://static.rust-lang.org/rustup'
    $env:RUSTUP_INIT_SKIP_PATH_CHECK = 'yes'
    $env:PATH = $cargoBin + [IO.Path]::PathSeparator + $previousEnvironment['PATH']
    if ($tool -eq 'setup') {
        if ($toolArgs.Count -ne 0) { throw 'Rust setup akzeptiert keine weiteren Argumente.' }
        Install-Rust
    }
    elseif ($tool -eq 'describe') {
        [ordered]@{
            rust_version = $pin.rust_version; rustup_version = $pin.rustup_version; host = $hostTriple
            kernel_target = $pin.kernel_target; root = $rustRoot; cargo_home = $cargoHome; rustup_home = $rustupHome
            toolchain = $toolchainRoot; llvm_bin = $llvmBin; installed = (Test-RustReady)
        } | ConvertTo-Json
    }
    else {
        if ($tool -in @('rustc', 'cargo', 'rustup', 'rustfmt', 'cargo-clippy', 'clippy-driver')) {
            $executable = Join-Path $cargoBin ($tool + $suffix)
        }
        elseif ($tool -in @('rust-lld', 'llvm-readobj', 'llvm-objdump', 'llvm-objcopy', 'llvm-nm', 'llvm-size')) {
            $executable = Join-Path $llvmBin ($tool + $suffix)
        }
        else { throw ('Unbekanntes Rust-Werkzeug: ' + $tool) }
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'Rust-Werkzeug fehlt. Zuerst Rust.sh setup beziehungsweise Rust.bat setup ausfuehren.' }
        & $executable @toolArgs
        $exitCode = $LASTEXITCODE
    }
}
catch {
    Write-Error $_ -ErrorAction Continue
    $exitCode = 1
}
finally {
    foreach ($name in $environmentNames) {
        if ($null -eq $previousEnvironment[$name]) {
            Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue
        }
        else {
            Set-Item -LiteralPath ('Env:' + $name) -Value $previousEnvironment[$name]
        }
    }
}
exit $exitCode
