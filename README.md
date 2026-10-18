# mdreport

A small command-line tool that turns Markdown into print-ready PDF reports. It converts the Markdown to a self-contained HTML page with [pandoc](https://pandoc.org), styles it with a template, and prints it to PDF with headless Chrome or Edge.

## Requirements

- [pandoc](https://pandoc.org/installing.html) on `PATH` (2.19+ recommended; older versions also work)
- Google Chrome, Chromium or Microsoft Edge. If yours is installed somewhere unusual, set `MDREPORT_BROWSER` to its path.
- Windows PowerShell 5.1, or PowerShell 7 (`pwsh`) on macOS and Linux

## Usage

On Windows, run `mdreport.cmd` (or add this folder to `PATH` and run `mdreport`). On macOS and Linux, run `./mdreport`.

```text
mdreport build <file.md>... [options]   Build one or more Markdown files into PDFs
mdreport templates                      List the available templates
mdreport new-template <name> [--from T] Create ./templates/<name> from template T
mdreport help                           Show help
```

Build options:

| Option | Meaning |
|---|---|
| `-t`, `--template <name\|path>` | Template name, or a path to a template folder or `.css` file. Default: `default`. |
| `-o`, `--out <path>` | Output `.pdf` file (one input only) or output folder. Default: next to each input. |
| `--html` | Also keep the intermediate HTML next to the PDF. |
| `--open` | Open the PDF when it is built. |

Examples:

```powershell
mdreport build report.md                     # -> report.pdf
mdreport build docs\*.md -o out              # -> out\<name>.pdf for each file
mdreport build report.md -t minimal          # use another template
mdreport build report.md -t .\brand.css      # use a one-off stylesheet
```

## Writing the Markdown

Any pandoc Markdown works. A YAML front matter block sets the title block:

```markdown
---
title: "Quarterly review"
subtitle: "Draft for comments"
author: "Team name"
date: "18. 10. 2026"
lang: cs
---
```

- Images are resolved relative to the Markdown file and embedded into the PDF. An image alone in its own paragraph becomes a figure, and its alt text becomes the caption.
- `> quotes` render as highlighted callout boxes in the default template, which works well for questions to the reader.
- `<div class="page-break"></div>` forces a page break.

## Templates

A template is a folder that contains:

- `style.css`: required. Print rules such as `@page { size: A4; margin: … }` go here.
- `template.html`: optional. A [pandoc HTML template](https://pandoc.org/MANUAL.html#templates), for when CSS alone isn't enough, for example to add a logo or a fixed header.
- any fonts or images that the CSS refers to, by a relative path

Templates are looked up by name in this order, and the first match wins:

1. `./templates/<name>`, relative to the folder you run `mdreport` in, for templates kept with a project
2. `$MDREPORT_TEMPLATES/<name>`, for a shared personal collection
3. `templates/<name>` inside this repo, for the built-in templates

To create a new template, copy an existing one and edit it:

```powershell
mdreport new-template brand            # copies "default" to .\templates\brand
mdreport build report.md -t brand
```

Built-in templates:

| Name | Look |
|---|---|
| `default` | A4, Segoe UI, yellow accent bars on the title and section headings, yellow callout boxes. Colours are CSS variables at the top of `style.css`. |

To add a built-in template, put a new folder with a `style.css` under `templates/`.

## Example

```powershell
.\mdreport.cmd build examples\example.md
```
