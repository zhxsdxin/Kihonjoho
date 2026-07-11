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
if (-not $JsonName) { $JsonName = "fe_siken_viewer_$($Year -replace '_','')" }
$jsonName = ($JsonName -replace '\.json$', '') + '.json'
$suffix = $JsonName -replace '\.json$', ''
if (-not $OutputDir) { $OutputDir = $suffix }
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

function Fix-Url($text) {
    $text = [regex]::Replace($text, '(src|href)="(?!https?://)([^"]+)"', {
        param($m)
        $attr = $m.Groups[1].Value
        $url = $m.Groups[2].Value
        $prefix = if ($url.StartsWith('/')) { 'https://www.fe-siken.com' } else { "https://www.fe-siken.com/kakomon/$Year/" }
        return "$attr=`"$prefix$url`""
    })
    return $text
}

function ExtractContent($html, $openPattern) {
    $m = [regex]::Match($html, $openPattern)
    if (-not $m.Success) { return "" }
    $start = $m.Index + $m.Length + 1
    if ($start -le 0) { return "" }
    $depth = 1; $i = $start
    while ($depth -gt 0 -and $i -lt $html.Length) {
        $di = $html.IndexOf('</div>', $i)
        $oi = $html.IndexOf('<div ', $i)
        if ($oi -ge 0 -and $oi -lt $di) { $depth++; $i = $oi + 5 }
        elseif ($di -ge 0) { $depth--; $i = $di + 6 }
        else { break }
    }
    return $html.Substring($start, $i - $start - 6)
}

$questions = [ordered]@{}
for ($i = 1; $i -le $Count; $i++) {
    $file = Join-Path $pagesPath "q$i.html"
    if (-not (Test-Path $file)) {
        Write-Host "  [$i/$Count] ✗ 文件不存在" -ForegroundColor Red
        continue
    }
    $html = Get-Content $file -Raw -Encoding UTF8

    # 提取 #mondai 内容（ansbg 标记结束）
    $m = [regex]::Match($html, '<div\s+id="mondai"[^>]*>')
    if ($m.Success) {
        $ms = $m.Index + $m.Length
        $me = $html.IndexOf('<div class="ansbg"', $ms)
        if ($me -gt $ms) {
            $mondaiRaw = $html.Substring($ms, $me - $ms).Trim()
            $mondaiRaw = $mondaiRaw -replace '</div>\s*$', ''
            $mondai = Fix-Url $mondaiRaw
        } else { $mondai = "" }
    } else { $mondai = "" }

    # 提取选项
    $selects = @()
    $sm = [regex]::Match($html, '<ul\s+class="selectList[^"]*"[^>]*>(.*?)</ul>')
    if ($sm.Success) {
        $listHtml = $sm.Groups[1].Value
        $liMatches = [regex]::Matches($listHtml, '<li>(.*?)</li>')
        foreach ($liMatch in $liMatches) {
            $liContent = $liMatch.Groups[1].Value
            # 提取按钮
            $btns = [regex]::Matches($liContent, '<button[^>]*>(.*?)</button>')
            if ($btns.Count -gt 1) {
                # 多个按钮在同一个 <li>（如 Q12 图片选择题）
                $pre = $liContent -replace '(<button[^>]*>.*?</button>\s*)+', ''
                $pre = Fix-Url $pre.Trim()
                foreach ($btn in $btns) {
                    $btnText = $btn.Groups[1].Value.Trim()
                    $btnFull = $btn.Groups[0].Value
                    $isCorrect = $btnFull -match 'id="t"'
                    $selects += @{ label = $btnText; text = $pre.Trim(); isCorrect = $isCorrect }
                }
            } else {
                $isCorrect = $liContent -match 'id="t"'
                $text = $liContent -replace '<button[^>]*>.*?</button>', ''
                $text = Fix-Url $text.Trim()
                $idx = $selects.Count
                $selects += @{ label = if ($idx -lt $chars.Count) { $chars[$idx] } else { "" }; text = $text; isCorrect = $isCorrect }
            }
        }
    }

    # 提取正解
    $am = [regex]::Match($html, '<span\s+id="answerChar"[^>]*>(.*?)</span>')
    $answer = if ($am.Success) { $am.Groups[1].Value.Trim() } else { "" }

    # 提取 #kaisetsu 内容（social-btn 标记结束）
    $km = [regex]::Match($html, '<div[^>]*\sid="kaisetsu"[^>]*>')
    if ($km.Success) {
        $ks = $km.Index + $km.Length
        $ke = $html.IndexOf('social-btn', $ks)
        if ($ke -gt $ks) {
            $ke = $html.LastIndexOf('</div>', $ke)
            $kaisetsu = Fix-Url $html.Substring($ks, $ke - $ks).Trim()
        } else { $kaisetsu = "" }
    } else { $kaisetsu = "" }

    # 提取分类
    $info = ""
    if ($html -match '<h3>分類\s*:</h3>\s*<div>(.*?)</div>') {
        $info = Fix-Url "<strong>分類:</strong> $($matches[1])"
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
