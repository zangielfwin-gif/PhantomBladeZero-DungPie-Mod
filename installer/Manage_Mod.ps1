param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Install', 'Uninstall')]
    [string]$Action,
    [string]$GamePath,
    [string]$BackupRoot = (Join-Path $env:LOCALAPPDATA 'PBZThrowModInstaller\Backups')
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$steam = 'platform\steam'
$loader = "$steam\ue4ss"
$mods = "$loader\Mods"
$paks = 'ProjectPBZ\Content\Paks\~mods'
$receipt = "$steam\.PBZThrowTest-installer.json"
$modsTxt = "$mods\mods.txt"
$modsJson = "$mods\mods.json"
$modFiles = @("$mods\PBZThrowTest\Scripts\main.lua", "$mods\PBZThrowTest\Scripts\PBZThrowAudio.dll")
$oldFiles = @()
foreach ($ext in 'pak', 'ucas', 'utoc') {
    $modFiles += "$paks\PBZThrowTest_P.$ext", "$paks\PBZThrowPropsSafe_P.$ext",
        "$paks\PointDownNative_LocalTest_P.$ext", "$paks\PBZActionMenu_P.$ext"
    $oldFiles += "$paks\PBZThrowProps_P.$ext"
}
$loaderFiles = @(
    "$steam\dwmapi.dll", "$loader\UE4SS.dll", "$loader\UE4SS-settings.ini",
    "$loader\MemberVariableLayout.ini", "$loader\LICENSE",
    "$loader\UE4SS_Signatures\GNatives.lua", "$loader\UE4SS_Signatures\GUObjectArray.lua",
    "$mods\shared\UEHelpers\UEHelpers.lua"
)
$plan = New-Object 'System.Collections.Generic.List[object]'

function Find-PBZ([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    $resolved = (Get-Item -LiteralPath $Path).FullName
    if ((Test-Path -LiteralPath (Join-Path $resolved 'platform\steam\PBZ.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $resolved 'ProjectPBZ\Content\Paks') -PathType Container)) {
        return $resolved
    }
}

function Select-PBZ {
    if ($GamePath) {
        $result = Find-PBZ $GamePath.Trim().Trim('"')
        if (-not $result) { throw "这不是《影之刃零》根目录：$GamePath" }
        return $result
    }

    $steamRoots = @()
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        if (Test-Path -LiteralPath $key) {
            $value = Get-ItemProperty -LiteralPath $key
            $steamRoots += @($value.SteamPath, $value.InstallPath) | Where-Object { $_ }
        }
    }
    $libraries = @($steamRoots)
    foreach ($root in $steamRoots | Select-Object -Unique) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf -PathType Leaf) {
            foreach ($match in [regex]::Matches([IO.File]::ReadAllText($vdf), '(?im)^\s*"path"\s+"([^"]+)"')) {
                $libraries += $match.Groups[1].Value.Replace('\\', '\')
            }
        }
    }
    $candidates = @(Find-PBZ $PSScriptRoot)
    foreach ($library in $libraries | Select-Object -Unique) {
        if (-not (Test-Path -LiteralPath $library -PathType Container)) { continue }
        $folder = 'PBZ'
        $manifest = Join-Path $library 'steamapps\appmanifest_4115450.acf'
        if (Test-Path -LiteralPath $manifest -PathType Leaf) {
            $match = [regex]::Match([IO.File]::ReadAllText($manifest), '(?im)^\s*"installdir"\s+"([^"]+)"')
            if ($match.Success -and $match.Groups[1].Value -notmatch '[/\\:]') { $folder = $match.Groups[1].Value }
        }
        $candidates += @(Find-PBZ (Join-Path $library "steamapps\common\$folder"))
    }
    $candidates = @($candidates | Select-Object -Unique)
    if ($candidates.Count -eq 1) { return $candidates[0] }
    if ($candidates.Count -gt 1) {
        Write-Host '找到多个游戏目录，请选择。'
        for ($i = 0; $i -lt $candidates.Count; $i++) { Write-Host ('{0}. {1}' -f ($i + 1), $candidates[$i]) }
        $choice = 0
        if ([int]::TryParse((Read-Host '输入编号'), [ref]$choice) -and $choice -ge 1 -and $choice -le $candidates.Count) {
            return $candidates[$choice - 1]
        }
        throw '未选择有效的游戏目录。'
    }
    $manual = (Read-Host '未自动找到游戏。请粘贴 Steam 的 PBZ 游戏根目录').Trim().Trim('"')
    $result = Find-PBZ $manual
    if (-not $result) { throw '游戏目录无效。请通过 Steam「已安装文件」里的「浏览」找到正确目录。' }
    return $result
}

function Game-File([string]$Relative) {
    return Join-Path $gameRoot $Relative
}

function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '')
    } finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

