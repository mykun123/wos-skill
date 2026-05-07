# WOS Batch Export Skill

Automated bulk export from Web of Science (WOS) with browser automation through `opencli`.

This skill supports two entry points: a WOS keyword search or an already configured WOS results page URL. It then exports records in batches of up to 1,000 records, verifies downloaded files, preserves every batch file, and optionally merges all batches into one `merge.txt` file.

## Key Features

- **Keyword mode**: search WOS by an English keyword and export the returned records.
- **URL mode**: start from a pre-configured WOS results page, such as a page where the query, filters, years, document types, or sorting have already been set manually.
- **Automatic batching**: split exports into 1,000-record batches to match the WOS export limit.
- **Record-content selection**: export either basic records or records with abstracts.
- **Download verification**: wait for each `savedrecs*.txt` file and check that the downloaded line count is reasonable before continuing.
- **Task-level organization**: store all batch files under one task-specific subdirectory.
- **Optional merge**: merge all batches into `merge.txt` while preserving the original batch files.
- **UI friction handling**: remove common cookie banners and interact with WOS export controls through browser-side JavaScript.

## Prerequisites

| Requirement | Details |
|---|---|
| `opencli` browser automation CLI | The script requires an `opencli` executable that supports the `browser` subcommands used below. It was developed with the OpenClaw implementation of `opencli`, but it is not inherently tied to one specific OpenClaw release. Any compatible `opencli` build or wrapper should work if it provides the same browser command interface. |
| Browser with WOS access | The machine must already have access to WOS, either through an active institutional login session or an institutional network/proxy. This script does **not** handle WOS authentication. |
| Chrome/Chromium | `opencli browser` needs a controllable Chrome/Chromium browser environment. |
| Bash environment | The script is written for Bash and uses common Unix utilities such as `grep`, `wc`, `du`, `head`, and `tail`. |

## `opencli` Compatibility

The most important dependency is not the name of the OpenClaw version, but whether the available `opencli` command supports the browser automation interface expected by the script.

At minimum, the following commands should be available:

```bash
opencli browser open "https://www.webofscience.com/"
opencli browser state
opencli browser type <element_index> "text"
opencli browser click <element_index>
opencli browser eval "document.title"
```

If these commands work in your environment and can control the browser session, the script should be usable. If your `opencli` comes from OpenClaw, you can install or update it as follows:

```bash
# Install the OpenClaw implementation of opencli
# Make sure Go is installed and GOPATH/bin is in your PATH.
go install github.com/openclaw/openclaw/cmd/opencli@latest

# Example PATH setup if opencli is not found after installation
export PATH="$(go env GOPATH)/bin:$PATH"

# Verify the CLI is available
opencli --version
```

For a more reproducible environment, avoid relying blindly on `@latest`. Pin a known working tag or commit if your automation depends on a specific `opencli browser` behavior.

## Usage

Make the script executable first:

```bash
chmod +x wos_export.sh
```

Export by keyword:

```bash
./wos_export.sh --keyword "Social Governance Innovation" --count 2000
```

Export from a pre-configured WOS results URL:

```bash
./wos_export.sh \
  --url "https://webofscience.clarivate.cn/wos/alldb/summary/..." \
  --count 3000
```

Export with additional options:

```bash
./wos_export.sh \
  --keyword "AI in Public Policy" \
  --count 5000 \
  --content abstract \
  --output-dir /tmp/wos
```

Skip merging and keep only batch files:

```bash
./wos_export.sh \
  --url "https://webofscience.clarivate.cn/wos/alldb/summary/..." \
  --count 3000 \
  --no-merge
```

## Options

| Option | Description | Default |
|---|---|---|
| `--keyword` | WOS search term. Use English keywords for reliable WOS search results. | — |
| `--url` | Pre-configured WOS results page URL. Useful when filters, time ranges, categories, or sorting have already been set in the browser. | — |
| `--count` | Number of records to export. The script automatically splits this into 1,000-record batches. | Required |
| `--content` | Record content type: `basic` or `abstract`. | `abstract` |
| `--output-dir` | Directory where Chrome downloads `savedrecs*.txt` files and where the task subdirectory is created. | `~/wos-exports` |
| `--merge-dir` | Reserved/legacy option in the current script. The script currently writes the merged file to the task subdirectory as `merge.txt`. | `~/wos-merge` |
| `--no-merge` | Disable merging and preserve batch files only. | Merge enabled |


## Output Structure

For keyword mode, the script creates a task directory based on the search term. For URL mode, it creates a timestamped task directory.

Example:

```text
~/wos-exports/
└── social_governance_innovation/
    ├── savedrecs_batch_1.txt
    ├── savedrecs_batch_2.txt
    └── merge.txt
```

The merged file keeps the header from the first batch and appends the data rows from later batches.

## Workflow

1. Open the WOS page.
   - If `--url` is provided, the script opens that results page directly.
   - If `--keyword` is provided, the script opens the WOS basic search page, types the keyword, and waits for the results page.
2. Split the requested export count into 1,000-record batches.
3. For each batch:
   - Open the WOS export dialog.
   - Select record range, such as `1–1000`, `1001–2000`, etc.
   - Select record content, either `basic` or `abstract`.
   - Trigger export.
   - Wait for the downloaded `savedrecs*.txt` file.
   - Move the downloaded file into the task directory and rename it by batch number.
4. If merging is enabled, combine all batch files into `merge.txt`.

## Important Notes

- **WOS login is required**: make sure the browser session controlled by `opencli` can access WOS before running the script.
- **The script does not bypass authentication**: it only automates the export workflow after access has already been established.
- **Single-query export limit**: WOS typically limits exports from a single result set. The script warns when `--count` is above 10,000, but you should normally split larger jobs into multiple WOS queries.
- **Use English search terms in keyword mode**: Chinese keywords may return zero or unstable results depending on WOS indexing and query parsing.
- **WOS UI changes may break selectors**: the script relies on current WOS element IDs and DOM structure, such as `export-trigger-btn`, `exportToTabWinButton`, `radio3`, and `exportButton`.
- **First-run browser permissions**: if Chrome asks for download permission, handle it manually once before running large export jobs.
- **Do not delete batch files immediately**: keep the original batch files until you confirm that `merge.txt` has the expected number of lines.

## Troubleshooting

### `opencli: command not found`

Check whether `opencli` is installed and whether its binary directory is in `PATH`:

```bash
which opencli
opencli --version
```

If installed through Go, add `GOPATH/bin` to `PATH`:

```bash
export PATH="$(go env GOPATH)/bin:$PATH"
```

### Browser opens but WOS is not logged in

Open WOS manually in the same browser profile used by `opencli`, complete institutional login, and rerun the script.

### No file is downloaded

Check the following:

- Whether Chrome blocked automatic downloads.
- Whether the WOS export dialog opened successfully.
- Whether the WOS page layout has changed.
- Whether `--output-dir` matches the actual Chrome download directory used by `opencli`.

### Download timeout

The script waits up to 60 seconds for each batch. If your network is slow or WOS responds slowly, increase the `timeout` value inside `wait_for_download()`.

## Recommended Command Pattern

For repeatable exports, URL mode is usually more stable than keyword mode because all search filters are already fixed in WOS:

```bash
./wos_export.sh \
  --url "https://webofscience.clarivate.cn/wos/alldb/summary/..." \
  --count 5000 \
  --content abstract \
  --output-dir ~/wos-exports
```
