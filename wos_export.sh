#!/bin/bash
# ============================================================================
# WOS Batch Export Script — powered by opencli browser automation
# Usage:
#   ./wos_export.sh --keyword "Social Governance Innovation" --count 2000
#   ./wos_export.sh --url "https://webofscience.clarivate.cn/wos/alldb/summary/..." --count 3000
#   ./wos_export.sh --reuse --count 2000                  # reuse current window
# ============================================================================

set -euo pipefail

# ── Default Configuration ─────────────────────────────────────────────────
BATCH_SIZE=1000
OUTPUT_DIR="/home/fuwuqi/下载"
MERGE=true
MERGE_DIR="/home/fuwuqi/.openclaw/workspace"
RECORD_CONTENT="abstract"  # "basic" or "abstract"

# ── Global Variables ──────────────────────────────────────────────────────
LAST_DOWNLOADED_FILE=""    # Final file for the current batch (in task subdir)
TASK_DIR=""                # Task subdirectory for this run
PRE_DOWNLOAD_TS=0          # Pre-download timestamp (for find -newer)
COOKIE_CLEARED=false       # Whether cookie popup has been handled

# ── Colored Output ────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "${CYAN}[INFO]${NC} $*" >&2; }
ok()    { echo -e "${GREEN}[OK]${NC}   $*" >&2; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
err()   { echo -e "${RED}[ERR]${NC}  $*" >&2; }

# ── Argument Parsing ──────────────────────────────────────────────────────
KEYWORD=""
URL=""
QUERY=""       # Advanced search query string
YEAR_RANGE=""  # Year range, e.g. "2020-2026"
COUNT=0
REUSE=false

usage() {
    echo "Usage:"
    echo "  $0 --keyword \"search term\" --count N"
    echo "  $0 --query \"TS=(term1) AND TS=(term2)\" --year 2020-2026 --count N"
    echo "  $0 --url \"results page URL\" --count N"
    echo "  $0 --reuse --count N                       # reuse current Chrome window"
    echo ""
    echo "Options:"
    echo "  --keyword    WOS simple search keyword (English)"
    echo "  --query      Advanced search query string (supports TS/TI/AU/KY fields, AND/OR/NOT)"
    echo "  --year       Year range, e.g. 2020-2026 (used with --query, auto-appends PY=)"
    echo "  --url        Pre-configured WOS results page URL"
    echo "  --reuse      Reuse current Chrome automation window (no new tab)"
    echo "  --count      Number of records to export (auto-split by 1000)"
    echo "  --output-dir Download directory (default: $OUTPUT_DIR)"
    echo "  --merge-dir  Merged file output directory (default: $MERGE_DIR)"
    echo "  --no-merge   Skip merging, keep batch files only"
    echo "  --content    Record content: basic | abstract (default: abstract)"
    echo ""
    echo "Advanced search examples:"
    echo "  --query \"TS=(Retrieval Augmented Generation) AND TS=(Large Language Model)\" --year 2020-2026"
    echo "  --query \"TI=(Blockchain) OR TI=(Distributed Ledger)\" --year 2018-2024"
    echo "  --query \"AU=(Smith) AND TS=(Climate Change)\""
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keyword)    KEYWORD="$2"; shift 2 ;;
        --url)        URL="$2"; shift 2 ;;
        --query)      QUERY="$2"; shift 2 ;;
        --year)       YEAR_RANGE="$2"; shift 2 ;;
        --reuse)      REUSE=true; shift ;;
        --count)      COUNT="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --merge-dir)  MERGE_DIR="$2"; shift 2 ;;
        --no-merge)   MERGE=false; shift ;;
        --content)    RECORD_CONTENT="$2"; shift 2 ;;
        --help|-h)    usage ;;
        *)            err "Unknown argument: $1"; usage ;;
    esac
done

# ── Parameter Validation ──────────────────────────────────────────────────
if [[ -z "$KEYWORD" && -z "$URL" && -z "$QUERY" && "$REUSE" != true ]]; then
    err "One of --keyword, --query, --url, or --reuse is required"; usage
