$baseUrl = "https://www.fe-siken.com/kakomon/02_menjo/q"
$outputDir = Join-Path $PSScriptRoot "pages"

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

Write-Host "下载 q1.html ~ q80.html 到 $outputDir ..." -ForegroundColor Cyan

for ($i = 1; $i -le 80; $i++) {
    $url = "$baseUrl$i.html"
    $file = Join-Path $outputDir "q$i.html"
    try {
        Invoke-WebRequest -Uri $url -OutFile $file -ErrorAction Stop
        Write-Host "  [$i/80] ✓ q$i.html" -ForegroundColor Green
    } catch {
        Write-Host "  [$i/80] ✗ q$i.html 失败: $_" -ForegroundColor Red
    }
    Start-Sleep -Milliseconds 200
}

Write-Host "全部下载完成！文件在: $outputDir" -ForegroundColor Cyan
Write-Host "然后修改 fe_siken_viewer_2020.html 中的:" -ForegroundColor Yellow
Write-Host "  const PROXY = '';" -ForegroundColor White
Write-Host "  const PROXY_LOCAL = './pages/';" -ForegroundColor White
