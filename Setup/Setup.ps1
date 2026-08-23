[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$setupRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$devKitRoot = [IO.Path]::GetFullPath((Join-Path $setupRoot '..'))
$hostId = if ($IsWindows) { 'Windows' } elseif ($IsLinux) { 'Linux' } else { 'Unsupported' }
$executableSuffix = if ($IsWindows) { '.exe' } else { '' }

$zigVersion = '0.16.0'
$limineVersion = '12.0.1'
$qemuVersionPrefix = if ($IsWindows) { 'QEMU emulator version 11.0.0' } else { 'QEMU emulator version 11.0' }
$hostToolsFormat = '4'

$contractRepositoryUrl = 'https://github.com/R4OSDev/r4os-contract.git'
$sdkRepositoryUrl = 'https://github.com/R4OSDev/r4os-sdk.git'
$librariesRepositoryUrl = 'https://github.com/R4OSDev/r4os-libraries.git'
$distributionRepositoryUrl = 'https://github.com/R4OSDev/r4os-distribution.git'

$zigTarget = Join-Path $devKitRoot 'Toolchains/Zig'
$limineTarget = Join-Path $devKitRoot 'Boot/Limine'
$qemuTarget = Join-Path $devKitRoot 'Emulation/QEMU'
$contractTarget = Join-Path $devKitRoot 'SDK/Contract'
$sdkTarget = Join-Path $devKitRoot 'SDK/Core'
$hostToolsTarget = Join-Path $devKitRoot 'HostTools'
$librariesTarget = Join-Path $hostToolsTarget 'Source/Libraries'
$distributionTarget = Join-Path $hostToolsTarget 'Source/Distribution'
$hostToolsBin = Join-Path $hostToolsTarget 'bin'
$hostToolsState = Join-Path $hostToolsTarget '.setup-state'
$cacheTarget = Join-Path $devKitRoot '.Cache'
$tempRoot = Join-Path $setupRoot ('.Setup_' + $hostId + '_' + [Guid]::NewGuid().ToString('N'))

$gitExecutable = $null
$curlExecutable = $null
$zigExecutable = Join-Path $zigTarget ('zig' + $executableSuffix)
$limineExecutable = if ($IsWindows) {
    Join-Path $limineTarget 'limine-tool-windows-x86/limine.exe'
}
else {
    Join-Path $limineTarget 'limine'
}
$qemuExecutable = Join-Path $qemuTarget ('qemu-system-x86_64' + $executableSuffix)

function Get-RequiredCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Description = $Name
    )
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) { throw ($Description + ' wurde nicht gefunden: ' + $Name) }
    return $command.Source
}

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = '',
        [string]$FailureMessage = 'Externer Befehl fehlgeschlagen.'
    )
    $previousLocation = $null
    if ($WorkingDirectory -ne '') { $previousLocation = Get-Location; Set-Location -LiteralPath $WorkingDirectory }
    try {
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) { throw ($FailureMessage + ' Exitcode: ' + $LASTEXITCODE) }
    }
    finally {
        if ($null -ne $previousLocation) { Set-Location -LiteralPath $previousLocation }
    }
}

function Get-ExternalOutput {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = ''
    )
    $previousLocation = $null
    if ($WorkingDirectory -ne '') { $previousLocation = Get-Location; Set-Location -LiteralPath $WorkingDirectory }
    try {
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $output = @(& $FilePath @Arguments 2>&1); $exitCode = $LASTEXITCODE }
        finally { $ErrorActionPreference = $previousErrorAction }
        return [pscustomobject]@{ ExitCode = $exitCode; Output = @($output | ForEach-Object { [string]$_ }) }
    }
    finally {
        if ($null -ne $previousLocation) { Set-Location -LiteralPath $previousLocation }
    }
}

