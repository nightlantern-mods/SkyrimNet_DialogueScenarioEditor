# Builds the release archive: a FOMOD installer (Mod Organizer 2, Vortex) that installs the mod in
# one language. Each language folder holds the whole mod under the same file names; the installer
# copies one of them into Data:
#
#   core/en/   English: MCM texts (English under all ten game-language names), settings page,
#              line wording (Common JSON) and example scenario in English
#   core/ja/   Japanese: the same in Japanese
#   fomod/     the installer (ModuleConfig.xml, info.xml)
#
# Reads the mod project's assets/ (Japanese page, Common JSON and example; scripts, prompts, MCM
# config, the DLL copied there by dll\build.ps1) and build/ (the ESP), the English files in
# release\lang\en (the page is made fresh from the Japanese one by make_en_page.py), the MCM texts
# in release\lang\<code>\Interface (make_strings.py), the docs in release\docs and the DLL source.
# Writes release\dist\SkyrimNet_DialogueScenarioEditor_<version>.zip and refuses to overwrite one.
# Then reads the archive back as an installer would and checks every choice.
#
# usage: release\tools\build_fomod.ps1 [-Version 0.1.0]
param(
    [string]$Version,
    [string]$Project = 'C:\Modding\skyrim-modding-tools-mcp\projects\SkyrimNet_DialogueScenarioEditor',
    [string]$Dll = 'C:\Modding\SkyrimNet_EventTrigger\dll',
    [string]$Validator = 'C:\Modding\SkyrimNet\1.0.0-rc1\devkit\tools\content-validate.exe',
    [string]$BaseTree = 'C:\Modding\SkyrimNet\1.0.0-rc1\GamePlugin\plugins\skyrimnet\base'
)
$ErrorActionPreference = 'Stop'
$env:PYTHONIOENCODING = 'utf-8'
$release = Split-Path $PSScriptRoot -Parent
$name = 'SkyrimNet_DialogueScenarioEditor'
$assets = "$Project\assets"
$esp = "$Project\build\$name.esp"
$bundle = "SKSE\Plugins\SkyrimNet\external\nightlantern-mods.dialogue-scenario-editor"
if (-not $Version) {
    $Version = (Select-String -Path "$Dll\xmake.lua" -Pattern 'PLUGIN_VERSION = "([^"]+)"').Matches[0].Groups[1].Value
}
$stage = "$release\dist\fomod"
$zip = "$release\dist\${name}_$Version.zip"
$gameLanguages = 'CHINESE', 'CZECH', 'ENGLISH', 'FRENCH', 'GERMAN', 'ITALIAN', 'JAPANESE', 'POLISH', 'RUSSIAN', 'SPANISH'
$languages = @(
    @{ code = 'en'; name = 'English'; desc = 'The settings menu, the settings page and the example scenario in English. Works with any game language.'; recommended = $true },
    @{ code = 'ja'; name = '日本語 (Japanese)'; desc = '設定メニュー、設定画面、サンプルのシナリオを日本語にします。ゲーム本体の言語は問いません。 The settings menu, page and example in Japanese.' }
)
$problems = New-Object System.Collections.Generic.List[string]
function Problem($text) { $problems.Add($text); Write-Host "PROBLEM: $text" -ForegroundColor Red }

