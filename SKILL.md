# WOS Batch Export Skill

> **⚠️ CAPTCHA Notice:** During execution, you may encounter 1–2 CAPTCHA challenges. This is normal and **does not break the script** — it will pause and prompt you to solve it manually, then continue automatically after you press Enter.

## Script Location

```
wos_export.sh
```

## Three Usage Modes

### Mode A: Simple Search

```bash
./wos_export.sh --keyword "Retrieval Augmented Generation" --count 5000
```

### Mode B: Advanced Search (supports AND/OR/NOT + year range)

```bash
./wos_export.sh --query "TS=(Retrieval Augmented Generation) AND TS=(Large Language Model)" --year 2020-2026 --count 5000

# OR combination
./wos_export.sh --query "TI=(Blockchain) OR TI=(Distributed Ledger)" --year 2018-2024 --count 3000

# Multi-condition
./wos_export.sh --query "AU=(Smith) AND TS=(Climate Change) AND KY=(Policy)" --count 2000
```

### Mode C: Reuse Current Browser Window (results page already open)

```bash
./wos_export.sh --reuse --count 5000
```

### Mode D: Pass a Pre-configured Results URL

```bash
./wos_export.sh --url "https://webofscience.clarivate.cn/wos/alldb/summary/..." --count 3000
```

## Full Options

| Argument | Description | Default |
|----------|-------------|---------|
| `--keyword` | WOS simple search keyword (English) | — |
| `--query` | Advanced search query string (supports TS/TI/AU/KY fields, AND/OR/NOT) | — |
| `--year` | Year range, e.g. `2020-2026` (used with `--query`, auto-appends `PY=`) | — |
| `--url` | Pre-configured results page URL | — |
| `--reuse` | Reuse the current Chrome automation window (no new tab) | — |
| `--count` | Number of records to export (auto-split by 1000); auto-adjusted to actual result count after search | 5000 |
| `--content` | Record content: `basic` or `abstract` | `abstract` |
| `--output-dir` | Download directory | `~/Downloads` |
| `--merge-dir` | Merged file output directory | workspace root |
| `--no-merge` | Skip merging, keep batch files only | — |

> Choose one of `--keyword`, `--query`, `--url`, `--reuse`.
> `--count` is optional; defaults to 5000, auto-adjusted to the actual WOS result count after search.

## WOS Field Codes

| Field | Description |
|-------|-------------|
| `TS=` | All Metadata (Topic) |
| `TI=` | Title |
| `AU=` | Author |
| `KY=` | Keywords |
| `AB=` | Abstract |
| `SO=` | Source (Journal) |
| `PY=` | Publication Year |
| `WC=` | Web of Science Category |

## What the Script Does Automatically

1. **Auto-detects actual WOS result count** after search, adjusts export batches accordingly
2. **Splits into batches of 1000**, loops through exports
3. **Auto-handles popups** each batch (Cookie consent, download confirmation, modals)
4. **Waits for download completion and verifies line count**
5. **Pads empty lines when count is short** (when actual WOS results are fewer than requested)
6. **Auto-terminates early** on non-final batches with timeout and no file (avoids idle waiting)
7. **5-second pause between batches**
8. **Auto-merges all batches into `merge.txt`** (in the task subdirectory; original batch files are preserved)

## Notes

- Search keywords must be in **English**; Chinese keywords return 0 results
- WOS allows a maximum of **10,000 records** per search
- Make sure Chrome is already logged into WOS with your institutional account before running
- Advanced search with `--query` triggers search via Enter key (not JS click)
