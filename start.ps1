Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RuntimeDir = Join-Path $RootDir '.phoneshop-runtime'
$AppDir = Join-Path $RuntimeDir 'app'
$ToolsDir = Join-Path $RootDir '.tools'
$PhpDir = Join-Path $ToolsDir 'php'
$ComposerDir = Join-Path $ToolsDir 'composer'
$ComposerPhar = Join-Path $ComposerDir 'composer.phar'
$PidFile = Join-Path $RuntimeDir 'server.pid'
$PortFile = Join-Path $RuntimeDir 'server.port'
$LogFile = Join-Path $RuntimeDir 'server.log'
$ErrorLogFile = Join-Path $RuntimeDir 'server-error.log'

$HostName = if ($env:PHONESHOP_HOST) { $env:PHONESHOP_HOST } else { '0.0.0.0' }
$Port = if ($env:PHONESHOP_PORT) { $env:PHONESHOP_PORT } else { '8000' }
$UrlHost = if ($env:PHONESHOP_URL_HOST) { $env:PHONESHOP_URL_HOST } else { 'localhost' }
$AppUrl = "http://$UrlHost`:$Port"
$DbConnection = if ($env:PHONESHOP_DB_CONNECTION) { $env:PHONESHOP_DB_CONNECTION } else { 'sqlite' }
$DbHost = if ($env:PHONESHOP_DB_HOST) { $env:PHONESHOP_DB_HOST } else { '127.0.0.1' }
$DbPort = if ($env:PHONESHOP_DB_PORT) { $env:PHONESHOP_DB_PORT } else { '3306' }
$DbDatabase = if ($env:PHONESHOP_DB_DATABASE) { $env:PHONESHOP_DB_DATABASE } else { 'phone_shop' }
$DbUsername = if ($env:PHONESHOP_DB_USERNAME) { $env:PHONESHOP_DB_USERNAME } else { 'root' }
$DbPassword = if ($env:PHONESHOP_DB_PASSWORD) { $env:PHONESHOP_DB_PASSWORD } else { '' }

function Ensure-Directory {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-PhpCommand {
    $localPhp = Join-Path $PhpDir 'php.exe'
    if (Test-Path -LiteralPath $localPhp) {
        return $localPhp
    }

    $php = Get-Command php -ErrorAction SilentlyContinue
    if ($php) {
        return $php.Source
    }

    return $null
}

function Configure-PortablePhpIni {
    $phpIniProduction = Join-Path $PhpDir 'php.ini-production'
    $phpIni = Join-Path $PhpDir 'php.ini'
    if (Test-Path -LiteralPath $phpIniProduction) {
        Copy-Item -LiteralPath $phpIniProduction -Destination $phpIni -Force
    } elseif (-not (Test-Path -LiteralPath $phpIni)) {
        Set-Content -LiteralPath $phpIni -Value '' -Encoding ASCII
    }

    $ini = Get-Content -LiteralPath $phpIni -Raw
    $ini = $ini -replace ';\s*extension_dir\s*=.*', 'extension_dir = "ext"'
    $ini = $ini -replace ';\s*date.timezone\s*=.*', 'date.timezone = Asia/Bangkok'

    $extensions = @(
        'curl',
        'fileinfo',
        'mbstring',
        'openssl',
        'pdo_mysql',
        'pdo_sqlite',
        'sqlite3',
        'zip'
    )

    $unsupportedExtensions = @('dom', 'xml', 'xmlwriter')
    foreach ($extension in $unsupportedExtensions) {
        $pattern = "(?m)^\s*;?\s*extension\s*=\s*$([regex]::Escape($extension))\s*$"
        $ini = [regex]::Replace($ini, $pattern, "; extension=$extension")
    }

    foreach ($extension in $extensions) {
        $dllName = "php_$extension.dll"
        if (-not (Test-Path -LiteralPath (Join-Path $PhpDir "ext\$dllName"))) {
            continue
        }

        $pattern = "(?m)^\s*;?\s*extension\s*=\s*$([regex]::Escape($extension))\s*$"
        if ($ini -match $pattern) {
            $ini = [regex]::Replace($ini, $pattern, "extension=$extension")
        } else {
            $ini += "`r`nextension=$extension"
        }
    }

    Set-Content -LiteralPath $phpIni -Value $ini -Encoding ASCII

    $phpExe = Join-Path $PhpDir 'php.exe'
    if (-not (Test-Path -LiteralPath $phpExe)) {
        throw 'Tai PHP xong nhung khong tim thay php.exe.'
    }

    return $phpExe
}

function Install-PortablePhp {
    Ensure-Directory $ToolsDir
    if (Test-Path -LiteralPath $PhpDir) {
        Remove-Item -LiteralPath $PhpDir -Recurse -Force
    }
    Ensure-Directory $PhpDir

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw 'Khong tim thay winget de tu tai PHP. Cai PHP 8.1+ hoac cai winget.'
    }

    Write-Host 'Downloading portable PHP for Windows...'
    $wingetInfo = & $winget.Source show --id PHP.PHP.8.3 --exact
    if ($LASTEXITCODE -ne 0) {
        throw 'Khong lay duoc thong tin goi PHP tu winget.'
    }

    $installerUrl = ($wingetInfo | Select-String 'Installer Url:\s+(\S+)' | Select-Object -First 1).Matches.Groups[1].Value
    if (-not $installerUrl) {
        throw 'Khong tim thay duong dan tai PHP trong thong tin winget.'
    }

    $zipPath = Join-Path $ToolsDir 'php.zip'
    Invoke-WebRequest -Uri $installerUrl -OutFile $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $PhpDir -Force
    Remove-Item -LiteralPath $zipPath -Force

    return Configure-PortablePhpIni
}