function Test-Version {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Expected,
        [switch]$Exact
    )
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { return $false }
    $result = Get-ExternalOutput $Executable $Arguments
    if ($result.ExitCode -ne 0 -or $result.Output.Count -eq 0) { return $false }
    $line = [string]$result.Output[0]
    if ($Exact) { return $line -ceq $Expected }
    return $line.StartsWith($Expected, [StringComparison]::Ordinal)
}

function Assert-EmptyDirectory {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) { [void](New-Item -ItemType Directory -Path $Path) }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw ($Label + '-Ziel ist kein Verzeichnis: ' + $Path) }
    if ($null -ne (Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1)) {
        throw ($Label + '-Ziel ist nicht leer: ' + $Path)
    }
}

function Remove-EmptyDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ($null -ne (Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1)) {
        throw ('Verzeichnis ist nicht leer und wird nicht entfernt: ' + $Path)
    }
    Remove-Item -LiteralPath $Path
}

function Get-OsRelease {
    $path = '/etc/os-release'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw '/etc/os-release fehlt.' }
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $path) {
        if ($line -match '^([A-Z_]+)=(.*)$') { $values[$matches[1]] = $matches[2].Trim('"', "'") }
    }
    return $values
}

function Invoke-AsRoot {
    param([Parameter(Mandatory = $true)][string]$Executable, [string[]]$Arguments)
    $id = Get-RequiredCommand 'id'
    $idResult = Get-ExternalOutput $id @('-u')
    if ($idResult.ExitCode -ne 0 -or $idResult.Output.Count -eq 0) { throw 'Aktuelle Benutzer-ID konnte nicht bestimmt werden.' }
    if ([string]$idResult.Output[0] -eq '0') {
        Invoke-External $Executable $Arguments -FailureMessage ($Executable + ' ist fehlgeschlagen.')
        return
    }
    $sudo = Get-RequiredCommand 'sudo' 'sudo oder root-Rechte'
    Invoke-External $sudo (@($Executable) + $Arguments) -FailureMessage ($Executable + ' ist mit sudo fehlgeschlagen.')
}

function Install-LinuxPrerequisites {
    if (-not $IsLinux) { return }
    $os = Get-OsRelease
    if ([string]$os.ID -cne 'debian') {
        throw ('Die automatische Linux-Einrichtung unterstuetzt derzeit Debian, erkannt wurde: ' + [string]$os.ID)
    }
    $codename = [string]$os.VERSION_CODENAME
    if ([string]::IsNullOrWhiteSpace($codename)) { throw 'Debian VERSION_CODENAME fehlt in /etc/os-release.' }

    $apt = Get-RequiredCommand 'apt-get'
    $baseMissing = @('curl', 'git', 'tar', 'xz', 'make', 'cc') | Where-Object { $null -eq (Get-Command $_ -ErrorAction SilentlyContinue) }
    $systemQemu = Get-Command 'qemu-system-x86_64' -ErrorAction SilentlyContinue
    $qemuReady = $null -ne $systemQemu -and (Test-Version $systemQemu.Source @('--version') $qemuVersionPrefix)
    if ($baseMissing.Count -eq 0 -and $qemuReady) { Write-Host '[OK] Linux-Systempakete sind bereits vorhanden.'; return }

    Write-Host '=== Debian-Systempakete ==='
    Invoke-AsRoot $apt @('update')
    Invoke-AsRoot $apt @('install', '-y', 'ca-certificates', 'curl', 'git', 'xz-utils', 'build-essential')
    if (-not $qemuReady) {
        Invoke-AsRoot $apt @('install', '-y', '-t', ($codename + '-backports'), 'qemu-system-x86', 'qemu-utils')
    }
}

function Download-File {
    param([Parameter(Mandatory = $true)][string]$Url, [Parameter(Mandatory = $true)][string]$Destination, [Parameter(Mandatory = $true)][string]$Label)
    Write-Host ('Lade ' + $Label + ' herunter ...')
    Invoke-External $curlExecutable @('--fail', '--location', '--retry', '3', '--retry-delay', '2', '--connect-timeout', '30', '--progress-bar', '--output', $Destination, $Url) -FailureMessage ('Download fehlgeschlagen: ' + $Label)
}

