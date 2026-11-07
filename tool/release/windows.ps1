# Packages the Windows release as an installable .exe plus a portable ZIP.
#
# Tesseract is bundled because OCR runs it as a child process; libmpv comes from
# media_kit's CMake plugin and must already be in the Flutter release bundle.
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$dist = Join-Path $root 'dist'
$staging = Join-Path $root 'build\release-windows'
$release = Join-Path $root 'build\windows\x64\runner\Release'

if (-not (Test-Path (Join-Path $release 'mindpocket.exe'))) {
    throw "Windows release executable not found in $release. Run 'flutter build windows --release' first."
}
foreach ($file in @('libmpv-2.dll', 'sqlite3.dll',
    'tesseract\tesseract.exe', 'tesseract\tessdata\eng.traineddata')) {
    if (-not (Test-Path (Join-Path $release $file))) {
        throw "$file was not bundled by the Flutter build; refusing to ship an incomplete runtime."
    }
}

New-Item -ItemType Directory -Force -Path $dist, $staging | Out-Null

$pubspec = Get-Content (Join-Path $root 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
    throw 'pubspec.yaml has no semantic version with a build number.'
}
$semver = $Matches[1]
$build = $Matches[2]
$version = "$semver+$build"

# The Flutter build already assembles the complete native/OCR runtime.
$app = Join-Path $staging 'app'
if (Test-Path $app) { Remove-Item -Recurse -Force $app }
Copy-Item -Recurse -Force $release $app

$iss = Join-Path $staging 'mindpocket.iss'
@"
#define AppName "MindPocket"
#define AppVersion "$semver"
#define AppBuild "$build"
#define AppExe "mindpocket.exe"

[Setup]
AppId={{7E1B3C51-0B6E-4F0C-9C64-2F6A2C48B7D1}
AppName={#AppName}
AppVersion={#AppVersion}.{#AppBuild}
DefaultDirName={autopf}\MindPocket
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
OutputDir=$dist
OutputBaseFilename=MindPocket-$version-windows-installer
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
SetupIconFile=$root\windows\runner\resources\app_icon.ico
DisableProgramGroupPage=yes

[Files]
Source: "$app\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
"@ | Set-Content -Encoding UTF8 $iss

# Inno Setup installs per-machine for choco, per-user for winget.
$iscc = $null
foreach ($candidate in @(
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
)) {
    if (Test-Path $candidate) { $iscc = $candidate; break }
}
if (-not $iscc) {
    $iscc = (Get-Command iscc.exe -ErrorAction Stop).Source
}
& $iscc /Qp $iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE." }

# Portable archive is what the workflow smoke-launches without installing.
$portable = Join-Path $staging "portable"
if (Test-Path $portable) { Remove-Item -Recurse -Force $portable }
Copy-Item -Recurse -Force $app $portable
$zip = Join-Path $dist "MindPocket-$version-windows-x64.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path "$portable\*" -DestinationPath $zip -CompressionLevel Optimal

# Smoke-check the packaged OCR runtime before declaring success.
& (Join-Path $portable 'tesseract\tesseract.exe') --version | Select-Object -First 1
if ($LASTEXITCODE -ne 0) { throw 'Bundled Tesseract failed to run.' }

$log = Join-Path $root 'build\smoke-windows.log'
$process = Start-Process -FilePath (Join-Path $portable 'mindpocket.exe') -PassThru `
    -RedirectStandardOutput $log -RedirectStandardError "$log.err"
Start-Sleep -Seconds 15
if ($process.HasExited) {
    $output = ''
    if (Test-Path $log) { $output += Get-Content $log -Raw }
    if (Test-Path "$log.err") { $output += Get-Content "$log.err" -Raw }
    throw "MindPocket exited during launch with code $($process.ExitCode).`n$output"
}
Stop-Process -Id $process.Id -Force
Write-Output 'MindPocket launched and stayed resident for 15s.'

Get-ChildItem $dist | Where-Object { $_.Name -match 'windows' } | ForEach-Object {
    $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
    Write-Output ("{0}`t{1}`t{2}" -f $_.Name, $_.Length, $hash)
}
