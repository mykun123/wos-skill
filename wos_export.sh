#!/bin/bash
# ============================================================================
# WOS Bulk Export Script — based on opencli browser automation
# Usage:
#   ./wos_export.sh --keyword "Social Governance Innovation" --count 2000
#   ./wos_export.sh --url "https://webofscience.clarivate.cn/wos/alldb/summary/..." --count 3000
#   ./wos_export.sh --url "..." --count 1000 --output-dir /tmp/wos
# ============================================================================

set -euo pipefail

# ── Default configuration ──────────────────────────────────────────────
BATCH_SIZE=1000
OUTPUT_DIR="~/wos-exports"
MERGE=true
MERGE_DIR="~/wos-merge"
RECORD_CONTENT="abstract"  # "basic" or "abstract"

# ── Global variables ──────────────────────────────────────────────
LAST_DOWNLOADED_FILE=""    # Final file of the current batch (stored in task subdirectory)
TASK_DIR=""                # File subdirectory for this task
PRE_DOWNLOAD_FILES=""      # List of files in Chrome download directory before export (for comparison to find new files)

# ── Color output ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "${CYAN}[INFO]${NC} $*" >&2; }
ok()    { echo -e "${GREEN}[OK]${NC}   $*" >&2; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
err()   { echo -e "${RED}[ERR]${NC}  $*" >&2; }

# ── Argument parsing ──────────────────────────────────────────────
KEYWORD=""
URL=""
COUNT=0

usage() {
    echo "Usage:"
    echo "  $0 --keyword \"search term\" --count N"
    echo "  $0 --url \"results page URL\" --count N"
    echo ""
    echo "Options:"
    echo "  --keyword    WOS search term (English)"
    echo "  --url        Pre-configured WOS results page URL"
    echo "  --count      Number of records to export (automatically split by 1000)"
    echo "  --output-dir Download directory (default: $OUTPUT_DIR)"
    echo "  --merge-dir  Directory for merged files (default: $MERGE_DIR)"
    echo "  --no-merge   Do not merge, keep only batch files"
    echo "  --content    Record content: basic | abstract (default: abstract)"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keyword)    KEYWORD="$2"; shift 2 ;;
        --url)        URL="$2"; shift 2 ;;
        --count)      COUNT="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --merge-dir)  MERGE_DIR="$2"; shift 2 ;;
        --no-merge)   MERGE=false; shift ;;
        --content)    RECORD_CONTENT="$2"; shift 2 ;;
        --help|-h)    usage ;;
        *)            err "Unknown parameter: $1"; usage ;;
    esac
done

# ── Parameter validation ──────────────────────────────────────────────
if [[ -z "$KEYWORD" && -z "$URL" ]]; then
    err "Must specify --keyword or --url"; usage
fi
if [[ $COUNT -le 0 ]]; then
    err "Must specify --count greater than 0"; usage
fi
if [[ $COUNT -gt 10000 ]]; then
    warn "WOS single search can export up to 10000 records, you requested $COUNT records"
fi
if [[ "$RECORD_CONTENT" != "basic" && "$RECORD_CONTENT" != "abstract" ]]; then
    err "--content must be basic or abstract"; exit 1
fi

