@echo off
chcp 65001 >nul
set "SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath $env:SELF -Encoding UTF8 | Select-Object -Skip 5 | Out-String | Invoke-Expression"
exit /b
# ============================================================
#  解除 PCL 2.99.0.0 的「无法下载 Minecraft 本体」限制
#  仅修改本 bat 所在目录下的 Plain Craft Launcher 2.exe
#
#  原理：
#    PCL 用编译期常量 RestrictMcDownload = True 禁用了下载页的
#    版本列表。编译后 PageDownloadInstall.LoaderInit 中只剩下
#    「关闭下载」这个必然抛异常的任务。本脚本把该任务构造的 IL
#    替换为加载真正的 DlClientListLoader 字段，从而恢复下载页。
#
#  适用：Plain Craft Launcher 2.exe 正式版 2.99.0.0 (413)
#        其他版本会因校验不通过而拒绝修改。
# ============================================================
$ErrorActionPreference = 'Stop'

function Invoke-Unlock {
    $dir = Split-Path -Parent $env:SELF
    $exe = Join-Path $dir 'Plain Craft Launcher 2.exe'

    if (-not (Test-Path -LiteralPath $exe)) {
        Write-Host '未找到 Plain Craft Launcher 2.exe。' -ForegroundColor Red
        Write-Host '请把本 bat 放到启动器所在的文件夹（与 exe 同级）后再运行。'
        return
    }

    Write-Host ('目标文件：' + $exe)

    $procName = [IO.Path]::GetFileNameWithoutExtension($exe)
    $running = @(Get-Process -Name $procName -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -eq $exe } catch { $true }
    })
    if ($running.Count -gt 0) {
        Write-Host 'PCL 正在运行，请先完全退出启动器后再运行本脚本。' -ForegroundColor Red
        return
    }

    $bytes = [IO.File]::ReadAllBytes($exe)

    # PageDownloadInstall.LoaderInit 方法体在文件中的位置
    $offset = 0x2C0DA
    $tailEnd = 0x2C109

    $patched = [byte[]](0x7E, 0x0F, 0x04, 0x00, 0x04)   # ldsfld PCL.ModDownload.DlClientListLoader
    $expected = [byte[]](
        0x72, 0x33, 0x47, 0x01, 0x70,                     # ldstr "关闭下载"
        0x7E, 0xFB, 0x09, 0x00, 0x04,                     # ldsfld $IR3-3
        0x2C, 0x07,                                       # brfalse.s
        0x7E, 0xFB, 0x09, 0x00, 0x04,                     # ldsfld $IR3-3
        0x2B, 0x16,                                       # br.s
        0x7E, 0xF9, 0x09, 0x00, 0x04,                     # ldsfld $I
        0xFE, 0x06, 0x67, 0x14, 0x00, 0x06,               # ldftn _Lambda$__R3-3
        0x73, 0x8D, 0x05, 0x00, 0x0A,                     # newobj Func
        0x25,                                             # dup
        0x80, 0xFB, 0x09, 0x00, 0x04,                     # stsfld $IR3-3
        0x14,                                             # ldnull
        0x18,                                             # ldc.i4.2
        0x73, 0x8E, 0x05, 0x00, 0x0A                      # newobj LoaderTask
    )

    $already = $true
    for ($i = 0; $i -lt $patched.Length; $i++) {
        if ($bytes[$offset + $i] -ne $patched[$i]) { $already = $false; break }
    }
    if ($already) {
        Write-Host '当前文件已经是解除限制后的状态，无需重复处理。' -ForegroundColor Yellow
        return
    }

    if ($bytes.Length -le $tailEnd) {
        Write-Host '文件长度异常，已停止。' -ForegroundColor Red
        return
    }
    for ($i = 0; $i -lt $expected.Length; $i++) {
        if ($bytes[$offset + $i] -ne $expected[$i]) {
            Write-Host '当前 PCL 版本与脚本不匹配，未找到预期的限制代码。' -ForegroundColor Red
            Write-Host '本脚本仅适用于 Plain Craft Launcher 2.exe 2.99.0.0 (413)。'
            return
        }
    }

    $backup = $exe + '.bak'
    if (-not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $exe -Destination $backup
        Write-Host ('已备份原文件：' + $backup)
    }

    [Array]::Copy($patched, 0, $bytes, $offset, $patched.Length)
    for ($i = $offset + $patched.Length; $i -le $tailEnd; $i++) { $bytes[$i] = 0 }
    [IO.File]::WriteAllBytes($exe, $bytes)

    $check = [IO.File]::ReadAllBytes($exe)
    for ($i = 0; $i -lt $patched.Length; $i++) {
        if ($check[$offset + $i] -ne $patched[$i]) {
            Write-Host '写入后校验失败，请使用备份恢复。' -ForegroundColor Red
            return
        }
    }

    Write-Host ''
    Write-Host '完成：已解除「无法下载 Minecraft 本体」的限制。' -ForegroundColor Green
    Write-Host '打开 PCL → 下载 → 原版游戏，即可看到版本列表并安装游戏。'
    Write-Host ''
    Write-Host '说明：整合包安装等其他限制属于另一段被编译期删除的代码，本脚本无法恢复。'
    Write-Host '      若 PCL 以后自动更新，限制会重新出现，重新运行本脚本即可。'
    Write-Host ('      如需还原：删除当前 exe，再把 ' + $backup + ' 改回原名。')
}

try {
    Invoke-Unlock
} catch {
    Write-Host ''
    Write-Host ('处理失败：' + $_.Exception.Message) -ForegroundColor Red
}
Write-Host ''
Read-Host '按回车键退出'
