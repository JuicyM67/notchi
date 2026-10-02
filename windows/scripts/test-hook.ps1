# Testar hooken på riktigt Windows (körs i GitHub Actions efter bygget):
#  1. Appen kör inte  → hooken avslutar tyst, utan utdata (Claude Code frågar som vanligt)
#  2. Godkännande     → hooken skickar händelsen med rätt nyckel och skriver tillbaka "allow"
#  3. Statusraden     → skriver en rad även när appen inte kör
param([string]$Exe = "src-tauri/target/release/tamanotchi.exe")
$ErrorActionPreference = "Stop"
$Exe = (Resolve-Path $Exe).Path
$dir = Join-Path $env:USERPROFILE ".tamanotchi"
New-Item -ItemType Directory -Force $dir | Out-Null
$tmp = New-Item -ItemType Directory -Force (Join-Path $env:RUNNER_TEMP "hooktest")

function Run-Hook([string]$json, [string[]]$hookArgs, [int]$timeoutSec = 30) {
  $in = Join-Path $tmp "in.json"; $out = Join-Path $tmp "out.txt"
  [IO.File]::WriteAllText($in, $json, [Text.UTF8Encoding]::new($false))
  $p = Start-Process -FilePath $Exe -ArgumentList $hookArgs -RedirectStandardInput $in -RedirectStandardOutput $out -NoNewWindow -PassThru
  if (-not $p.WaitForExit($timeoutSec * 1000)) { $p.Kill(); throw "hooken hängde sig" }
  return (Get-Content $out -Raw)
}

# 1
Remove-Item (Join-Path $dir "server.json") -ErrorAction SilentlyContinue
$sw = [Diagnostics.Stopwatch]::StartNew()
$r = Run-Hook '{"hook_event_name":"PreToolUse","session_id":"x"}' @("--hook")
if ($r) { throw "1: oväntad utdata: $r" }
"1 ok: tyst när appen inte kör ($($sw.ElapsedMilliseconds) ms)"

# 2
$l = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $l.Start()
$port = $l.LocalEndpoint.Port
[IO.File]::WriteAllText((Join-Path $dir "server.json"), "{`"port`":$port,`"token`":`"abc123`"}")
$in = Join-Path $tmp "perm.json"; $out = Join-Path $tmp "perm.txt"
[IO.File]::WriteAllText($in, '{"hook_event_name":"PermissionRequest","session_id":"x","cwd":"C:\\proj\\kundportal","tool_name":"Bash","tool_input":{"command":"npm test"}}', [Text.UTF8Encoding]::new($false))
$p = Start-Process -FilePath $Exe -ArgumentList "--hook" -RedirectStandardInput $in -RedirectStandardOutput $out -NoNewWindow -PassThru
$deadline = (Get-Date).AddSeconds(20)
while (-not $l.Pending()) { if ((Get-Date) -gt $deadline) { throw "2: hooken kopplade aldrig upp" }; Start-Sleep -Milliseconds 50 }
$c = $l.AcceptTcpClient(); $s = $c.GetStream()
$line = [IO.StreamReader]::new($s).ReadLine()
if ($line -notmatch '"tamanotchi_token":"abc123"') { throw "2: fel eller saknad nyckel: $line" }
if ($line -notmatch '"hook_event_name":"PermissionRequest"') { throw "2: fel händelse: $line" }
$w = [IO.StreamWriter]::new($s); $w.WriteLine('{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'); $w.Flush()
$c.Close(); $l.Stop()
if (-not $p.WaitForExit(20000)) { $p.Kill(); throw "2: hooken avslutades inte" }
$r = Get-Content $out -Raw
if ($r -notmatch '"behavior":"allow"') { throw "2: hooken skrev: $r" }
"2 ok: godkännande gick fram och tillbaka"

# 3
$r = Run-Hook '{"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":42}}}' @("--hook", "--statusline")
if ($r -notmatch "Opus") { throw "3: statusraden blev: $r" }
"3 ok: statusrad: $($r.Trim())"
Remove-Item (Join-Path $dir "server.json") -ErrorAction SilentlyContinue
