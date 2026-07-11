param(
    [string]$Year = "02_menjo",
    [int]$Count = 80,
    [string]$OutputDir = "pages",
    [string]$JsonName = "",
    [int]$DelayMs = 200,
    [switch]$Push,
    [switch]$Clean
)

$ErrorActionPreference = "Continue"
$baseUrl = "https://www.fe-siken.com/kakomon/$Year/q"
$pagesPath = Join-Path $PSScriptRoot $OutputDir

# 1. 下载所有题目网页
Write-Host "=== 下载 $Year q1~q$Count ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $pagesPath | Out-Null
for ($i = 1; $i -le $Count; $i++) {
    $url = "$baseUrl$i.html"
    $file = Join-Path $pagesPath "q$i.html"
    if (-not (Test-Path $file)) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $file -ErrorAction Stop
            Write-Host "  [$i/$Count] ✓" -ForegroundColor Green -NoNewline
        } catch {
            Write-Host "  [$i/$Count] ✗ $_" -ForegroundColor Red
        }
        if ($DelayMs -gt 0 -and $i -lt $Count) { Start-Sleep -Milliseconds $DelayMs }
    } else {
        Write-Host "  [$i/$Count] 跳过(已存在)" -ForegroundColor DarkGray
    }
}

# 2. 解析所有页面生成 JSON
Write-Host "`n=== 生成 JSON ===" -ForegroundColor Cyan
$chars = @('ア','イ','ウ','エ','オ','カ','キ','ク','ケ','コ')

$questions = [ordered]@{}
for ($i = 1; $i -le $Count; $i++) {
    $file = Join-Path $pagesPath "q$i.html"
    if (-not (Test-Path $file)) {
        Write-Host "  [$i/$Count] ✗ 文件不存在" -ForegroundColor Red
        continue
    }
    $html = Get-Content $file -Raw -Encoding UTF8

    # 提取 #mondai 内容
    if ($html -match '<div\s+id="mondai"[^>]*>(.*?)</div>\s*') {
        $mondai = $matches[1]
    } else { $mondai = "" }

    # 提取选项
    $selects = @()
    if ($html -match '<ul\s+class="selectList[^"]*"[^>]*>(.*?)</ul>') {
        $listHtml = $matches[1]
        # 分割每个 <li>
        $liMatches = [regex]::Matches($listHtml, '<li>(.*?)</li>')
        $idx = 0
        foreach ($liMatch in $liMatches) {
            $liContent = $liMatch.Groups[1].Value
            $isCorrect = $liContent -match 'id="t"'
            $text = $liContent -replace '<button[^>]*>.*?</button>', ''
            $selects += @{ label = if ($idx -lt $chars.Count) { $chars[$idx] } else { "" }; text = $text.Trim(); isCorrect = $isCorrect }
            $idx++
        }
    }

    # 提取正解
    $answer = if ($html -match '<span\s+id="answerChar"[^>]*>(.*?)</span>') { $matches[1].Trim() } else { "" }

    # 提取 #kaisetsu 内容
    $kaisetsu = if ($html -match '<div[^>]*\sid="kaisetsu"[^>]*>(.*?)</div>\s*<div\s+class="social-btn') { $matches[1] } else { "" }

    # 提取分类
    $info = ""
    if ($html -match '<h3>分類\s*:</h3>\s*<div>(.*?)</div>') {
        $info = "<strong>分類:</strong> $($matches[1])"
    }

    $questions["$i"] = @{
        mondai = $mondai
        selects = $selects
        answer = $answer
        kaisetsu = $kaisetsu
        info = $info
    }
    Write-Host "  [$i/$Count] ✓" -ForegroundColor Green -NoNewline
}
Write-Host "`n  已解析 $($questions.Count) 题" -ForegroundColor Green

$jsonData = @{
    version = 3
    type = "full"
    marks = @{}
    questions = $questions
}
if (-not $JsonName) { $JsonName = "fe_siken_viewer_$($Year -replace '_','')" }
$jsonName = ($JsonName -replace '\.json$', '') + '.json'
$jsonPath = Join-Path $PSScriptRoot $jsonName
Write-Host "  输出: $jsonName" -ForegroundColor Cyan
$jsonData | ConvertTo-Json -Depth 10 | Out-File $jsonPath -Encoding UTF8
Write-Host "  已写入 $jsonPath" -ForegroundColor Green

# 3. 删除题目网页
if ($Clean) {
    Write-Host "`n=== 删除 $OutputDir ===" -ForegroundColor Cyan
    Remove-Item -Path $pagesPath -Recurse -Force
    Write-Host "  已删除" -ForegroundColor Green
}

# 4. Git 推送
if ($Push) {
    # 查找 git
    $gitExe = Get-Command "git" -ErrorAction SilentlyContinue
    if (-not $gitExe) {
        $gitExe = Get-ChildItem -Filter "git.exe" -Path "C:\Program Files\Git\bin" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($gitExe) {
        $gitDir = if ($gitExe.Source) { Split-Path $gitExe.Source } else { Split-Path $gitExe.FullName }
        $env:PATH = "$gitDir;$env:PATH"
    }

    try {
        $status = git -C $PSScriptRoot status --porcelain 2>$null
        if ($status) {
            Write-Host "`n=== Git 推送 ===" -ForegroundColor Cyan
            git -C $PSScriptRoot add -A
            git -C $PSScriptRoot commit -m "generate $jsonName for $Year"
            git -C $PSScriptRoot push
            Write-Host "  推送完成" -ForegroundColor Green
        } else {
            Write-Host "`nGit: 无变更" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "`nGit 操作失败: $_" -ForegroundColor Red
    }
}

Write-Host "`n=== 完成 ===" -ForegroundColor Cyan