function Assert-Hash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('SHA256', 'SHA512')][string]$Algorithm,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )
    Write-Host ('Pruefe ' + $Label + ' ...')
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash
    if (-not $actual.Equals($Expected, [StringComparison]::OrdinalIgnoreCase)) { throw ('Pruefsumme stimmt nicht: ' + $Label) }
}

function Expand-Zip {
    param([Parameter(Mandatory = $true)][string]$Archive, [Parameter(Mandatory = $true)][string]$Destination)
    [void](New-Item -ItemType Directory -Path $Destination)
    Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
}

function Install-Zig {
    if (Test-Version $zigExecutable @('version') $zigVersion -Exact) { Write-Host ('[OK] Zig ' + $zigVersion + ' ist bereits installiert.'); return }
    Assert-EmptyDirectory $zigTarget 'Zig'
    Write-Host ('=== Zig ' + $zigVersion + ' ===')
    if ($IsWindows) {
        $url = 'https://ziglang.org/download/0.16.0/zig-x86_64-windows-0.16.0.zip'
        $hash = '68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e'
        $archive = Join-Path $tempRoot 'zig.zip'; $extract = Join-Path $tempRoot 'Zig'
        Download-File $url $archive 'Zig'; Assert-Hash $archive SHA256 $hash 'Zig'; Expand-Zip $archive $extract
        $source = Join-Path $extract ('zig-x86_64-windows-' + $zigVersion)
    }
    else {
        $url = 'https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz'
        $hash = '70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00'
        $archive = Join-Path $tempRoot 'zig.tar.xz'; $extract = Join-Path $tempRoot 'Zig'
        [void](New-Item -ItemType Directory -Path $extract)
        Download-File $url $archive 'Zig'; Assert-Hash $archive SHA256 $hash 'Zig'
        Invoke-External (Get-RequiredCommand 'tar') @('-xJf', $archive, '-C', $extract) -FailureMessage 'Zig konnte nicht entpackt werden.'
        $source = Join-Path $extract ('zig-x86_64-linux-' + $zigVersion)
    }
    $sourceExecutable = Join-Path $source ('zig' + $executableSuffix)
    if (-not (Test-Version $sourceExecutable @('version') $zigVersion -Exact)) { throw 'Das entpackte Zig-Artefakt besitzt eine unerwartete Version oder Struktur.' }
    Remove-EmptyDirectory $zigTarget; Move-Item -LiteralPath $source -Destination $zigTarget
    Write-Host ('[OK] Zig wurde installiert: ' + $zigTarget)
}

function Install-Limine {
    if (Test-Version $limineExecutable @('--version') ('Limine ' + $limineVersion)) { Write-Host ('[OK] Limine ' + $limineVersion + ' ist bereits installiert.'); return }
    Assert-EmptyDirectory $limineTarget 'Limine'
    Write-Host ('=== Limine ' + $limineVersion + ' ===')
    $url = 'https://github.com/Limine-Bootloader/Limine/releases/download/v12.0.1/limine-binary-12.0.1.zip'
    $hash = '175be9999063b7754af52b2852357f61cbe67a32ad8d3bf0d76d69c8757f9865'
    $archive = Join-Path $tempRoot 'limine.zip'; $extract = Join-Path $tempRoot 'Limine'
    Download-File $url $archive 'Limine'; Assert-Hash $archive SHA256 $hash 'Limine'; Expand-Zip $archive $extract
    $source = Join-Path $extract ('limine-binary-' + $limineVersion)
    if ($IsLinux) { Invoke-External (Get-RequiredCommand 'make') @('-C', $source) -FailureMessage 'Das Limine-Hostwerkzeug konnte nicht gebaut werden.' }
    $sourceExecutable = if ($IsWindows) { Join-Path $source 'limine-tool-windows-x86/limine.exe' } else { Join-Path $source 'limine' }
    if (-not (Test-Version $sourceExecutable @('--version') ('Limine ' + $limineVersion))) { throw 'Das Limine-Artefakt besitzt eine unerwartete Version oder Struktur.' }
    Remove-EmptyDirectory $limineTarget; Move-Item -LiteralPath $source -Destination $limineTarget
    Write-Host ('[OK] Limine wurde installiert: ' + $limineTarget)
}