function Add-Copy([string]$Relative, [string]$Source) {
    $target = Game-File $Relative
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "安装包不完整：$Source" }
    if (Test-Path -LiteralPath $target -PathType Container) { throw "目标文件名被目录占用：$target" }
    $digest = Get-Sha256 $Source
    if ((Test-Path -LiteralPath $target -PathType Leaf) -and
        (Get-Sha256 $target) -eq $digest) { return }
    $plan.Add([pscustomobject]@{ Kind = 'Copy'; Path = $Relative; Source = $Source; Hash = $digest })
}

function Add-Text([string]$Relative, [string]$Text) {
    $target = Game-File $Relative
    if (Test-Path -LiteralPath $target -PathType Container) { throw "目标文件名被目录占用：$target" }
    if ((Test-Path -LiteralPath $target -PathType Leaf) -and [IO.File]::ReadAllText($target) -ceq $Text) { return }
    $plan.Add([pscustomobject]@{ Kind = 'Text'; Path = $Relative; Text = $Text })
}

function Add-Remove([string]$Relative) {
    if (Test-Path -LiteralPath (Game-File $Relative) -PathType Leaf) {
        $plan.Add([pscustomobject]@{ Kind = 'Remove'; Path = $Relative })
    }
}

function Read-ModList([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $content = [IO.File]::ReadAllText($Path).Trim()
    if (-not $content.StartsWith('[') -or -not $content.EndsWith(']')) {
        throw "现有 mods.json 不是有效的列表，脚本不会覆盖它：$Path"
    }
    $entries = ConvertFrom-Json -InputObject $content
    foreach ($entry in $entries) {
        if ($null -eq $entry) { continue }
        if ($entry -isnot [pscustomobject] -or -not $entry.mod_name) {
            throw "现有 mods.json 包含无法识别的条目：$Path"
        }
        $entry
    }
}

function Update-ModList([bool]$Enable, [bool]$RemoveLoader) {
    if ($RemoveLoader) {
        Add-Remove $modsTxt
        Add-Remove $modsJson
        return
    }
    $txtPath = Game-File $modsTxt
    $jsonPath = Game-File $modsJson
    if ((Test-Path -LiteralPath $txtPath -PathType Leaf) -or $Enable) {
        $before = if (Test-Path -LiteralPath $txtPath -PathType Leaf) { [IO.File]::ReadAllText($txtPath, $strictUtf8) } else { '' }
        $after = [regex]::Replace($before, '(?im)^[ \t]*PBZThrowTest[ \t]*:[^\r\n]*(?:\r?\n|$)', '')
        if ($Enable) {
            if ($after.Length -gt 0 -and -not $after.EndsWith("`n")) { $after += "`r`n" }
            $after += "PBZThrowTest : 1`r`n"
        }
        if ($after -cne $before) { Add-Text $modsTxt $after }
    }
    if ((Test-Path -LiteralPath $jsonPath -PathType Leaf) -or $Enable) {
        $entries = @(Read-ModList $jsonPath)
        $other = @($entries | Where-Object { $_.mod_name -ne 'PBZThrowTest' })
        if ($Enable) {
            $other += [pscustomobject]@{ mod_name = 'PBZThrowTest'; mod_enabled = $true }
        }
        if ($Enable -or $other.Count -ne $entries.Count) {
            Add-Text $modsJson ((ConvertTo-Json -InputObject $other -Depth 32) + "`r`n")
        }
    }
}

function Test-OwnLoader {
    $marker = Game-File $receipt
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) { return $false }
    $saved = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($marker))
    if ($saved.version -ne 1 -or -not $saved.loader) { return $false }
    foreach ($relative in $loaderFiles) {
        $path = Game-File $relative
        $digest = $saved.loader.PSObject.Properties[$relative]
        if (-not $digest -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-Sha256 $path) -ne $digest.Value) { return $false }
    }
    $extraMods = Get-ChildItem -LiteralPath (Game-File $mods) -Directory -Force |
        Where-Object { $_.Name -notin 'PBZThrowTest', 'shared' }
    if ($extraMods) { return $false }
    $allowedFiles = @($modFiles) + @($loaderFiles) + @($modsTxt, $modsJson)
    $extraFiles = Get-ChildItem -LiteralPath (Game-File $mods) -File -Recurse -Force |
        Where-Object { $_.FullName.Substring($gameRoot.TrimEnd('\').Length + 1) -notin $allowedFiles }
    if ($extraFiles) { return $false }
    $txtPath = Game-File $modsTxt
    if ((Test-Path -LiteralPath $txtPath -PathType Leaf) -and
        [IO.File]::ReadAllText($txtPath) -match '(?im)^[ \t]*(?!PBZThrowTest[ \t]*:)[\w.-]+[ \t]*:') { return $false }
    if (Read-ModList (Game-File $modsJson) | Where-Object { $_.mod_name -ne 'PBZThrowTest' }) { return $false }
    return $true
}

function Require-ClosedGame {
    if (Get-Process -Name PBZ -ErrorAction SilentlyContinue) {
        throw '游戏仍在运行。请完全退出游戏，然后重新双击脚本。'
    }
}

function Invoke-FilePlan {
    if ($plan.Count -eq 0) { return }
    Require-ClosedGame
    $tag = '{0}-{1}-{2}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Action, ([guid]::NewGuid().ToString('N').Substring(0, 6))
    $backup = Join-Path $BackupRoot $tag
    $savedFiles = @{}
    foreach ($op in $plan) {
        $path = Game-File $op.Path
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $copy = Join-Path $backup $op.Path
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $copy))
            Copy-Item -LiteralPath $path -Destination $copy
            $savedFiles[$op.Path] = $copy
        }
    }
    if ($savedFiles.Count -gt 0) { Write-Host "备份位置：$backup" }
    Require-ClosedGame
    $applied = New-Object 'System.Collections.Generic.List[string]'
    try {
        foreach ($op in $plan) {
            $path = Game-File $op.Path
            $applied.Add($op.Path)
            if ($op.Kind -eq 'Remove') {
                Remove-Item -LiteralPath $path
                continue
            }
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
            if ($op.Kind -eq 'Copy') {
                Copy-Item -LiteralPath $op.Source -Destination $path -Force
                if ((Get-Sha256 $path) -ne $op.Hash) {
                    throw "复制校验失败：$path"
                }
            } else {
                [IO.File]::WriteAllText($path, $op.Text, $utf8)
            }
        }
    } catch {
        Write-Host '操作中断，正在恢复已改动的文件。'
        foreach ($relative in $applied) {
            try {
                $path = Game-File $relative
                if ($savedFiles.ContainsKey($relative)) {
                    Copy-Item -LiteralPath $savedFiles[$relative] -Destination $path -Force
                } elseif (Test-Path -LiteralPath $path -PathType Leaf) {
                    Remove-Item -LiteralPath $path
                }
            } catch {
                Write-Host "自动恢复失败：$relative。请查看上方备份目录。"
            }
        }
        throw
    }
}

