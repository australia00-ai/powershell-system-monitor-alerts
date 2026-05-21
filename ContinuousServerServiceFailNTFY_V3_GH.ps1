# ================= CONFIG =================
$FilePath        = "C:\temp\ping_timeouts.txt"
$MonitorPath     = "yourDirPath"
$NtfyUrl         = "https://ntfy.sh/yourUrl"
# log file (ping_timeouts.txt) content "2025-11-14 14:12:23 - Request timed out from serverName"
$LookbackMinutes = 5
$SleepSeconds    = 180

# file monitoring rules
$MinFiles        = 5
$AlertDuration   = 20   # minutes

# store history of low counts
$LowCountStartTime = $null

# ================= LOOP =================
while ($true) {

    $Now = Get-Date
    Write-Host "`n[$($Now.ToString('HH:mm:ss'))] Running checks..." -ForegroundColor Cyan

    # =====================================================
    # 🔹 FILE COUNT MONITOR
    # =====================================================
    if (Test-Path $MonitorPath) {

        try {
            $FileCount = (Get-ChildItem -Path $MonitorPath -File -ErrorAction Stop).Count

            Write-Host "Root File count: $FileCount" -ForegroundColor White

            if ($FileCount -lt $MinFiles) {

                if (-not $LowCountStartTime) {
                    $LowCountStartTime = $Now
                    Write-Host "Low file count detected (started tracking)" -ForegroundColor Yellow
                }
                else {
                    $Elapsed = ($Now - $LowCountStartTime).TotalMinutes

                    Write-Host ("Low count duration: {0:N1} min" -f $Elapsed) -ForegroundColor Yellow

                    if ($Elapsed -ge $AlertDuration) {

                        Write-Host "🚨 Threshold breached - sending alert" -ForegroundColor Red

                        $Msg = @"
						🚨 FILE BACKLOG ALERT

						Path:
						$MonitorPath

						File count: $FileCount
						Below threshold: $MinFiles

						Duration: $([math]::Round($Elapsed,1)) minutes
						"@

                        try {
                            Invoke-RestMethod -Uri $NtfyUrl -Method POST -Body $Msg -Headers @{
                                Title    = "📂 File Queue Alert"
                                Priority = "high"
                            } | Out-Null

                            Write-Host "Alert sent ✅" -ForegroundColor Green
                        }
                        catch {
                            Write-Host "Failed to send alert" -ForegroundColor Red
                        }

                        # reset so it doesn't spam
                        $LowCountStartTime = $Now
                    }
                }

            }
            else {
                # reset if recovered
                if ($LowCountStartTime) {
                    Write-Host "✅ File count recovered" -ForegroundColor Green
                }

                $LowCountStartTime = $null
            }

        }
        catch {
            Write-Host "Error reading folder" -ForegroundColor Red
        }

    }
    else {
        Write-Host "Monitor path not accessible!" -ForegroundColor Red
    }

    # =====================================================
    # 🔹 EXISTING TIMEOUT CHECK
    # =====================================================
    if (Test-Path $FilePath) {

        $Cutoff = $Now.AddMinutes(-$LookbackMinutes)
        $RecentEntries = @()

        Get-Content $FilePath | ForEach-Object {

            if ($_ -match "^(?<date>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) - (?<msg>.+)$") {
                try {
                    $logTime = [datetime]$matches["date"]

                    if ($logTime -ge $Cutoff) {
                        $RecentEntries += $_
                    }
                } catch {}
            }
        }

        if ($RecentEntries.Count -gt 0) {

            $Servers = $RecentEntries |
                ForEach-Object { ($_ -split "from ")[-1] } |
                Sort-Object -Unique

            $Message = @"
⚠️ TIMEOUT ALERT

Servers:
$($Servers -join "`n")

Events: $($RecentEntries.Count)
"@

            try {
                Invoke-RestMethod -Uri $NtfyUrl -Method POST -Body $Message -Headers @{
                    Title    = "🚨 Timeout Detected"
                    Priority = "high"
                } | Out-Null

                Write-Host "Timeout alert sent ✅" -ForegroundColor Green
            }
            catch {
                Write-Host "Timeout alert failed" -ForegroundColor Red
            }
        }
        else {
            Write-Host "No recent timeouts ✅"
        }
    }

    # =====================================================
    # 🔹 COUNTDOWN TIMER
    # =====================================================
    for ($i = $SleepSeconds; $i -gt 0; $i--) {

        $m = [int]($i / 60)
        $s = [int]($i % 60)

        $timeLeft = "{0}:{1}" -f $m.ToString("00"), $s.ToString("00")

        Write-Host -NoNewline "`rNext check in: $timeLeft  "
        Start-Sleep -Seconds 1
    }

    Write-Host ""
}