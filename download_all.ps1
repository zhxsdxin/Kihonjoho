param(
    [string]$Year = "02_menjo",
    [int]$Count = 80,
    [string]$OutputDir = "pages",
    [int]$DelayMs = 200
)

$baseUrl = "https://www.fe-siken.com/kakomon/$($Year)/q"
$outputPath = Join-Path $PSScriptRoot $OutputDir

New-Item -ItemType Directory -Force -Path $outputPath | Out-Null

Write-Host "下载 $Year q1.html ~ q$Count.html 到 $outputPath ..." -ForegroundColor Cyan

for ($i = 1; $i -le $Count; $i++) {
    $url = "$baseUrl$i.html"
    $file = Join-Path $outputPath "q$i.html"
    try {
        Invoke-WebRequest -Uri $url -OutFile $file -ErrorAction Stop
        Write-Host "  [$i/$Count] $file" -ForegroundColor Green
    } catch {
        Write-Host "  [$i/$Count] q$i.html 失败: $_" -ForegroundColor Red
    }
    if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
}

Write-Host "全部下载完成！" -ForegroundColor Cyan
Write-Host "然后在 HTML 中修改:" -ForegroundColor Yellow
Write-Host "  TOTAL = $Count" -ForegroundColor White
Write-Host "  BASE_URL = 'https://www.fe-siken.com/kakomon/$Year/q'" -ForegroundColor White
Write-Host "  LS_CACHE_PREFIX = 'fe$($Year -replace '_','')_'" -ForegroundColor White