function Ensure-Php {
    $phpCmd = Get-PhpCommand
    if ($phpCmd) {
        if ($phpCmd -eq (Join-Path $PhpDir 'php.exe')) {
            Configure-PortablePhpIni | Out-Null
        }
        return $phpCmd
    }

    $phpCmd = Install-PortablePhp
    & $phpCmd -v | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'PHP portable da duoc tai ve nhung khong chay duoc. Kiem tra Visual C++ Redistributable 2015-2022 x64.'
    }

    return $phpCmd
}

function Install-PortableComposer {
    param([string] $PhpCmd)

    Ensure-Directory $ComposerDir

    $installerPath = Join-Path $ComposerDir 'composer-setup.php'
    $checksumResponse = Invoke-WebRequest -Uri 'https://composer.github.io/installer.sig' -UseBasicParsing
    $expectedChecksum = if ($checksumResponse.Content -is [byte[]]) {
        [System.Text.Encoding]::UTF8.GetString($checksumResponse.Content).Trim()
    } else {
        ([string] $checksumResponse.Content).Trim()
    }
    Invoke-WebRequest -Uri 'https://getcomposer.org/installer' -OutFile $installerPath -UseBasicParsing

    try {
        $actualChecksum = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA384).Hash.ToLowerInvariant()
        if ($actualChecksum -ne $expectedChecksum.ToLowerInvariant()) {
            throw 'Composer installer checksum khong hop le.'
        }

        & $PhpCmd $installerPath --quiet --install-dir=$ComposerDir --filename=composer.phar
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ComposerPhar)) {
            throw 'Khong cai duoc Composer local.'
        }
    } finally {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        Executable = $PhpCmd
        Prefix = @($ComposerPhar)
    }
}

function Get-ComposerCommand {
    param([string] $PhpCmd)

    if (Test-Path -LiteralPath $ComposerPhar) {
        return [pscustomobject]@{
            Executable = $PhpCmd
            Prefix = @($ComposerPhar)
        }
    }

    $composer = Get-Command composer -ErrorAction SilentlyContinue
    if ($composer) {
        return [pscustomobject]@{
            Executable = $composer.Source
            Prefix = @()
        }
    }

    $composerBat = Get-Command composer.bat -ErrorAction SilentlyContinue
    if ($composerBat) {
        return [pscustomobject]@{
            Executable = $composerBat.Source
            Prefix = @()
        }
    }

    return Install-PortableComposer -PhpCmd $PhpCmd
}

function Invoke-Composer {
    param(
        [pscustomobject] $ComposerCmd,
        [string[]] $Arguments,
        [string] $WorkingDirectory
    )

    if ($WorkingDirectory) {
        Push-Location $WorkingDirectory
    }

    try {
        & $ComposerCmd.Executable @($ComposerCmd.Prefix + $Arguments)
        if ($LASTEXITCODE -ne 0) {
            throw "Composer command failed: $($Arguments -join ' ')"
        }
    } finally {
        if ($WorkingDirectory) {
            Pop-Location
        }
    }
}

function Test-PhpExtension {
    param(
        [string] $PhpCmd,
        [string] $Extension
    )

    $extensions = & $PhpCmd -m
    if ($LASTEXITCODE -ne 0) {
        throw 'Khong doc duoc danh sach PHP extensions.'
    }

    return @($extensions | Where-Object { $_ -eq $Extension }).Count -gt 0
}