# ---- before anything: the version, the inputs, the prompts ----
if (Test-Path $zip) { throw "$zip exists already: a changed build needs a new version (old archives are never overwritten)" }
$manifest = Get-Content "$assets\$bundle\manifest.json" -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.version -ne $Version) { throw "manifest.json version $($manifest.version) is not $Version" }
if (-not (Select-String -Path "$assets\$bundle\settings\DialogueScenarioEditor.yaml" -Pattern "version: `"$([regex]::Escape($Version))`"" -Quiet)) { throw "DialogueScenarioEditor.yaml plugin version is not $Version" }
foreach ($f in $esp, "$assets\SKSE\Plugins\$name.dll", "$release\docs\README.md", "$release\docs\README_ja.md", "$release\docs\COPYING.txt", "$release\docs\THIRD_PARTY_NOTICES.txt", "$release\docs\SOURCE_README.txt") {
    if (-not (Test-Path $f)) { throw "missing: $f" }
}
# the DLL in assets must be the one built from the current source
$built = "$Dll\build\windows\x64\release\$name.dll"
if ((Get-FileHash $built).Hash -ne (Get-FileHash "$assets\SKSE\Plugins\$name.dll").Hash) { throw "assets DLL differs from ${built}: run dll\build.ps1 first" }
function Invoke-Tool([scriptblock]$Run) {
    # the tools write their summary to stderr: judge them by the exit code, not by that
    $before = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & $Run 2>&1 | Out-Null; $LASTEXITCODE } finally { $ErrorActionPreference = $before }
}
Invoke-Tool { & $Validator "$assets\$bundle" --base-tree $BaseTree --report "$env:TEMP\dse_release_validate.json" } | Out-Null
$report = Get-Content "$env:TEMP\dse_release_validate.json" -Raw | ConvertFrom-Json
if (-not $report.ok -or $report.errors.Count) { throw "prompts do not validate: $($report.errors | ConvertTo-Json -Compress)" }

# ---- the English page, made fresh from the Japanese one ----
$enPage = "$release\lang\en\Magelight\$name\views\index.html"
python -I "$PSScriptRoot\make_en_page.py" "$assets\Magelight\$name\views\index.html" $enPage
if ($LASTEXITCODE -ne 0) { throw 'make_en_page.py failed' }
New-Item -ItemType Directory -Force "$release\lang\en\PrismaUI\views\$name" | Out-Null
Copy-Item $enPage "$release\lang\en\PrismaUI\views\$name\index.html" -Force
foreach ($code in 'en', 'ja') {
    python -I "$PSScriptRoot\make_strings.py" $code "$release\lang\$code\Interface\Translations" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'make_strings.py failed' }
}

# ---- one complete mod per language ----
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory "$stage\fomod" | Out-Null
foreach ($l in $languages) {
    $dir = "$stage\core\$($l.code)"
    New-Item -ItemType Directory $dir | Out-Null
    Copy-Item "$assets\*" $dir -Recurse
    Copy-Item $esp $dir
    foreach ($doc in 'README.md', 'README_ja.md', 'COPYING.txt', 'THIRD_PARTY_NOTICES.txt') { Copy-Item "$release\docs\$doc" $dir }
    New-Item -ItemType Directory "$dir\Source\Scripts" | Out-Null
    Copy-Item "$Project\src\*.psc" "$dir\Source\Scripts"
    $src = "$dir\Source\SKSE\$name"
    New-Item -ItemType Directory $src | Out-Null
    Copy-Item "$Dll\src" $src -Recurse
    Copy-Item "$Dll\xmake.lua" $src
    Copy-Item "$release\docs\SOURCE_README.txt" "$src\README.txt"
    Copy-Item "$release\lang\$($l.code)\*" $dir -Recurse -Force
}

# ---- the installer (no BOM, double-quoted declaration: Vortex) ----
$utf8 = New-Object System.Text.UTF8Encoding($false)
$esc = { param($s) [System.Security.SecurityElement]::Escape($s) }
$info = @"
<?xml version="1.0" encoding="UTF-8"?>
<fomod>
  <Name>$name</Name>
  <Author>nightlantern-mods</Author>
  <Version>$Version</Version>
  <Description>Adult content. A SkyrimNet add-on: write scenarios that nearby NPCs play out (narration, lines in their own voice, OStim scenes), or let an NPC write them. Choose the language of the settings menu and page.</Description>
  <Groups>
    <element>Gameplay</element>
  </Groups>
</fomod>
"@
$plugins = ($languages | ForEach-Object {
    $type = if ($_.recommended) { 'Recommended' } else { 'Optional' }
    @"
            <plugin name="$(& $esc $_.name)">
              <description>$(& $esc $_.desc)</description>
              <conditionFlags>
                <flag name="Language">$($_.code)</flag>
              </conditionFlags>
              <typeDescriptor>
                <type name="$type"/>
              </typeDescriptor>
            </plugin>
"@
}) -join "`n"
$patterns = ($languages | ForEach-Object {
    @"
      <pattern>
        <dependencies operator="And">
          <flagDependency flag="Language" value="$($_.code)"/>
        </dependencies>
        <files>
          <folder source="core\$($_.code)" destination="" priority="0"/>
        </files>
      </pattern>
"@
}) -join "`n"
$config = @"
<?xml version="1.0" encoding="UTF-8"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://qconsulting.ca/fo3/ModConfig5.0.xsd">
  <moduleName>SkyrimNet Dialogue Scenario Editor</moduleName>
  <installSteps order="Explicit">
    <installStep name="Language">
      <optionalFileGroups order="Explicit">
        <group name="Language of the settings menu and page" type="SelectExactlyOne">
          <plugins order="Explicit">
$plugins
          </plugins>
        </group>
      </optionalFileGroups>
    </installStep>
  </installSteps>
  <conditionalFileInstalls>
    <patterns>
$patterns
    </patterns>
  </conditionalFileInstalls>
</config>
"@
[System.IO.File]::WriteAllText("$stage\fomod\info.xml", $info.Replace("`r`n", "`n"), $utf8)
[System.IO.File]::WriteAllText("$stage\fomod\ModuleConfig.xml", $config.Replace("`r`n", "`n"), $utf8)

# ---- the archive, with forward slashes in every entry name ----
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
try {
    Get-ChildItem $stage -Recurse -File | ForEach-Object {
        $entry = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $entry, 'Optimal') | Out-Null
    }
} finally { $archive.Dispose() }

# ---- read it back as an installer would ----
$japanese = '[\u3040-\u30FF\u4E00-\u9FFF]'
$archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    $entries = @{}
    foreach ($e in $archive.Entries) { $entries[$e.FullName] = $e }
    $read = { param($path) $s = $entries[$path].Open(); $m = New-Object System.IO.MemoryStream; $s.CopyTo($m); $s.Dispose(); $m.ToArray() }
    $text = { param($path) [System.Text.Encoding]::UTF8.GetString((& $read $path)) }
    foreach ($x in 'fomod/ModuleConfig.xml', 'fomod/info.xml') {
        if (-not $entries.ContainsKey($x)) { Problem "missing $x"; continue }
        $bytes = & $read $x
        if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) { Problem "$x has a BOM" }
        if ((& $text $x) -notmatch '^<\?xml version="1\.0" encoding="UTF-8"\?>') { Problem "$x : the declaration must use double quotes (Vortex)" }
    }
    foreach ($top in ($entries.Keys | ForEach-Object { $_.Split('/')[0] } | Sort-Object -Unique)) {
        if ($top -notin 'fomod', 'core') { Problem "unexpected top-level entry: $top" }
    }
    [xml]$xml = & $text 'fomod/ModuleConfig.xml'
    $group = $xml.config.installSteps.installStep.optionalFileGroups.group
    if ($group.type -ne 'SelectExactlyOne') { Problem "group type $($group.type)" }
    [xml]$infoXml = & $text 'fomod/info.xml'
    if ($infoXml.fomod.Name -ne $name -or $infoXml.fomod.Version -ne $Version) { Problem "info.xml Name/Version" }
    $flags = @($group.plugins.plugin | ForEach-Object { $_.conditionFlags.flag.'#text' })
    if ($flags.Count -ne $languages.Count) { Problem "$($flags.Count) choices, $($languages.Count) languages" }
    $sets = @{}
    foreach ($p in $xml.config.conditionalFileInstalls.patterns.pattern) {
        $flag = $p.dependencies.flagDependency.value
        $source = $p.files.folder.source.Replace('\', '/')
        if ($flag -notin $flags) { Problem "pattern $flag has no choice" }
        $files = @($entries.Keys | Where-Object { $_.StartsWith("$source/") } | ForEach-Object { $_.Substring($source.Length + 1) })
        $sets[$flag] = $files
        $needed = "SKSE/Plugins/$name.dll", "$name.esp", 'COPYING.txt', 'THIRD_PARTY_NOTICES.txt', 'README.md', 'README_ja.md',
            "MCM/Config/$name/config.json", "MCM/Config/$name/settings.ini",
            "Scripts/${name}Main.pex", "Scripts/${name}UI.pex", "Scripts/${name}Player.pex", "Scripts/${name}Native.pex",
            "Source/Scripts/${name}Main.psc", "Source/SKSE/$name/src/main.cpp", "Source/SKSE/$name/src/generator.cpp", "Source/SKSE/$name/xmake.lua", "Source/SKSE/$name/README.txt",
            "Magelight/$name/views/index.html", "PrismaUI/views/$name/index.html",
            "SKSE/Plugins/StorageUtilData/${name}_Common.json", "SKSE/Plugins/StorageUtilData/$name/example_riverwood.json",
            "SKSE/Plugins/SkyrimNet/external/nightlantern-mods.dialogue-scenario-editor/manifest.json",
            "SKSE/Plugins/SkyrimNet/external/nightlantern-mods.dialogue-scenario-editor/settings/DialogueScenarioEditor.yaml",
            "SKSE/Plugins/SkyrimNet/external/nightlantern-mods.dialogue-scenario-editor/prompts/dse_scenario_plan.prompt",
            "SKSE/Plugins/SkyrimNet/external/nightlantern-mods.dialogue-scenario-editor/prompts/dse_scenario_column.prompt"
        foreach ($need in $needed) { if ($need -notin $files) { Problem "$source : missing $need" } }
        foreach ($g in $gameLanguages) {
            $t = "$source/Interface/Translations/${name}_$g.txt"
            if (-not $entries.ContainsKey($t)) { Problem "$source : missing $t"; continue }
            $b = & $read $t
            if ($b[0] -ne 0xFF -or $b[1] -ne 0xFE) { Problem "$t : not UTF-16 LE with BOM" }
            $s = [System.Text.Encoding]::Unicode.GetString($b, 2, $b.Length - 2)
            if (($flag -eq 'ja') -ne ($s -match $japanese)) { Problem "$t : not in the language of choice $flag" }
            foreach ($key in ((& $text "$source/MCM/Config/$name/config.json") | Select-String -Pattern '"(\$[A-Za-z_]+)"' -AllMatches).Matches.Groups | Where-Object { $_.Name -eq '1' } | ForEach-Object Value) {
                if ($s -notmatch [regex]::Escape($key) + "`t") { Problem "$t : no text for $key" }
            }
        }
        # the language of the page, the line wording and the example
        foreach ($page in "Magelight/$name/views/index.html", "PrismaUI/views/$name/index.html") {
            $html = & $text "$source/$page"
            $visible = ($html -split "`n" | Where-Object { $_ -notmatch 'return \["player", "\{player\}", "プレイヤー", "\{プレイヤー\}"\]' }) -join "`n"
            if (($flag -eq 'ja') -ne ($visible -match $japanese)) { Problem "$source/$page : not in the language of choice $flag" }
            $script = [regex]::Matches($html, '(?s)<script>(.*?)</script>') | Select-Object -Last 1
            [System.IO.File]::WriteAllText("$env:TEMP\dse_page_check.js", $script.Groups[1].Value, $utf8)
            if ((Invoke-Tool { node --check "$env:TEMP\dse_page_check.js" }) -ne 0) { Problem "$source/$page : the script does not parse" }
        }
        foreach ($json in "SKSE/Plugins/StorageUtilData/${name}_Common.json", "SKSE/Plugins/StorageUtilData/$name/example_riverwood.json") {
            $j = & $text "$source/$json"
            try { $null = $j | ConvertFrom-Json } catch { Problem "$source/$json : not JSON" }
            $words = ($j -replace '"playerwords"[^\]]*\]', '')
            if (($flag -eq 'ja') -ne ($words -match $japanese)) { Problem "$source/$json : not in the language of choice $flag" }
        }
        foreach ($f in $files) { if ($f -match '\.(log|tmp|bak|obj|pdb)$' -or $f -match '(^|/)build/') { Problem "$source : stray file $f" } }
        if (($files | Where-Object { $_ -like '*.esp' }).Count -ne 1) { Problem "$source : not exactly one plugin" }
    }
    foreach ($flag in $flags) {
        if (-not $sets.ContainsKey($flag)) { Problem "choice $flag installs nothing"; continue }
        $diff = Compare-Object ($sets['en'] | Sort-Object) ($sets[$flag] | Sort-Object)
        if ($diff) { Problem "choice $flag : files differ from English: $(($diff | ForEach-Object { $_.InputObject }) -join ', ')" }
    }
    $count = $sets['en'].Count
} finally { $archive.Dispose() }

if ($problems.Count) {
    Remove-Item $zip
    Write-Host "the archive was removed: $($problems.Count) problem(s)" -ForegroundColor Red
    exit 1
}
"$([IO.Path]::GetFileName($zip)): $($languages.Count) languages x $count files, $([math]::Round((Get-Item $zip).Length/1KB)) KB; the installer reads back clean"
