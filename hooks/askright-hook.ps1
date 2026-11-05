# askright: UserPromptSubmit hook, PowerShell version (Windows without Git Bash).
# Mirrors askright-hook.sh exactly; tests/hook-test.sh runs the same cases against both.
# ASCII only, so Windows PowerShell 5.1 reads this file correctly without a BOM.

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
try { [Console]::InputEncoding  = [System.Text.UTF8Encoding]::new($false) } catch {}

$raw = [Console]::In.ReadToEnd()

# ---- Settings ---------------------------------------------------------------
$cfgDir = $env:CLAUDE_CONFIG_DIR
if (-not $cfgDir) { $cfgDir = Join-Path $HOME '.claude' }
$conf = @{}
$cf = Join-Path $cfgDir 'askright.conf'
if (Test-Path -LiteralPath $cf) {
  foreach ($line in Get-Content -LiteralPath $cf) {
    if ($line -match '^([A-Za-z_]+)=(.*)$') { $conf[$Matches[1]] = ($Matches[2] -replace '\s', '') }
  }
}
$enabled = 'on'; if ($conf['enabled']) { $enabled = $conf['enabled'] }
if ($enabled -eq 'off') { exit 0 }
$threshold = '80'; if ($conf['threshold'] -match '^[0-9]+$') { $threshold = $conf['threshold'] }
$mode = 'full'; if ($conf['mode'] -eq 'quick') { $mode = 'quick' }

# ---- Input ------------------------------------------------------------------
try { $j = $raw | ConvertFrom-Json } catch { exit 0 }
$prompt = [string]$j.prompt
$cwd = [string]$j.cwd
if (-not $cwd -or -not (Test-Path -LiteralPath $cwd)) { $cwd = (Get-Location).Path }

$trimmed = ($prompt -replace '[\r\n\t]', ' ').Trim()
$lower = $trimmed.ToLowerInvariant()

# ---- Skip rules -------------------------------------------------------------
if (-not $trimmed) { exit 0 }
if ($trimmed.StartsWith('/')) { exit 0 }
if ($lower.StartsWith('raw:')) {
  Write-Output '[askright] Review skipped (raw: prefix). Ignore the prefix and do the request as written.'
  exit 0
}

$replyWords = @(
  'ok','okay','okk','okey','k','kk','alright','yes','yeah','yea','yep','yup','ya','y','no','nope','nah','n','sure','fine','cool','great','nice','perfect','good','awesome',
  'thanks','thank','thx','ty','you','please','pls','plz','go','ahead','on','do','it','that','this','them','those','these','all','both','same','then','now','just','and','so',
  'continue','proceed','next','done','stop','cancel','wait','hold','lgtm','looks','sounds','seems','approve','approved','ship','keep','going','carry',
  'try','again','retry','agreed','agree','right','correct','exactly','first','second','third','one','option','a','b','c','d',
  'apply','let','lets','s',
  'haan','han','ha','haa','theek','thik','hai','chalo','karo','kardo','kar','bas','accha','acha','achha','sahi','hmm','hm','mm'
)
$words = @(($lower -replace '[^a-z0-9]+', ' ').Trim() -split ' ' | Where-Object { $_ -ne '' })
$replyOnly = $true
foreach ($w in $words) {
  if (-not (($replyWords -contains $w) -or ($w -match '^[0-9]{1,2}$'))) { $replyOnly = $false; break }
}
if ($replyOnly -and $words.Count -le 8) { exit 0 }

# ---- Project context (cheap, read-only) -------------------------------------
$ctx = 'dir ' + (Split-Path -Leaf $cwd)
if (Get-Command git -ErrorAction SilentlyContinue) {
  $inside = (& git -C $cwd rev-parse --is-inside-work-tree 2>$null)
  if ($inside -eq 'true') {
    $ctx += ' | branch ' + (& git -C $cwd branch --show-current 2>$null)
    $changed = @(& git -C $cwd status --short 2>$null | Select-Object -First 10 | ForEach-Object { ($_.Trim() -split '\s+')[-1] })
    if ($changed.Count -gt 0) { $ctx += ' | changed: ' + ($changed -join ' ') + ' ' }
    $last = @(& git -C $cwd log -3 --pretty='%s' 2>$null)
    if ($last.Count -gt 0) { $ctx += ' | recent commits: ' + ($last -join ';') }
  }
}
$stack = @()
$pkg = Join-Path $cwd 'package.json'
if (Test-Path -LiteralPath $pkg) {
  $text = Get-Content -LiteralPath $pkg -Raw
  $found = [regex]::Matches($text, '"(next|react|vue|svelte|@angular/core|tailwindcss|vite|express|@nestjs/core|react-native|expo|electron|typescript)"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique -CaseSensitive
  $stack += @($found)
}
if ((Test-Path -LiteralPath (Join-Path $cwd 'pyproject.toml')) -or (Test-Path -LiteralPath (Join-Path $cwd 'requirements.txt'))) { $stack += 'python' }
if (Test-Path -LiteralPath (Join-Path $cwd 'go.mod'))       { $stack += 'go' }
if (Test-Path -LiteralPath (Join-Path $cwd 'Cargo.toml'))   { $stack += 'rust' }
if (Test-Path -LiteralPath (Join-Path $cwd 'pubspec.yaml')) { $stack += 'flutter' }
if ($stack.Count -gt 0) { $ctx += ' | stack: ' + ($stack -join ' ') }

if ($mode -eq 'quick') {
  $opts = '2 options: "Best match (NN%) (Recommended)" and "Use mine (NN%)"'
} else {
  $opts = '4 options in order: "Best match (NN%) (Recommended)", "Short (NN%)" (1-2 lines), "Detailed (NN%)" (goal, context, steps, constraints, done-criteria), "Use mine (NN%)"'
}
$check = [string][char]0x2713
$dot = [string][char]0x00B7

# ---- Compact instructions for Claude ----------------------------------------
Write-Output "[askright ON | threshold $threshold% | mode $mode] Review the user's prompt before starting work."
Write-Output "Context: $ctx"
Write-Output "- Skip entirely if the message is a reply (approving, declining or tweaking what you proposed, answering your question, picking an option)."
Write-Output "- Score 0-100 with this rubric, judging against conversation context: Goal 25, Target (file/page/component) 25, Context 20, Done-criteria 20, Constraints 10."
Write-Output "- Score >= ${threshold}: print one line `"Prompt score NN% $dot Goal $check Target $check ...`" and do the task as written. No picker."
Write-Output "- Score < ${threshold}: build rewrites from the conversation, the context line above, and at most 3 quick read-only lookups (Glob, Grep, a short file) so they name real files. Never invent facts; use [placeholders] for unknowns. Write in the user's language. Then call AskUserQuestion once: header `"Rewrite`", question `"Prompt score NN% $dot <rubric $check/x line> $dot <what's missing>. Which prompt should I run?`", $opts; each with a one-line description and the full prompt as preview. The user may add notes (apply them as edits) or pick Other (use their text)."
Write-Output "- Then ask once for any [placeholders] you can't fill, show the final prompt in a quote headed `"Running:`", and do it."
exit 0