function Check-RuntimeRequirements {
    param([string] $PhpCmd)

    switch ($DbConnection) {
        'sqlite' {
            if (-not (Test-PhpExtension -PhpCmd $PhpCmd -Extension 'pdo_sqlite') -or -not (Test-PhpExtension -PhpCmd $PhpCmd -Extension 'sqlite3')) {
                throw "SQLite mode can pdo_sqlite va sqlite3. PHP dang duoc dung: $PhpCmd"
            }
        }
        'mysql' {
            if (-not (Test-PhpExtension -PhpCmd $PhpCmd -Extension 'pdo_mysql')) {
                throw 'MySQL mode can PHP extension pdo_mysql.'
            }

            if (-not (Get-Command mysql -ErrorAction SilentlyContinue)) {
                throw 'MySQL mode can mysql client command.'
            }
        }
        default {
            throw "Unsupported PHONESHOP_DB_CONNECTION: $DbConnection"
        }
    }
}

function Stop-Existing {
    if (-not (Test-Path -LiteralPath $PidFile)) {
        return
    }

    $existingPid = (Get-Content -LiteralPath $PidFile -Raw).Trim()
    $stopScript = Join-Path $RootDir 'stop.ps1'
    if (Test-Path -LiteralPath $stopScript) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $stopScript *> $null
    }

    if ($existingPid) {
        for ($i = 0; $i -lt 20; $i++) {
            if (-not (Get-Process -Id ([int] $existingPid) -ErrorAction SilentlyContinue)) {
                break
            }
            Start-Sleep -Milliseconds 500
        }
    }
}

function Bootstrap-LaravelRuntime {
    param([string] $PhpCmd)

    $artisan = Join-Path $AppDir 'artisan'
    $autoload = Join-Path $AppDir 'vendor\autoload.php'
    if ((Test-Path -LiteralPath $artisan) -and (Test-Path -LiteralPath $autoload)) {
        return
    }

    $composerCmd = Get-ComposerCommand -PhpCmd $PhpCmd

    if (Test-Path -LiteralPath $AppDir) {
        Remove-Item -LiteralPath $AppDir -Recurse -Force
    }
    Ensure-Directory $AppDir

    Write-Host 'Bootstrapping Laravel runtime...'
    Invoke-Composer -ComposerCmd $composerCmd -WorkingDirectory $RootDir -Arguments @(
        'create-project',
        'laravel/laravel:^10.0',
        $AppDir,
        '--no-install',
        '--no-scripts',
        '--no-interaction',
        '--prefer-dist'
    )

    $composerJson = Join-Path $AppDir 'composer.json'
    $composerData = Get-Content -LiteralPath $composerJson -Raw | ConvertFrom-Json
    $composerData.PSObject.Properties.Remove('require-dev')
    $composerData.PSObject.Properties.Remove('autoload-dev')
    $composerJsonText = ($composerData | ConvertTo-Json -Depth 100) + "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($composerJson, $composerJsonText, $utf8NoBom)

    Invoke-Composer -ComposerCmd $composerCmd -WorkingDirectory $AppDir -Arguments @(
        'install',
        '--no-dev',
        '--no-interaction',
        '--prefer-dist',
        '--no-scripts',
        '--ignore-platform-req=ext-curl',
        '--ignore-platform-req=ext-dom',
        '--ignore-platform-req=ext-xml',
        '--ignore-platform-req=ext-xmlwriter'
    )
}

function Copy-DirectoryContents {
    param(
        [string] $Source,
        [string] $Destination
    )

    Ensure-Directory $Destination
    $items = @(Get-ChildItem -LiteralPath $Source -Force)
    if ($items.Count -eq 0) {
        return
    }

    Copy-Item -LiteralPath $items.FullName -Destination $Destination -Recurse -Force
}