fi
if [[ -n "$QUERY" && -n "$KEYWORD" ]]; then
    err "--query and --keyword cannot be used together"; usage
fi
if [[ $COUNT -le 0 ]]; then
    COUNT=5000
    log "--count not specified, defaulting to 5000 (will auto-adjust to actual result count)"
fi
if [[ $COUNT -gt 10000 ]]; then
    warn "WOS allows max 10000 records per search, auto-adjusted to 10000"
    COUNT=10000
fi
if [[ "$RECORD_CONTENT" != "basic" && "$RECORD_CONTENT" != "abstract" ]]; then
    err "--content must be basic or abstract"; exit 1
fi

# ── Generate Task Name and Subdirectory ───────────────────────────────────
if [[ -n "$QUERY" ]]; then
    SAFE_NAME=$(echo "$QUERY" | tr ' ' '_' | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_' | cut -c1-60)
elif [[ -n "$KEYWORD" ]]; then
    SAFE_NAME=$(echo "$KEYWORD" | tr ' ' '_' | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_')
elif [[ -n "$URL" ]]; then
    SAFE_NAME="wos_export_$(date +%Y%m%d_%H%M%S)"
else
    SAFE_NAME="wos_reuse_$(date +%Y%m%d_%H%M%S)"
fi
TASK_DIR="${OUTPUT_DIR}/${SAFE_NAME}"
mkdir -p "$TASK_DIR"

# ── Calculate Batches ─────────────────────────────────────────────────────
TOTAL_BATCHES=$(( (COUNT + BATCH_SIZE - 1) / BATCH_SIZE ))

log "═══════════════════════════════════════════════════"
log "WOS Batch Export Task"
log "═══════════════════════════════════════════════════"
[[ -n "$KEYWORD" ]] && log "Keyword: $KEYWORD"
[[ -n "$QUERY" ]]   && log "Advanced query: $QUERY"
[[ -n "$YEAR_RANGE" ]] && log "Year range: $YEAR_RANGE"
[[ -n "$URL" ]]     && log "Results URL: $URL"
[[ "$REUSE" == true ]] && log "Mode: reuse current window"
log "Records: $COUNT (split into $TOTAL_BATCHES batches, $BATCH_SIZE each)"
log "Record content: $RECORD_CONTENT"
log "Download dir: $OUTPUT_DIR"
log "Task subdir: $TASK_DIR"
log "Merge dir: $MERGE_DIR"
log "═══════════════════════════════════════════════════"

# ===================================================================
#  Utility Functions
# ===================================================================

# Filter out opencli "Update available" prompts (keep meaningful lines)
filter_opencli() {
    grep -v "Update available" | grep -v "^Run: npm" | grep -v "^$" || true
}

# Get the last meaningful opencli output line (for URL single values)
filter_opencli_last() {
    grep -v "Update available" | grep -v "^Run: npm" | grep -v "^$" | tail -1
}

# ── Popup Detection and Dismissal (called before each export) ──────────────
check_and_clear_popups() {
    # Detect multiple popup types: Cookie consent, CAPTCHA, session expired, WOS alerts
    local has_popup
    has_popup=$(opencli browser eval "
(function(){
  var popups = [];
  // Cookie popup
  var cookie = document.getElementById('onetrust-consent-sdk');
  if(cookie && cookie.offsetParent !== null) popups.push('cookie');
  // CAPTCHA popup (hCaptcha / reCAPTCHA / custom)
  var captcha = document.querySelector('.hcaptcha-wrapper, .g-recaptcha, [class*=captcha], [class*=verification], [class*=challenge]');
  if(captcha && captcha.offsetParent !== null) popups.push('captcha');
  // Generic modal/dialog overlay
  var modals = document.querySelectorAll('[role=dialog], .modal-backdrop, .overlay');
  modals.forEach(function(m){ if(m.offsetParent !== null) popups.push('modal'); });
  // WOS session expired
  var session = document.querySelector('.session-expired, .session-timeout');
  if(session && session.offsetParent !== null) popups.push('session');
  return popups.join(',');
})()" 2>/dev/null | filter_opencli | tail -1)

    if [[ -z "$has_popup" || "$has_popup" == "undefined" ]]; then
        return 0  # No popup
    fi

    # If CAPTCHA detected, pause and wait for manual resolution
    if echo "$has_popup" | grep -q "captcha"; then
        err "═══════════════════════════════════════════════════"
        err "⚠️  CAPTCHA detected!"
        err "═══════════════════════════════════════════════════"
        err "Please solve the CAPTCHA manually in the Chrome automation window"
        err "Press Enter after completing..."
        err "═══════════════════════════════════════════════════"
        read -r  # Wait for user to press Enter
        ok "Continuing..."
        return 0
    fi

    warn "Popup detected: $has_popup, attempting to dismiss..."

    # Dismiss various popups
    opencli browser eval "
(function(){
  var removed = 0;
  // Cookie consent
  var cookie = document.getElementById('onetrust-consent-sdk');
  if(cookie) { cookie.remove(); removed++; }
  // Try clicking Accept All
  var acceptBtn = document.querySelector('#onetrust-accept-btn-handler, .onetrust-button-group button');
  if(acceptBtn) { acceptBtn.click(); removed++; }
  // Close Chrome download confirmation popup
  var downloadBubble = document.querySelector('#download-bubble, [id*=download-dialog]');
  if(downloadBubble){
    var alwaysBtn = downloadBubble.querySelector('button');
    if(alwaysBtn) { alwaysBtn.click(); removed++; }
    else { downloadBubble.remove(); removed++; }
  }
  // Close generic modals
  var closeBtns = document.querySelectorAll('[aria-label=Close], .close-btn, button.close');
  closeBtns.forEach(function(b){ b.click(); removed++; });
  return 'cleaned ' + removed + ' elements';
})()" 2>/dev/null | filter_opencli || true

    COOKIE_CLEARED=true
    ok "Popup handling complete"
}

# ── Record timestamp before download (for find -newer) ────────────────────
snapshot_pre_download() {
    sleep 1  # Ensure time gap from previous files
    PRE_DOWNLOAD_TS=$(date +%s)
}

# ── Wait for download file and verify ──────────────────────────────────────
wait_for_download() {
    local expected_lines="$1"
    local batch_num="$2"
    local timeout=120
    local elapsed=0
    local check_interval=5
    local is_last_batch=false
    [[ $batch_num -eq $TOTAL_BATCHES ]] && is_last_batch=true

    log "Waiting for download (max ${timeout}s, expecting ${expected_lines} lines)..."
    [[ "$is_last_batch" == true ]] && log "  (last batch — fewer lines is normal, actual results may be less than requested)"

    while [[ $elapsed -lt $timeout ]]; do
        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))

        # Use find -newer to locate new files (more reliable than ls+grep)
        local ref_file
        ref_file=$(mktemp /tmp/wos_ts_XXXXXX)
        touch -d "@${PRE_DOWNLOAD_TS}" "$ref_file"

        local new_file
        new_file=$(find "$OUTPUT_DIR" -maxdepth 1 -name "savedrecs*.txt" -newer "$ref_file" 2>/dev/null | head -1)
        rm -f "$ref_file"

        if [[ -n "$new_file" ]]; then
            local lines
            lines=$(wc -l < "$new_file")
            local size
            size=$(du -h "$new_file" | cut -f1)

            if [[ $lines -ge $expected_lines ]]; then
                # Move to task subdirectory with batch number to avoid overwrite
                local dest="${TASK_DIR}/savedrecs_batch_${batch_num}.txt"
                mv "$new_file" "$dest"
                ok "Download done: savedrecs_batch_${batch_num}.txt (${size}, ${lines} lines) → moved to task dir"
                LAST_DOWNLOADED_FILE="$dest"
                return 0
            elif [[ $lines -ge 2 ]]; then
                # Fewer lines than expected: move to task dir and pad empty lines
                local dest="${TASK_DIR}/savedrecs_batch_${batch_num}.txt"
                mv "$new_file" "$dest"
                local missing=$((expected_lines - lines))
                if [[ $missing -gt 0 ]]; then
                    # Pad empty lines
                    printf '%0.s\n' $(seq 1 $missing) >> "$dest"
                    local new_lines
                    new_lines=$(wc -l < "$dest")
                    ok "Download done: savedrecs_batch_${batch_num}.txt (${lines} lines → padded ${missing} empty → ${new_lines} lines)"
                else
                    ok "Download done: savedrecs_batch_${batch_num}.txt (${size}, ${lines} lines) → moved to task dir"
                fi
                LAST_DOWNLOADED_FILE="$dest"
                return 0
            else
                log "  File appeared but line count too low: ${lines}/${expected_lines} (${elapsed}s)..."
            fi
        else
            log "  Waiting... no new file yet (${elapsed}s)"
        fi
    done

    # After timeout, try any savedrecs file as fallback
    warn "Timeout (${timeout}s), searching for recently modified files..."
    local fallback
    fallback=$(ls -t "$OUTPUT_DIR"/savedrecs*.txt 2>/dev/null | head -1 || true)
    if [[ -n "$fallback" && -f "$fallback" ]]; then
        local lines
        lines=$(wc -l < "$fallback")
        log "  Fallback file found: $fallback (${lines} lines)"
        if [[ $lines -ge 2 ]]; then
            local dest="${TASK_DIR}/savedrecs_batch_${batch_num}.txt"
            mv "$fallback" "$dest"
            # Pad empty lines to expected count
            local missing=$((expected_lines - lines))
            if [[ $missing -gt 0 ]]; then
                printf '%0.s\n' $(seq 1 $missing) >> "$dest"
                warn "Using fallback file, padded ${missing} empty lines to ${expected_lines}"
            else
                warn "Using fallback file"
            fi
            LAST_DOWNLOADED_FILE="$dest"
            return 0
        fi
    fi

    # Non-last batch + timeout + no file → WOS results exhausted
    if [[ "$is_last_batch" == false ]]; then
        warn "Batch ${batch_num} returned no results, WOS results may be fully exported"
        warn "Terminating remaining batches early"
        # Set global flag for outer loop to exit early
        export WOS_EXPORT_DONE=1
    fi

    err "Download timed out, no valid file found"
    return 1
}

# ── Export a Single Batch ─────────────────────────────────────────────────
export_batch() {
    local batch_from="$1"
    local batch_to="$2"
    local batch_num="$3"

    log ""
    log "── Batch ${batch_num}/${TOTAL_BATCHES}: ${batch_from}-${batch_to} ──"

    # Check popups before each export
    check_and_clear_popups

    # Select option index based on content type
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

  // Handle browser download confirmation popup
  var downloadBubble = document.querySelector('#download-bubble, [id*=download-dialog]');
  if(downloadBubble){
    var alwaysBtn = downloadBubble.querySelector('button');
    if(alwaysBtn) alwaysBtn.click();
  }
  await new Promise(r => setTimeout(r, 500));

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
" 2>&1 | filter_opencli | grep -E "^From=" || true)

    if [[ -n "$result" ]]; then
        log "Export triggered: $result"
    else
        warn "No export confirmation received, continuing to wait for download..."
    fi

    # Record timestamp, then wait for download
    snapshot_pre_download
    local expected_lines=$(( batch_to - batch_from + 2 ))
    wait_for_download "$expected_lines" "$batch_num"
}

# ===================================================================
#  Main Flow
# ===================================================================

# Step 1: Open page / reuse window
if [[ "$REUSE" == true ]]; then
    log "Reusing current Chrome automation window..."
    current_url=$(opencli browser get url 2>&1 | filter_opencli_last)
    log "Current page: $current_url"
    if echo "$current_url" | grep -q "summary/"; then
        ok "Already on results page"
    else
        warn "Current page may not be a results page: $current_url"
        warn "Please ensure the Chrome automation window has a WOS results page open"
    fi
elif [[ -n "$QUERY" ]]; then
    # ── Advanced Search Mode ──
    log "Advanced search mode..."
    
    # Build full query string
    FULL_QUERY="$QUERY"
    if [[ -n "$YEAR_RANGE" ]]; then
        # Parse year range "2020-2026"
        YEAR_FROM=$(echo "$YEAR_RANGE" | cut -d'-' -f1)
        YEAR_TO=$(echo "$YEAR_RANGE" | cut -d'-' -f2)
        if [[ -n "$YEAR_FROM" && -n "$YEAR_TO" ]]; then
            FULL_QUERY="${FULL_QUERY} AND PY=(${YEAR_RANGE})"
            log "Full query: $FULL_QUERY"
        fi
    else
        log "Full query: $FULL_QUERY"
    fi
    
    # Open advanced search page
    opencli browser open "https://www.webofscience.com/wos/alldb/advanced-search" 2>&1 | filter_opencli || true
    opencli browser wait time 5 2>&1 | filter_opencli || true
    
    check_and_clear_popups
    
    # Dismiss cookie popup
    opencli browser eval "
(function(){
  var s = document.getElementById('onetrust-consent-sdk');
  if(s) s.remove();
  var a = document.querySelector('#onetrust-accept-btn-handler');
  if(a) a.click();
  return 'done';
})()" 2>&1 | filter_opencli || true
    
    # Find textarea index and input search query (use opencli browser type to avoid JS escaping)
    textarea_idx=$(opencli browser state 2>&1 | grep "advancedSearchInputArea" | grep -oP '\[\K[0-9]+' | head -1)
    log "Query textarea index: [$textarea_idx]"
    
    opencli browser type "$textarea_idx" "$FULL_QUERY" 2>&1 | filter_opencli || true
    
    # Press Enter to trigger search (WOS Search button is an Angular component, JS click() doesn't work, Enter key does)
    opencli browser keys Enter 2>&1 | filter_opencli || true
    
    log "Waiting for search results to load..."
    opencli browser wait time 10 2>&1 | filter_opencli || true
    
    current_url=$(opencli browser get url 2>&1 | filter_opencli_last)
    if echo "$current_url" | grep -q "summary/"; then
        ok "Results page loaded: $current_url"
    else
        warn "May not have navigated to results page: $current_url"
    fi
elif [[ -n "$URL" ]]; then
    log "Opening results page directly..."
    opencli browser open "$URL" 2>&1 | filter_opencli || true
    opencli browser wait time 8 2>&1 | filter_opencli || true

    current_url=$(opencli browser get url 2>&1 | filter_opencli_last)
    if echo "$current_url" | grep -q "summary/"; then
        ok "Results page loaded: $current_url"
    else
        warn "May not have navigated to results page: $current_url"
    fi
else
    log "Opening search page and entering keyword..."
    opencli browser open "https://www.webofscience.com/wos/woscc/basic-search" 2>&1 | filter_opencli || true
    opencli browser wait time 5 2>&1 | filter_opencli || true

    check_and_clear_popups

    # Clear search box
    opencli browser eval "document.getElementById('search-option-0').value=''; document.getElementById('search-option-0').dispatchEvent(new Event('input',{bubbles:true})); 'cleared'" 2>&1 | filter_opencli || true

    # Find search box and button indices
    search_box_idx=$(opencli browser state 2>&1 | grep -i "search-option-0" | grep -oP '\[\K[0-9]+' | head -1)
    search_btn_idx=$(opencli browser state 2>&1 | grep "type=submit" | grep -oP '\[\K[0-9]+' | head -1)

    log "Search box index: [$search_box_idx], Search button index: [$search_btn_idx]"

    opencli browser type "$search_box_idx" "$KEYWORD" 2>&1 | filter_opencli || true
    opencli browser click "$search_btn_idx" 2>&1 | filter_opencli || true

    log "Waiting for search results to load..."
    opencli browser wait time 10 2>&1 | filter_opencli || true

    current_url=$(opencli browser get url 2>&1 | filter_opencli_last)
    if echo "$current_url" | grep -q "summary/"; then
        ok "Results page loaded: $current_url"
    else
        warn "May not have navigated to results page: $current_url"
    fi
fi

# Step 1.5: Detect actual WOS result count, auto-adjust COUNT and batches
detect_result_count() {
    local count_text
    count_text=$(opencli browser eval "
(function(){
  // WOS result count exact match: X,XXX results from Web of Science
  // Search for the number before 'results from' in body text
  var bodyText = document.body.innerText;
  var m = bodyText.match(/(\\d[\\d,\\s]*)\\s+results\\s+from/i);
  if(m) return m[1].replace(/[,\\s]/g, '');
  // Fallback: try 'of X,XXX' format
  m = bodyText.match(/of\\s+(\\d[\\d,]+)/);
  if(m) return m[1].replace(/,/g, '');
  return '0';
})()" 2>/dev/null | filter_opencli | tail -1)
    
    # Strip non-numeric characters
    count_text=$(echo "$count_text" | grep -oP '\d+' | head -1)
    
    if [[ -n "$count_text" && "$count_text" -gt 0 ]] 2>/dev/null; then
        ok "WOS actual result count: ${count_text} records"
        if [[ $COUNT -gt $count_text ]]; then
            warn "You requested ${COUNT} records but only ${count_text} exist, auto-adjusted"
            COUNT=$count_text
        fi
        # Recalculate batches
        TOTAL_BATCHES=$(( (COUNT + BATCH_SIZE - 1) / BATCH_SIZE ))
        log "Adjusted: export $COUNT records, split into $TOTAL_BATCHES batches"
    else
        warn "Could not read WOS actual result count, proceeding with requested ${COUNT} records"
        log "(If actual results are fewer, the last batch will auto-pad empty lines)"
    fi
}

# Step 2: Loop export
declare -a DOWNLOADED_FILES=()

# First detect actual result count
detect_result_count

export WOS_EXPORT_DONE=0

for (( batch=0; batch<TOTAL_BATCHES; batch++ )); do
    # Check for early termination
    if [[ "$WOS_EXPORT_DONE" == "1" ]]; then
        warn "Early termination detected, skipping remaining batches"
        break
    fi

    batch_from=$(( batch * BATCH_SIZE + 1 ))
    batch_to=$(( (batch + 1) * BATCH_SIZE ))

    if [[ $batch_to -gt $COUNT ]]; then
        batch_to=$COUNT
    fi

    actual_size=$(( batch_to - batch_from + 1 ))
    log "This batch actual size: $actual_size records"

    export_batch "$batch_from" "$batch_to" $((batch + 1)) || true
    if [[ -n "$LAST_DOWNLOADED_FILE" ]]; then
        DOWNLOADED_FILES+=("$LAST_DOWNLOADED_FILE")
    fi

    # Pause between batches — use wait instead of sleep
    if [[ $((batch + 1)) -lt $TOTAL_BATCHES ]]; then
        log "Waiting 5 seconds between batches..."
        opencli browser wait time 5 2>&1 | filter_opencli || true
    fi
done

# Step 3: Merge
if [[ "$MERGE" == true && ${#DOWNLOADED_FILES[@]} -gt 0 ]]; then
    log ""
    log "── Merging Files ──"

    merge_file="${TASK_DIR}/merge.txt"

    log "Merging into: $merge_file"
    log "(original batch files preserved in task directory)"

    head -1 "${DOWNLOADED_FILES[0]}" > "$merge_file"
    for f in "${DOWNLOADED_FILES[@]}"; do
        tail -n +2 "$f" >> "$merge_file"
    done

    total_lines=$(wc -l < "$merge_file")
    total_size=$(du -h "$merge_file" | cut -f1)

    ok "Merge complete: $merge_file (${total_size}, ${total_lines} lines)"
    log "Expected lines: $((COUNT + 1)) (including header)"
    log "Original batch files preserved in: $TASK_DIR/"
fi

log ""
log "═══════════════════════════════════════════════════"
ok "All exports complete!"
log "═══════════════════════════════════════════════════"
