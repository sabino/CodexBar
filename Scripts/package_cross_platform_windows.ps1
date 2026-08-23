param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$Architecture,
    [Parameter(Mandatory = $true)][string]$BinDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($Version -notmatch '^[0-9A-Za-z._-]+$') {
    throw "Invalid package version: $Version"
}
if ($Architecture -notmatch '^[0-9A-Za-z._-]+$') {
    throw "Invalid architecture: $Architecture"
}

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$Executable = Join-Path $BinDirectory "CodexBarCross.exe"
if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
    throw "Missing CodexBarCross executable: $Executable"
}

$CoreResourceCandidates = @(
    (Join-Path $BinDirectory "CodexBar_CodexBarCore.resources"),
    (Join-Path $BinDirectory "CodexBar_CodexBarCore.bundle")
)
$CoreResources = $CoreResourceCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Container } |
    Select-Object -First 1
if (-not $CoreResources) {
    throw "Missing CodexBarCore resource bundle in $BinDirectory"
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$StageDirectory = Join-Path ([IO.Path]::GetTempPath()) ("codexbar-cross-package-" + [Guid]::NewGuid())
$PackageRoot = Join-Path $StageDirectory "CodexBarCross"

try {
    New-Item -ItemType Directory -Force -Path $PackageRoot | Out-Null
    Copy-Item -LiteralPath $Executable -Destination $PackageRoot
    Copy-Item -LiteralPath $CoreResources -Destination $PackageRoot -Recurse
    Copy-Item -LiteralPath (Join-Path $RepositoryRoot "LICENSE") -Destination $PackageRoot
    Copy-Item -LiteralPath (Join-Path $RepositoryRoot "docs/CROSS_PLATFORM.md") `
        -Destination (Join-Path $PackageRoot "README.md")
    Set-Content -LiteralPath (Join-Path $PackageRoot "VERSION") -Value $Version -Encoding utf8NoBOM

    Get-ChildItem -LiteralPath $BinDirectory -Directory | Where-Object {
        $_.Name -like "*.resources" -or $_.Name -like "*.bundle"
    } | ForEach-Object {
        $Destination = Join-Path $PackageRoot $_.Name
        if (-not (Test-Path -LiteralPath $Destination)) {
            Copy-Item -LiteralPath $_.FullName -Destination $PackageRoot -Recurse
        }
    }

    Get-ChildItem -LiteralPath $BinDirectory -Filter "*.dll" -File -ErrorAction SilentlyContinue |
        Copy-Item -Destination $PackageRoot

    $TargetInfo = (& swiftc -print-target-info | ConvertFrom-Json)
    foreach ($RuntimePath in @($TargetInfo.paths.runtimeLibraryPaths)) {
        if (Test-Path -LiteralPath $RuntimePath -PathType Container) {
            Get-ChildItem -LiteralPath $RuntimePath -Filter "*.dll" -File -ErrorAction SilentlyContinue |
                Copy-Item -Destination $PackageRoot -Force
        }
    }

    if ($env:CODEXBAR_VCPKG_BIN_DIR -and
        (Test-Path -LiteralPath $env:CODEXBAR_VCPKG_BIN_DIR -PathType Container)) {
        Get-ChildItem -LiteralPath $env:CODEXBAR_VCPKG_BIN_DIR -Filter "*.dll" -File |
            Copy-Item -Destination $PackageRoot -Force
    }

    $AssetName = "CodexBarCross-v$Version-windows-$Architecture.zip"
    $AssetPath = Join-Path $OutputDirectory $AssetName
    Compress-Archive -LiteralPath $PackageRoot -DestinationPath $AssetPath -CompressionLevel Optimal -Force

    $Hash = (Get-FileHash -LiteralPath $AssetPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath "$AssetPath.sha256" -Value "$Hash  $AssetName" -Encoding ascii
    Write-Output $AssetPath
} finally {
    if (Test-Path -LiteralPath $StageDirectory) {
        Remove-Item -LiteralPath $StageDirectory -Recurse -Force
    }
}