function Sync-ProjectFiles {
    Write-Host 'Syncing project files...'

    $pathsToReset = @(
        (Join-Path $AppDir 'database\migrations'),
        (Join-Path $AppDir 'database\seeders'),
        (Join-Path $AppDir 'resources'),
        (Join-Path $AppDir 'config\app.php'),
        (Join-Path $AppDir 'public\css'),
        (Join-Path $AppDir 'storage\app\public\products')
    )

    foreach ($path in $pathsToReset) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }

    Ensure-Directory (Join-Path $AppDir 'database\migrations')
    Ensure-Directory (Join-Path $AppDir 'database\seeders')
    Ensure-Directory (Join-Path $AppDir 'config')
    Ensure-Directory (Join-Path $AppDir 'public\css')
    Ensure-Directory (Join-Path $AppDir 'storage\app\public\products')

    Copy-DirectoryContents -Source (Join-Path $RootDir 'app') -Destination (Join-Path $AppDir 'app')
    Copy-DirectoryContents -Source (Join-Path $RootDir 'database\migrations') -Destination (Join-Path $AppDir 'database\migrations')
    Copy-Item -LiteralPath (Join-Path $RootDir 'database\seeders\DatabaseSeeder.php') -Destination (Join-Path $AppDir 'database\seeders\DatabaseSeeder.php') -Force
    Copy-DirectoryContents -Source (Join-Path $RootDir 'resources') -Destination (Join-Path $AppDir 'resources')
    Copy-Item -LiteralPath (Join-Path $RootDir 'config\app.php') -Destination (Join-Path $AppDir 'config\app.php') -Force
    Copy-Item -LiteralPath (Join-Path $RootDir 'routes\web.php') -Destination (Join-Path $AppDir 'routes\web.php') -Force
    Copy-DirectoryContents -Source (Join-Path $RootDir 'public\css') -Destination (Join-Path $AppDir 'public\css')
    Copy-DirectoryContents -Source (Join-Path $RootDir 'storage\app\public\products') -Destination (Join-Path $AppDir 'storage\app\public\products')
}