function Install-QemuWindows {
    $qemuArchive = Join-Path $tempRoot 'qemu.exe'; $sevenZipBootstrap = Join-Path $tempRoot '7zr.exe'
    $sevenZipArchive = Join-Path $tempRoot '7z-x64.exe'; $sevenZipExtract = Join-Path $tempRoot 'SevenZip'; $qemuExtract = Join-Path $tempRoot 'QEMU'
    Download-File 'https://qemu.weilnetz.de/w64/2026/qemu-w64-setup-20260422.exe' $qemuArchive 'QEMU'
    Assert-Hash $qemuArchive SHA512 '64a43c0d39acddc9d30d290935a312a2b5c4fa62cffe6c27090f2a45ca6c8de0f0e8673e1e5117fb116a8742f86df92163531afc23f34758aadfc6d82c1f41a5' 'QEMU'
    Download-File 'https://github.com/ip7z/7zip/releases/download/26.02/7zr.exe' $sevenZipBootstrap '7-Zip-Bootstrap'
    Assert-Hash $sevenZipBootstrap SHA256 '56b8cc9f4971cef253644fafe54063ed7fdca551d4dee0f8c6baa81b855acd72' '7-Zip-Bootstrap'
    Download-File 'https://github.com/ip7z/7zip/releases/download/26.02/7z2602-x64.exe' $sevenZipArchive '7-Zip'
    Assert-Hash $sevenZipArchive SHA256 '6745fa76dc2ea031596d8678f6f6b99c3c1b435b4164a63485adbbc7b8d82ef0' '7-Zip'
    [void](New-Item -ItemType Directory -Path $sevenZipExtract)
    Invoke-External $sevenZipBootstrap @('x', $sevenZipArchive, ('-o' + $sevenZipExtract), '-y') -FailureMessage '7-Zip konnte nicht vorbereitet werden.'
    $sevenZip = Join-Path $sevenZipExtract '7z.exe'
    if (-not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) { throw 'Das 7-Zip-Paket besitzt eine unerwartete Struktur.' }
    [void](New-Item -ItemType Directory -Path $qemuExtract)
    Invoke-External $sevenZip @('x', $qemuArchive, ('-o' + $qemuExtract), '-y') -FailureMessage 'QEMU konnte nicht entpackt werden.'
    $pluginDirectory = Join-Path $qemuExtract '$PLUGINSDIR'; if (Test-Path -LiteralPath $pluginDirectory) { Remove-Item -LiteralPath $pluginDirectory -Recurse -Force }
    $uninstaller = Join-Path $qemuExtract 'qemu-uninstall.exe'; if (Test-Path -LiteralPath $uninstaller) { Remove-Item -LiteralPath $uninstaller -Force }
    if (-not (Test-Version (Join-Path $qemuExtract 'qemu-system-x86_64.exe') @('--version') $qemuVersionPrefix)) { throw 'Das QEMU-Artefakt besitzt eine unerwartete Version oder Struktur.' }
    Remove-EmptyDirectory $qemuTarget; Move-Item -LiteralPath $qemuExtract -Destination $qemuTarget
}

function Install-QemuLinux {
    $systemQemu = Get-RequiredCommand 'qemu-system-x86_64'
    if (-not (Test-Version $systemQemu @('--version') $qemuVersionPrefix)) { throw 'Das installierte Debian-QEMU entspricht nicht Version 11.0.x.' }
    $systemQemuImg = Get-RequiredCommand 'qemu-img'
    [void](New-Item -ItemType SymbolicLink -Path (Join-Path $qemuTarget 'qemu-system-x86_64') -Target $systemQemu)
    [void](New-Item -ItemType SymbolicLink -Path (Join-Path $qemuTarget 'qemu-img') -Target $systemQemuImg)
}

