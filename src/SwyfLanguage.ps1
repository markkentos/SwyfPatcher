# UI language is local to the patcher; it does not change the game's language.
$script:Language = 'ru'
function T([string]$ru, [string]$en) {
    if ($script:Language -eq 'en') { return $en }
    return $ru
}
function Initialize-Language([string]$requested = '') {
    $language = if ([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ru') { 'ru' } else { 'en' }
    $path = Join-Path $PatcherRoot 'language.txt'
    if (Test-Path -LiteralPath $path) {
        try {
            $saved = [IO.File]::ReadAllText($path).Trim()
            if ($saved -in @('ru', 'en')) { $language = $saved }
        } catch { }
    }
    if ($requested) { $language = $requested }
    if ($language -notin @('ru', 'en')) { throw 'Language must be ru or en.' }
    $script:Language = $language
}
function Switch-Language {
    $next = if ($script:Language -eq 'ru') { 'en' } else { 'ru' }
    [IO.File]::WriteAllText((Join-Path $PatcherRoot 'language.txt'), $next)
    $script:Language = $next
}
function Show-MainMenu {
    Write-Host (T '  [1] Проверить текущее состояние' '  [1] Check current status')
    Write-Host (T '  [2] Применить / обновить патч' '  [2] Apply / update patch')
    Write-Host (T '  [3] Переключить на CPU' '  [3] Switch to CPU')
    Write-Host (T '  [4] Переключить на GPU (Vulkan)' '  [4] Switch to GPU (Vulkan)')
    Write-Host (T '  [5] Включить Q4' '  [5] Use Q4')
    Write-Host (T '  [6] Включить Q8' '  [6] Use Q8')
    Write-Host (T '  [7] Собрать логи в ZIP' '  [7] Collect logs as ZIP')
    Write-Host '  [8] Русский / English'
    Write-Host (T '  [0] Выход' '  [0] Exit')
}
