<#
mdreport: build PDF reports from Markdown with pandoc and headless Chrome.

  mdreport build <file.md>... [-t <template>] [-o <out>] [--html] [--open]
  mdreport templates
  mdreport new-template <name> [--from <template>]
  mdreport help

Run "mdreport help" for details.
#>

$ErrorActionPreference = 'Stop'
$ToolRoot = $PSScriptRoot
$BuiltinTemplates = Join-Path $ToolRoot 'templates'
$DefaultTemplate = 'default'

$Usage = @'
mdreport: build PDF reports from Markdown

Usage:
  mdreport build <file.md>... [options]   Build one or more Markdown files into PDFs
  mdreport templates                      List the available templates
  mdreport new-template <name> [--from T] Create ./templates/<name> from template T (default: default)
  mdreport help                           Show this help

Build options:
  -t, --template <name|path>  Template name or path to a template folder or .css file (default: default)
  -o, --out <path>            Output .pdf file (one input only) or output folder
      --html                  Also keep the intermediate HTML next to the PDF
      --open                  Open the PDF when it is built

Templates are looked up by name in this order:
  1. ./templates/<name>          (next to where you run mdreport)
  2. $MDREPORT_TEMPLATES/<name>  (if the variable is set)
  3. <mdreport>/templates/<name> (built in)

A template is a folder with a style.css and, optionally, a pandoc HTML
template named template.html. Images in the Markdown are resolved relative
to the Markdown file.
'@

function Fail([string]$Message) {
    [Console]::Error.WriteLine("mdreport: $Message")
    exit 1
}

function Get-TemplateRoots {
    $roots = @(Join-Path (Get-Location) 'templates')
    if ($env:MDREPORT_TEMPLATES) { $roots += $env:MDREPORT_TEMPLATES }
    $roots += $BuiltinTemplates
    $roots | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Select-Object -Unique
}

# Returns @{ Name; Css; HtmlTemplate } for a template name, folder or .css file.
function Resolve-Template([string]$Spec) {
    if (Test-Path -LiteralPath $Spec -PathType Leaf) {
        $css = (Resolve-Path -LiteralPath $Spec).Path
        return @{ Name = $Spec; Css = $css; HtmlTemplate = $null }
    }
    $dirs = @()
    if (Test-Path -LiteralPath $Spec -PathType Container) { $dirs += (Resolve-Path -LiteralPath $Spec).Path }
    foreach ($root in Get-TemplateRoots) { $dirs += Join-Path $root $Spec }
    foreach ($dir in $dirs) {
        $css = Join-Path $dir 'style.css'
        if (Test-Path -LiteralPath $css) {
            $html = Join-Path $dir 'template.html'
            return @{
                Name = $Spec
                Css = $css
                HtmlTemplate = $(if (Test-Path -LiteralPath $html) { $html } else { $null })
            }
        }
    }
    Fail "template '$Spec' not found. Run 'mdreport templates' to list them."
}

function Find-Browser {
    $candidates = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
        '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'
    )
    if ($env:MDREPORT_BROWSER) { $candidates = @($env:MDREPORT_BROWSER) + $candidates }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    foreach ($name in 'google-chrome', 'chromium', 'chromium-browser', 'microsoft-edge') {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    Fail 'Chrome, Chromium or Edge is required. Set MDREPORT_BROWSER to its path if it is installed elsewhere.'
}

function Get-PandocEmbedArgs {
    if (-not (Get-Command pandoc -ErrorAction SilentlyContinue)) {
        Fail 'pandoc is required but was not found on PATH.'
    }
    $versionLine = (& pandoc --version | Select-Object -First 1)
    if ($versionLine -match '(\d+)\.(\d+)') {
        $version = [version]"$($matches[1]).$($matches[2])"
        if ($version -lt [version]'2.19') { return @('--self-contained') }
    }
    @('--standalone', '--embed-resources')
}

function Test-HasTitle([string]$Path) {
    $head = Get-Content -LiteralPath $Path -TotalCount 30 -Encoding UTF8
    if ($head.Count -eq 0 -or $head[0] -ne '---') { return $false }
    foreach ($line in $head | Select-Object -Skip 1) {
        if ($line -match '^(---|\.\.\.)\s*$') { return $false }
        if ($line -match '^title\s*:') { return $true }
    }
    $false
}