function Install-Qemu {
    if (Test-Version $qemuExecutable @('--version') $qemuVersionPrefix) { Write-Host '[OK] QEMU 11.0.x ist bereits installiert.'; return }
    Assert-EmptyDirectory $qemuTarget 'QEMU'; Write-Host '=== QEMU 11.0.x ==='
    if ($IsWindows) { Install-QemuWindows } else { Install-QemuLinux }
    if (-not (Test-Version $qemuExecutable @('--version') $qemuVersionPrefix)) { throw 'Die installierte QEMU-Version konnte nicht bestaetigt werden.' }
    Write-Host ('[OK] QEMU wurde eingerichtet: ' + $qemuTarget)
}

function Sync-Repository {
    param([Parameter(Mandatory = $true)][string]$Url, [Parameter(Mandatory = $true)][string]$Target, [Parameter(Mandatory = $true)][string]$Label)
    Write-Host ('=== ' + $Label + ' ===')
    if (-not (Test-Path -LiteralPath (Join-Path $Target '.git') -PathType Container)) {
        Assert-EmptyDirectory $Target $Label; Remove-EmptyDirectory $Target
        $cloneTarget = Join-Path $tempRoot ('clone-' + $Label)
        Invoke-External $gitExecutable @('-c', 'credential.helper=', 'clone', '--branch', 'main', '--single-branch', $Url, $cloneTarget) -FailureMessage ($Label + ' konnte nicht geklont werden.')
        Move-Item -LiteralPath $cloneTarget -Destination $Target
        Write-Host ('[OK] ' + $Label + ' wurde installiert: ' + $Target); return
    }
    $status = Get-ExternalOutput $gitExecutable @('-C', $Target, 'status', '--porcelain', '--untracked-files=normal')
    if ($status.ExitCode -ne 0) { throw ($Label + '-Status konnte nicht gelesen werden.') }
    if ($status.Output.Count -gt 0) { throw ($Label + '-Verbraucherkopie enthaelt lokale Aenderungen: ' + $Target) }
    $origin = Get-ExternalOutput $gitExecutable @('-C', $Target, 'remote', 'get-url', 'origin')
    if ($origin.ExitCode -ne 0 -or $origin.Output.Count -eq 0 -or -not ([string]$origin.Output[0]).Equals($Url, [StringComparison]::OrdinalIgnoreCase)) { throw ($Label + '-Verbraucherkopie besitzt ein unerwartetes origin.') }
    $branch = Get-ExternalOutput $gitExecutable @('-C', $Target, 'branch', '--show-current')
    if ($branch.ExitCode -ne 0 -or $branch.Output.Count -eq 0 -or [string]$branch.Output[0] -cne 'main') { throw ($Label + '-Verbraucherkopie steht nicht auf main.') }
    Invoke-External $gitExecutable @('-c', 'credential.helper=', '-C', $Target, 'pull', '--ff-only', 'origin', 'main') -FailureMessage ($Label + ' konnte nicht aktualisiert werden.')
    Write-Host ('[OK] ' + $Label + ' ist aktuell.')
}

function Get-RepositoryCommit {
    param([Parameter(Mandatory = $true)][string]$Target, [Parameter(Mandatory = $true)][string]$Label)
    $result = Get-ExternalOutput $gitExecutable @('-C', $Target, 'rev-parse', 'HEAD')
    if ($result.ExitCode -ne 0 -or $result.Output.Count -eq 0) { throw ($Label + '-Commit konnte nicht bestimmt werden.') }
    return [string]$result.Output[0]
}

function Read-StateFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    $state = @{}; if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $state }
    foreach ($line in Get-Content -LiteralPath $Path) { $separator = $line.IndexOf('='); if ($separator -gt 0) { $state[$line.Substring(0, $separator)] = $line.Substring($separator + 1) } }
    return $state
}