$installerLock = [Threading.Mutex]::new($false, 'Local\PBZThrowTestInstaller')
$ownsLock = $false
try {
    try { $ownsLock = $installerLock.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsLock = $true }
    if (-not $ownsLock) { throw '另一个 Mod 安装或卸载窗口正在操作，请等它结束。' }
    Require-ClosedGame
    $gameRoot = Select-PBZ
    Write-Host "游戏目录：$gameRoot"
    if ($Action -eq 'Install') {
        if (Test-Path -LiteralPath (Game-File "$mods\PointDown\Scripts\main.lua") -PathType Leaf) {
            throw '检测到独立下指 Mod。请先卸载独立版，再安装动作菜单整合版。'
        }
        $dll = Game-File "$loader\UE4SS.dll"
        if (Test-Path -LiteralPath $dll -PathType Leaf) {
            $image = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($dll))
            if (-not $image.Contains('LoopInGameThreadAfterFrames')) {
                throw '已有的 UE4SS 不支持此版 Mod。请先查看说明中的 UE4SS 要求。'
            }
            $settings = Game-File "$loader\UE4SS-settings.ini"
            if ((Test-Path -LiteralPath $settings -PathType Leaf) -and
                [IO.File]::ReadAllText($settings) -match '(?im)^\s*HookEngineTick\s*=\s*(?:0|false)\b') {
                throw '已有 UE4SS 关闭了 EngineTick。请备份配置后将 HookEngineTick 设为 1，再重新安装。'
            }
            Write-Host '使用已有的兼容 UE4SS。'
        } else {
            $hashes = [ordered]@{}
            foreach ($relative in $loaderFiles) {
                $source = Join-Path $PSScriptRoot "UE4SS_FirstInstall\$relative"
                if (Test-Path -LiteralPath (Game-File $relative)) { throw "检测到已有的加载器文件，请先备份并确认用途：$relative" }
                Add-Copy $relative $source
                $hashes[$relative] = Get-Sha256 $source
            }
            Add-Text $receipt (ConvertTo-Json -InputObject @{ version = 1; loader = $hashes } -Depth 4)
        }
        foreach ($relative in $modFiles) {
            Add-Copy $relative (Join-Path $PSScriptRoot "Mod\$relative")
        }
        foreach ($relative in $oldFiles) { Add-Remove $relative }
        Update-ModList $true $false
        Invoke-FilePlan
        Write-Host '安装完成。可以从 Steam 启动游戏。' -ForegroundColor Green
    } else {
        $removeLoader = Test-OwnLoader
        foreach ($relative in @($modFiles) + @($oldFiles)) { Add-Remove $relative }
        Update-ModList $false $removeLoader
        if ($removeLoader) {
            foreach ($relative in $loaderFiles) { Add-Remove $relative }
        }
        Add-Remove $receipt
        Invoke-FilePlan
        Write-Host 'Mod 已卸载。' -ForegroundColor Green
        if ($removeLoader) {
            Write-Host '此安装器添加的 UE4SS 文件也已移除。'
        } else {
            Write-Host '保留已有或可能由其他 Mod 使用的 UE4SS。'
        }
    }
    exit 0
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
} finally {
    if ($ownsLock) { $installerLock.ReleaseMutex() }
    $installerLock.Dispose()
}