function Invoke-Build([string[]]$Arguments) {
    $inputs = @()
    $templateSpec = $DefaultTemplate
    $out = $null
    $keepHtml = $false
    $open = $false

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $a = $Arguments[$i]
        switch -Regex ($a) {
            '^(-t|--template)$' { $i++; if ($i -ge $Arguments.Count) { Fail "$a needs a value." }; $templateSpec = $Arguments[$i]; continue }
            '^(-o|--out)$'      { $i++; if ($i -ge $Arguments.Count) { Fail "$a needs a value." }; $out = $Arguments[$i]; continue }
            '^--html$'          { $keepHtml = $true; continue }
            '^--open$'          { $open = $true; continue }
            '^-'                { Fail "unknown option '$a'. Run 'mdreport help'." }
            default {
                $matched = @(Resolve-Path -Path $a -ErrorAction SilentlyContinue)
                if ($matched.Count -eq 0) { Fail "file not found: $a" }
                $inputs += $matched | ForEach-Object { $_.Path }
            }
        }
    }
    if ($inputs.Count -eq 0) { Fail "no input files. Usage: mdreport build <file.md>... [-t <template>] [-o <out>]" }

    $outFile = $null
    $outDir = $null
    if ($out) {
        if ($out -match '\.pdf$') {
            if ($inputs.Count -gt 1) { Fail '-o with a .pdf file name needs exactly one input; pass a folder instead.' }
            $outFile = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $out))
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outFile) | Out-Null
        } else {
            $outDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $out))
            New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        }
    }

    $template = Resolve-Template $templateSpec
    $embedArgs = Get-PandocEmbedArgs
    $browser = Find-Browser
    # A separate profile keeps headless Chrome from attaching to a running browser.
    $profileDir = Join-Path ([System.IO.Path]::GetTempPath()) 'mdreport-browser-profile'

    foreach ($src in $inputs) {
        $srcDir = Split-Path -Parent $src
        $base = [System.IO.Path]::GetFileNameWithoutExtension($src)
        $pdf = if ($outFile) { $outFile } elseif ($outDir) { Join-Path $outDir "$base.pdf" } else { Join-Path $srcDir "$base.pdf" }
        $html = if ($keepHtml) { [System.IO.Path]::ChangeExtension($pdf, '.html') } else { Join-Path ([System.IO.Path]::GetTempPath()) "mdreport-$([guid]::NewGuid()).html" }

        $pandocArgs = @($src) + $embedArgs + @('--css', $template.Css, "--resource-path=$srcDir", '-o', $html)
        if ($template.HtmlTemplate) { $pandocArgs += @('--template', $template.HtmlTemplate) }
        if (-not (Test-HasTitle $src)) { $pandocArgs += @('--metadata', "pagetitle=$base") }

        & pandoc @pandocArgs
        if ($LASTEXITCODE -ne 0) { Fail "pandoc failed for $src" }

        if (Test-Path -LiteralPath $pdf) { Remove-Item -LiteralPath $pdf }
        $url = ([System.Uri]$html).AbsoluteUri
        $proc = Start-Process -FilePath $browser -Wait -PassThru -WindowStyle Hidden -ArgumentList @(
            '--headless=new', '--disable-gpu', '--no-pdf-header-footer',
            "--user-data-dir=`"$profileDir`"", "--print-to-pdf=`"$pdf`"", "`"$url`""
        )
        if (-not $keepHtml) { Remove-Item -LiteralPath $html -ErrorAction SilentlyContinue }
        if (-not (Test-Path -LiteralPath $pdf)) { Fail "the browser did not produce $pdf (exit code $($proc.ExitCode))." }

        Write-Host "$src -> $pdf  [$($template.Name)]"
        if ($open) { Invoke-Item -LiteralPath $pdf }
    }
}

function Show-Templates {
    $seen = @{}
    foreach ($root in Get-TemplateRoots) {
        Get-ChildItem -LiteralPath $root -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'style.css') } | ForEach-Object {
            $shadowed = $seen.ContainsKey($_.Name)
            $seen[$_.Name] = $true
            $note = if ($shadowed) { '  (shadowed)' } else { '' }
            '{0,-16} {1}{2}' -f $_.Name, $_.FullName, $note
        }
    }
}

function New-Template([string[]]$Arguments) {
    $name = $null
    $from = $DefaultTemplate
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $a = $Arguments[$i]
        if ($a -eq '--from') { $i++; if ($i -ge $Arguments.Count) { Fail '--from needs a value.' }; $from = $Arguments[$i] }
        elseif ($a -match '^-') { Fail "unknown option '$a'." }
        elseif (-not $name) { $name = $a }
        else { Fail "unexpected argument '$a'." }
    }
    if (-not $name) { Fail 'usage: mdreport new-template <name> [--from <template>]' }
    if ($name -notmatch '^[A-Za-z0-9._-]+$') { Fail 'template names may contain only letters, digits, ".", "_" and "-".' }

    $source = Resolve-Template $from
    $target = Join-Path (Join-Path (Get-Location) 'templates') $name
    if (Test-Path -LiteralPath $target) { Fail "$target already exists." }
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item -Path (Join-Path (Split-Path -Parent $source.Css) '*') -Destination $target -Recurse
    Write-Host "Created $target from '$from'. Edit style.css, then build with: mdreport build <file.md> -t $name"
}

$command = if ($args.Count -gt 0) { $args[0] } else { 'help' }
$rest = @(if ($args.Count -gt 1) { $args[1..($args.Count - 1)] })

switch ($command) {
    'build'        { Invoke-Build $rest }
    'templates'    { Show-Templates }
    'new-template' { New-Template $rest }
    { $_ -in 'help', '-h', '--help' } { Write-Host $Usage }
    default        { Fail "unknown command '$command'. Run 'mdreport help'." }
}