function Test-HostToolsCurrent {
    param([hashtable]$Commits)
    foreach ($name in @('api-contract-gen', 'r4l-contract-gen', 'r4xbuilder', 'module-catalog', 'imagecreater', 'ntfsverify', 'r4upack', 'seriallink-host', 'image-plan', 'preload-image', 'default-registry')) {
        if (-not (Test-Path -LiteralPath (Join-Path $hostToolsBin ($name + $executableSuffix)) -PathType Leaf)) { return $false }
    }
    $state = Read-StateFile $hostToolsState
    return (
        $state['FORMAT'] -ceq $hostToolsFormat -and
        $state['HOST'] -ceq $hostId -and
        $state['CONTRACT_COMMIT'] -ceq $Commits.Contract -and
        $state['SDK_COMMIT'] -ceq $Commits.SDK -and
        $state['LIBRARIES_COMMIT'] -ceq $Commits.Libraries -and
        $state['DISTRIBUTION_COMMIT'] -ceq $Commits.Distribution -and
        $state['ZIG_VERSION'] -ceq $zigVersion
    )
}

function Build-HostTools {
    param([hashtable]$Commits)
    Write-Host '=== R4OS HostTools ==='
    $contractPrefix = Join-Path $tempRoot 'ContractTools'; $sdkPrefix = Join-Path $tempRoot 'SdkTools'; $distributionPrefix = Join-Path $tempRoot 'DistributionTools'
    $globalCache = Join-Path $cacheTarget 'Zig/Global'; $contractCache = Join-Path $cacheTarget 'Zig/Contract'; $sdkCache = Join-Path $cacheTarget 'Zig/SDK'; $distributionCache = Join-Path $cacheTarget 'Zig/Distribution'
    Write-Host 'Baue Contract-Hosttools ...'
    Invoke-External $zigExecutable @('build', '--cache-dir', $contractCache, '--global-cache-dir', $globalCache, '--prefix', $contractPrefix, '-Doptimize=ReleaseSafe') $contractTarget 'Contract-Hosttools konnten nicht gebaut werden.'
    Write-Host 'Baue SDK-Hosttools ...'
    Invoke-External $zigExecutable @('build', '--cache-dir', $sdkCache, '--global-cache-dir', $globalCache, '--prefix', $sdkPrefix, '-Doptimize=ReleaseSafe', ('--fork=' + $contractTarget)) $sdkTarget 'SDK-Hosttools konnten nicht gebaut werden.'
    Write-Host 'Baue Distribution-Hosttools ...'
    Invoke-External $zigExecutable @('build', '--cache-dir', $distributionCache, '--global-cache-dir', $globalCache, '--prefix', $distributionPrefix, '-Doptimize=ReleaseSafe', ('--fork=' + $sdkTarget), ('--fork=' + $contractTarget), ('--fork=' + $librariesTarget)) $distributionTarget 'Distribution-Hosttools konnten nicht gebaut werden.'

    [void](New-Item -ItemType Directory -Path $hostToolsBin -Force)
    $sources = [ordered]@{
        'api-contract-gen' = $contractPrefix; 'r4l-contract-gen' = $sdkPrefix; 'r4xbuilder' = $sdkPrefix; 'module-catalog' = $sdkPrefix
        'imagecreater' = $distributionPrefix; 'ntfsverify' = $distributionPrefix; 'r4upack' = $distributionPrefix; 'seriallink-host' = $distributionPrefix
        'image-plan' = $distributionPrefix; 'preload-image' = $distributionPrefix; 'default-registry' = $distributionPrefix
    }
    foreach ($entry in $sources.GetEnumerator()) {
        $fileName = $entry.Key + $executableSuffix; $source = Join-Path $entry.Value ('bin/' + $fileName)
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw ('Erwartetes Hosttool fehlt: ' + $source) }
        $destination = Join-Path $hostToolsBin $fileName
        Copy-Item -LiteralPath $source -Destination $destination -Force
        if ($IsLinux) { Invoke-External (Get-RequiredCommand 'chmod') @('755', $destination) -FailureMessage ('Ausfuehrbarkeitsbit konnte nicht gesetzt werden: ' + $destination) }
    }
    $stateLines = @(
        "FORMAT=$hostToolsFormat"
        "HOST=$hostId"
        "CONTRACT_COMMIT=$($Commits.Contract)"
        "SDK_COMMIT=$($Commits.SDK)"
        "LIBRARIES_COMMIT=$($Commits.Libraries)"
        "DISTRIBUTION_COMMIT=$($Commits.Distribution)"
        "ZIG_VERSION=$zigVersion"
    )
    $stateLines | Set-Content -LiteralPath $hostToolsState -Encoding utf8NoBOM
    Write-Host ('[OK] R4OS HostTools wurden installiert: ' + $hostToolsBin)
}