function Set-OrAppendEnvValue {
    param(
        [string] $Contents,
        [string] $Key,
        [string] $Value
    )

    $escapedKey = [regex]::Escape($Key)
    $line = "$Key=$Value"
    $regex = [regex]::new("^$escapedKey=.*$", [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($regex.IsMatch($Contents)) {
        return $regex.Replace($Contents, $line, 1)
    }

    if ($Contents.Length -gt 0 -and -not $Contents.EndsWith("`r`n") -and -not $Contents.EndsWith("`n")) {
        $Contents += "`r`n"
    }

    return $Contents + $line + "`r`n"
}

function Ensure-EnvFile {
    $envFile = Join-Path $AppDir '.env'
    $sqliteDatabase = (Join-Path $AppDir 'database\database.sqlite').Replace('\', '/')
    if (-not (Test-Path -LiteralPath $envFile)) {
        Copy-Item -LiteralPath (Join-Path $AppDir '.env.example') -Destination $envFile -Force
    }

    $contents = Get-Content -LiteralPath $envFile -Raw
    $updates = [ordered]@{
        APP_NAME = 'PhoneShop'
        APP_ENV = 'local'
        APP_DEBUG = 'true'
        APP_URL = $AppUrl
        SESSION_DRIVER = 'file'
        SESSION_LIFETIME = '120'
        CACHE_DRIVER = 'file'
        QUEUE_CONNECTION = 'sync'
    }

    if ($DbConnection -eq 'mysql') {
        $updates['DB_CONNECTION'] = 'mysql'
        $updates['DB_HOST'] = $DbHost
        $updates['DB_PORT'] = $DbPort
        $updates['DB_DATABASE'] = $DbDatabase
        $updates['DB_USERNAME'] = $DbUsername
        $updates['DB_PASSWORD'] = $DbPassword
    } else {
        $updates['DB_CONNECTION'] = 'sqlite'
        $updates['DB_HOST'] = '127.0.0.1'
        $updates['DB_PORT'] = '3306'
        $updates['DB_DATABASE'] = $sqliteDatabase
        $updates['DB_USERNAME'] = 'root'
        $updates['DB_PASSWORD'] = ''
    }

    foreach ($entry in $updates.GetEnumerator()) {
        $contents = Set-OrAppendEnvValue -Contents $contents -Key $entry.Key -Value $entry.Value
    }

    Set-Content -LiteralPath $envFile -Value $contents -Encoding ASCII
}

function Prepare-App {
    param([string] $PhpCmd)

    Ensure-Directory (Join-Path $AppDir 'database')
    Ensure-Directory (Join-Path $AppDir 'storage')
    Ensure-Directory (Join-Path $AppDir 'bootstrap\cache')

    if ($DbConnection -eq 'sqlite') {
        $sqliteFile = Join-Path $AppDir 'database\database.sqlite'
        if (-not (Test-Path -LiteralPath $sqliteFile)) {
            New-Item -ItemType File -Path $sqliteFile -Force | Out-Null
        }
    } else {
        $mysqlArgs = @(
            '--protocol=TCP',
            "--host=$DbHost",
            "--port=$DbPort",
            "--user=$DbUsername",
            '-e',
            "CREATE DATABASE IF NOT EXISTS ``$DbDatabase`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        )
        if ($DbPassword) {
            $env:MYSQL_PWD = $DbPassword
        }
        & mysql @mysqlArgs | Out-Null
        Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
    }

    Patch-TermwindDomFallback

    $envFile = Join-Path $AppDir '.env'
    $envText = Get-Content -LiteralPath $envFile -Raw
    if ($envText -notmatch '(?m)^APP_KEY=base64:') {
        & $PhpCmd artisan key:generate --force --no-interaction | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Khong tao duoc APP_KEY.'
        }
    }

    & $PhpCmd artisan optimize:clear | Out-Null
    & $PhpCmd artisan package:discover --ansi | Out-Null
    & $PhpCmd artisan storage:link | Out-Null
    & $PhpCmd artisan migrate --force | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Khong chay duoc migrate.'
    }

    $seedFlag = Join-Path $AppDir '.phoneshop-seeded'
    if (-not (Test-Path -LiteralPath $seedFlag)) {
        & $PhpCmd artisan db:seed --force | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Khong chay duoc db:seed.'
        }
        Set-Content -LiteralPath $seedFlag -Value '' -Encoding ASCII
    }
}

function Patch-TermwindDomFallback {
    $renderer = Join-Path $AppDir 'vendor\nunomaduro\termwind\src\HtmlRenderer.php'
    if (-not (Test-Path -LiteralPath $renderer)) {
        return
    }

    $contents = Get-Content -LiteralPath $renderer -Raw
    if ($contents.Contains('class_exists(DOMDocument::class)')) {
        return
    }

    $needle = "        `$dom = new DOMDocument;`n"
    $replacement = @"
        if (! class_exists(DOMDocument::class)) {
            return Termwind::span(trim(strip_tags(`$html)));
        }

        `$dom = new DOMDocument;
"@
    $replacement = $replacement -replace "`r?`n", "`n"

    if ($contents.Contains($needle)) {
        $contents = $contents.Replace($needle, $replacement + "`n")
        Set-Content -LiteralPath $renderer -Value $contents -Encoding ASCII
    }
}

function Start-Server {
    param([string] $PhpCmd)

    Write-Host "Starting PhoneShop on $AppUrl ..."
    if (Test-Path -LiteralPath $LogFile) {
        try {
            Clear-Content -LiteralPath $LogFile -ErrorAction Stop
        } catch {
        }
    }
    if (Test-Path -LiteralPath $ErrorLogFile) {
        try {
            Clear-Content -LiteralPath $ErrorLogFile -ErrorAction Stop
        } catch {
        }
    }

    $process = Start-Process -FilePath $PhpCmd `
        -ArgumentList @('artisan', 'serve', "--host=$HostName", "--port=$Port") `
        -WorkingDirectory $AppDir `
        -RedirectStandardOutput $LogFile `
        -RedirectStandardError $ErrorLogFile `
        -PassThru

    Set-Content -LiteralPath $PidFile -Value $process.Id -Encoding ASCII
    Set-Content -LiteralPath $PortFile -Value $Port -Encoding ASCII

    Start-Sleep -Seconds 2
    if ($process.HasExited) {
        $logText = @()
        if (Test-Path -LiteralPath $LogFile) {
            $logText += Get-Content -LiteralPath $LogFile -Tail 50
        }
        if (Test-Path -LiteralPath $ErrorLogFile) {
            $logText += Get-Content -LiteralPath $ErrorLogFile -Tail 50
        }
        throw ("Failed to start server.`n" + ($logText -join [Environment]::NewLine))
    }

    Write-Host 'PhoneShop is running.'
    Write-Host "URL: $AppUrl"
    Write-Host "Log: $LogFile"
    if (Test-Path -LiteralPath $ErrorLogFile) {
        Write-Host "Error log: $ErrorLogFile"
    }
}

Ensure-Directory $RuntimeDir
$phpCmd = Ensure-Php
Check-RuntimeRequirements -PhpCmd $phpCmd
Stop-Existing
Bootstrap-LaravelRuntime -PhpCmd $phpCmd
Sync-ProjectFiles
Ensure-EnvFile
Push-Location $AppDir
try {
    Prepare-App -PhpCmd $phpCmd
    Start-Server -PhpCmd $phpCmd
} finally {
    Pop-Location
}
