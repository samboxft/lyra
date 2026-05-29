#Requires -Version 5.1
# Build Lyra (release) on Windows with MSVC + offline SQLx.
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

$vcvars = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) {
    throw "Visual Studio 2022 Build Tools (C++) not found. Install from https://visualstudio.microsoft.com/visual-cpp-build-tools/"
}

$pathExtra = @(
    "$env:USERPROFILE\.cargo\bin",
    "$env:LOCALAPPDATA\PortableGit\cmd",
    "$env:LOCALAPPDATA\cmake\cmake-4.0.2-windows-x86_64\bin",
    "$env:LOCALAPPDATA\nasm\nasm-2.16.03"
) -join ";"

cmd /c "call `"$vcvars`" && set PATH=$pathExtra;%PATH% && cargo build --release"
exit $LASTEXITCODE
