# Builds SkyrimNet_DialogueScenarioEditor.dll and copies it, with the settings page for Prisma UI,
# into the skyrim-modding-tools-mcp project (its assets/), which deployProject turns into the MO2 mod.
# The page itself is edited in assets\Magelight\...\views\index.html; Prisma UI gets a copy.
$project = 'C:\Modding\skyrim-modding-tools-mcp\projects\SkyrimNet_DialogueScenarioEditor\assets'
Push-Location $PSScriptRoot
try {
    & 'C:\Program Files\xmake\xmake.exe' build -y
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    New-Item -ItemType Directory -Force "$project\SKSE\Plugins" | Out-Null
    Copy-Item build\windows\x64\release\SkyrimNet_DialogueScenarioEditor.dll "$project\SKSE\Plugins\" -Force
    $prisma = "$project\PrismaUI\views\SkyrimNet_DialogueScenarioEditor"
    New-Item -ItemType Directory -Force $prisma | Out-Null
    Copy-Item "$project\Magelight\SkyrimNet_DialogueScenarioEditor\views\*" "$prisma\" -Force
} finally {
    Pop-Location
}