function Remove-SetupTemp {
    if (-not (Test-Path -LiteralPath $tempRoot)) { return }
    $resolved = [IO.Path]::GetFullPath($tempRoot); $parent = [IO.Path]::GetFullPath((Split-Path -Parent $resolved)); $leaf = Split-Path -Leaf $resolved
    if (-not $parent.Equals($setupRoot, [StringComparison]::OrdinalIgnoreCase) -or -not $leaf.StartsWith('.Setup_', [StringComparison]::Ordinal)) { throw ('Unsicherer temporaerer Bereinigungspfad wurde abgelehnt: ' + $resolved) }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

try {
    if ((Split-Path -Leaf $setupRoot) -cne 'Setup' -or (Split-Path -Leaf $devKitRoot) -cne 'DevKit') { throw 'Setup.ps1 muss unter DevKit/Setup liegen.' }
    if ($hostId -ceq 'Unsupported') { throw 'Unterstuetzt werden Windows und Linux.' }
    if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne [Runtime.InteropServices.Architecture]::X64) { throw 'Das DevKit-Setup unterstuetzt derzeit nur x86_64-Hosts.' }
    if ($IsLinux) { Install-LinuxPrerequisites }
    $gitExecutable = Get-RequiredCommand $(if ($IsWindows) { 'git.exe' } else { 'git' }) 'Git'
    $curlExecutable = Get-RequiredCommand $(if ($IsWindows) { 'curl.exe' } else { 'curl' }) 'curl'
    $env:GIT_ASKPASS = ''; $env:SSH_ASKPASS = ''; $env:GIT_TERMINAL_PROMPT = '0'; $env:GCM_INTERACTIVE = 'Never'
    [void](New-Item -ItemType Directory -Path $tempRoot)
    Install-Zig; Install-Limine; Install-Qemu
    Sync-Repository $contractRepositoryUrl $contractTarget 'Contract'; Sync-Repository $sdkRepositoryUrl $sdkTarget 'SDK'
    Sync-Repository $librariesRepositoryUrl $librariesTarget 'Libraries'; Sync-Repository $distributionRepositoryUrl $distributionTarget 'Distribution'
    $commits = @{ Contract = Get-RepositoryCommit $contractTarget 'Contract'; SDK = Get-RepositoryCommit $sdkTarget 'SDK'; Libraries = Get-RepositoryCommit $librariesTarget 'Libraries'; Distribution = Get-RepositoryCommit $distributionTarget 'Distribution' }
    if (Test-HostToolsCurrent $commits) { Write-Host '[OK] R4OS HostTools sind bereits aktuell.' } else { Build-HostTools $commits }
    Write-Host ''; Write-Host 'R4OS DevKit wurde erfolgreich eingerichtet.'
}
catch {
    Write-Host ''; Write-Error ('R4OS DevKit-Setup fehlgeschlagen: ' + $_.Exception.Message); exit 1
}
finally {
    try { Remove-SetupTemp } catch { Write-Warning $_.Exception.Message }
}