# ── Generate task name and subdirectory ────────────────────────────────────
if [[ -n "$KEYWORD" ]]; then
    SAFE_NAME=$(echo "$KEYWORD" | tr ' ' '_' | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_')
else
    SAFE_NAME="wos_export_$(date +%Y%m%d_%H%M%S)"
fi
TASK_DIR="${OUTPUT_DIR}/${SAFE_NAME}"
mkdir -p "$TASK_DIR"

# ── Calculate batches ──────────────────────────────────────────────
TOTAL_BATCHES=$(( (COUNT + BATCH_SIZE - 1) / BATCH_SIZE ))

log "═══════════════════════════════════════════════════"
log "WOS Bulk Export Task"
log "═══════════════════════════════════════════════════"
[[ -n "$KEYWORD" ]] && log "Search term: $KEYWORD"
[[ -n "$URL" ]]     && log "Results page: $URL"
log "Export count: $COUNT records (split into $TOTAL_BATCHES batches, $BATCH_SIZE per batch)"
log "Record content: $RECORD_CONTENT"
log "Download directory: $OUTPUT_DIR"
log "Task subdirectory: $TASK_DIR"
log "Merge directory: $MERGE_DIR"
log "═══════════════════════════════════════════════════"

# ── Utility functions ──────────────────────────────────────────────

clear_cookie_banner() {
    log "Clearing cookie banner..."
    opencli browser eval "(function(){var s=document.getElementById('onetrust-consent-sdk');if(s){s.remove();return 'removed';}return 'not found';})()" 2>&1 | grep -v "Update available" | grep -v "Run:" | grep -v "^$" || true
}

# Record existing files in Chrome download directory before export (for comparison to find new files)
snapshot_pre_files() {
    PRE_DOWNLOAD_FILES=$(ls -1 "$OUTPUT_DIR"/savedrecs*.txt 2>/dev/null || true)
}

# Wait for download to appear and verify — move result to TASK_DIR (with batch number), store path in LAST_DOWNLOADED_FILE
wait_for_download() {
    local expected_lines="$1"
    local batch_num="$2"
    local timeout=60
    local elapsed=0

    log "Waiting for download to complete (max ${timeout}s)..."

    while [[ $elapsed -lt $timeout ]]; do
        sleep 5
        elapsed=$((elapsed + 5))

        # Find newly appearing files (not in PRE_DOWNLOAD_FILES)
        local new_file=""
        for f in "$OUTPUT_DIR"/savedrecs*.txt; do
            [[ -e "$f" ]] || continue
            if ! echo "$PRE_DOWNLOAD_FILES" | grep -qF "$f"; then
                new_file="$f"
                break
            fi
        done

        if [[ -n "$new_file" ]]; then
            local lines
            lines=$(wc -l < "$new_file")
            local size
            size=$(du -h "$new_file" | cut -f1)

            if [[ $lines -ge $expected_lines ]]; then
                # Move to task subdirectory with batch number to avoid overwriting
                local dest="${TASK_DIR}/savedrecs_batch_${batch_num}.txt"
                mv "$new_file" "$dest"
                ok "Download complete: savedrecs_batch_${batch_num}.txt (${size}, ${lines} lines) → moved to task directory"
                LAST_DOWNLOADED_FILE="$dest"
                return 0
            else
                log "  Waiting... ${lines}/${expected_lines} lines (${elapsed}s)"
            fi
        else
            log "  Waiting... no new file yet (${elapsed}s)"
        fi
    done

    err "Download timeout, no new file found"
    return 1
}

# Execute a single batch export — result stored in LAST_DOWNLOADED_FILE
export_batch() {
    local batch_from="$1"
    local batch_to="$2"
    local batch_num="$3"

    log ""
    log "── Batch ${batch_num}/${TOTAL_BATCHES}: ${batch_from}-${batch_to} ──"

    clear_cookie_banner

    # Select option index based on content
    local opt_idx=0
    [[ "$RECORD_CONTENT" == "abstract" ]] && opt_idx=1

    # One-click export
    local result
    result=$(opencli browser eval "
(async function(){
  var s = document.getElementById('onetrust-consent-sdk');
  if(s) s.remove();

  document.getElementById('export-trigger-btn').click();
  await new Promise(r => setTimeout(r, 1500));

  document.getElementById('exportToTabWinButton').click();
  await new Promise(r => setTimeout(r, 2500));

  var radioInput = document.querySelector('#radio3 input[type=radio]');
  if(radioInput && !radioInput.checked){
    radioInput.click();
    await new Promise(r => setTimeout(r, 500));
  }

  function typeValue(selector, value){
    return new Promise(function(resolve){
      var el = document.querySelector(selector);
      if(!el){ resolve(); return; }
      el.focus(); el.select();
      el.dispatchEvent(new KeyboardEvent('keydown',{key:'Backspace',bubbles:true}));
      el.value = '';
      el.dispatchEvent(new InputEvent('input',{bubbles:true}));
      var chars = value.split('');
      var i = 0;
      function typeNext(){
        if(i >= chars.length){
          el.dispatchEvent(new Event('change',{bubbles:true}));
          el.dispatchEvent(new Event('blur',{bubbles:true}));
          resolve(); return;
        }
        var ch = chars[i++];
        el.dispatchEvent(new KeyboardEvent('keydown',{key:ch,bubbles:true}));
        el.dispatchEvent(new KeyboardEvent('keypress',{key:ch,bubbles:true}));
        el.value += ch;
        el.dispatchEvent(new InputEvent('input',{bubbles:true}));
        el.dispatchEvent(new KeyboardEvent('keyup',{key:ch,bubbles:true}));
        setTimeout(typeNext, 50);
      }
      typeNext();
    });
  }

  await typeValue('input[name=markFrom]', '${batch_from}');
  await typeValue('input[name=markTo]', '${batch_to}');

  var btn = document.querySelector('wos-select button[role=combobox]');
  if(btn){
    btn.click();
    await new Promise(r => setTimeout(r, 500));
    var options = document.querySelectorAll('[role=option]');
    if(options[${opt_idx}]) options[${opt_idx}].click();
  }

  await new Promise(r => setTimeout(r, 500));

  var exportBtn = document.getElementById('exportButton');
  if(exportBtn) exportBtn.click();

  var fromVal = document.querySelector('input[name=markFrom]');
  var toVal = document.querySelector('input[name=markTo]');
  return 'From=' + (fromVal?fromVal.value:'?') + ' To=' + (toVal?toVal.value:'?') + ' radio=' + (radioInput?radioInput.checked:'?');
})()
" 2>&1 | grep -E "^From=" || true)

    if [[ -n "$result" ]]; then
        log "Export triggered: $result"
    else
        warn "No export confirmation received, continuing to wait for download..."
    fi

    # Record existing files before export
    snapshot_pre_files

    # Wait for download — use actual batch size (+1 for header)
    local expected_lines=$(( batch_to - batch_from + 2 ))
    wait_for_download "$expected_lines" "$batch_num"
}

# ── Main workflow ────────────────────────────────────────────────

# Step 1: Open page
if [[ -n "$URL" ]]; then
    log "Opening results page directly..."
    opencli browser open "$URL" 2>&1 | grep -v "Update available" | grep -v "Run:" | grep -v "^$" || true
    sleep 8
else
    log "Opening search page and entering search term..."
    opencli browser open "https://www.webofscience.com/wos/woscc/basic-search" 2>&1 | grep -v "Update available" | grep -v "Run:" | grep -v "^$" || true
    sleep 5

    clear_cookie_banner

    # Clear search box
    opencli browser eval "document.getElementById('search-option-0').value=''; document.getElementById('search-option-0').dispatchEvent(new Event('input',{bubbles:true})); 'cleared'" 2>&1 | grep -v "Update available" | grep -v "Run:" | grep -v "^$" || true

    # Find search box and button indices
    search_box_idx=$(opencli browser state 2>&1 | grep -i "search-option-0" | grep -oP '\[\K[0-9]+' | head -1)
    search_btn_idx=$(opencli browser state 2>&1 | grep "type=submit" | grep -oP '\[\K[0-9]+' | head -1)

    log "Search box index: [$search_box_idx], Search button index: [$search_btn_idx]"

    opencli browser type "$search_box_idx" "$KEYWORD" 2>&1 | grep -v "Update available" | grep -v "Run:" | grep -v "^$" || true
    opencli browser click "$search_btn_idx" 2>&1 | grep -v "Update available" | grep -v "Run:" | grep -v "^$" || true

    log "Waiting for search results to load..."
    sleep 10

    current_url=$(opencli browser eval "window.location.href" 2>&1 | tail -1)
    if echo "$current_url" | grep -q "summary/"; then
        ok "Results page loaded: $current_url"
    else
        warn "May not have navigated to results page: $current_url"
    fi
fi

# Step 2: Loop export
declare -a DOWNLOADED_FILES=()

for (( batch=0; batch<TOTAL_BATCHES; batch++ )); do
    batch_from=$(( batch * BATCH_SIZE + 1 ))
    batch_to=$(( (batch + 1) * BATCH_SIZE ))

    if [[ $batch_to -gt $COUNT ]]; then
        batch_to=$COUNT
    fi

    actual_size=$(( batch_to - batch_from + 1 ))
    log "Actual export size for this batch: $actual_size records"

    export_batch "$batch_from" "$batch_to" $((batch + 1))
    DOWNLOADED_FILES+=("$LAST_DOWNLOADED_FILE")

    # Wait between batches
    if [[ $((batch + 1)) -lt $TOTAL_BATCHES ]]; then
        log "Waiting 5 seconds between batches..."
        sleep 5
    fi
done

# Step 3: Merge
if [[ "$MERGE" == true && ${#DOWNLOADED_FILES[@]} -gt 0 ]]; then
    log ""
    log "── Merging files ──"

    merge_file="${TASK_DIR}/merge.txt"

    log "Merging to: $merge_file"
    log "(Original batch files preserved in task directory)"

    head -1 "${DOWNLOADED_FILES[0]}" > "$merge_file"
    for f in "${DOWNLOADED_FILES[@]}"; do
        tail -n +2 "$f" >> "$merge_file"
    done

    total_lines=$(wc -l < "$merge_file")
    total_size=$(du -h "$merge_file" | cut -f1)

    ok "Merge complete: $merge_file (${total_size}, ${total_lines} lines)"
    log "Expected lines: $((COUNT + 1)) (including header)"
    log "Original batch files preserved at: $TASK_DIR/"
fi

log ""
log "═══════════════════════════════════════════════════"
ok "All exports complete!"
log "═══════════════════════════════════════════════════"