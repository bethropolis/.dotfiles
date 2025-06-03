#!/usr/bin/env bash
#
# Download anime from animepahe in terminal
#
#/ Usage:
#/   ./animepahe-dl.sh [-a <anime name>] [-s <anime_slug>] [-e <episode_selection>] [-r <resolution>] [-t <num>] [-l] [-d] [-T <secs>]
#/
#/ Options:
#/   -a <name>               anime name
#/   -s <slug>               anime slug/uuid, can be found in $_ANIME_LIST_FILE
#/                           ignored when "-a" is enabled
#/   -e <selection>          optional, episode selection string. Examples:
#/                           - Single: "1"
#/                           - Multiple: "1,3,5"
#/                           - Range: "1-5"
#/                           - All: "*"
#/                           - Exclude: "*,!1,!10-12" (all except 1 and 10-12)
#/                           - Latest N: "L3" (latest 3 available)
#/                           - First N: "F5" (first 5 available)
#/                           - From N: "10-" (episode 10 to last available)
#/                           - Up to N: "-5" (episode 1 to 5)
#/                           - Combined: "1-10,!5,L2" (1-10 except 5, plus latest 2)
#/   -r <resolution>         optional, specify resolution: "1080", "720"...
#/                           by default, the highest resolution is selected
#/   -o <language>           optional, specify audio language: "eng", "jpn"
#/   -t <num>                optional, specify a positive integer as num of threads (default: 4)
#/   -T <secs>               optional, add timeout in seconds for individual segment download jobs.
#/                           Requires GNU Parallel.
#/   -l                      optional, show m3u8 playlist link without downloading videos
#/   -d                      enable debug mode
#/   -h | --help             display this help message

# --- Configuration ---
set -e
set -u

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Check for terminal compatibility with colors
if ! [ -t 1 ]; then
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  PURPLE=''
  CYAN=''
  BOLD=''
  NC=''
fi

# --- Global Variables ---
_SCRIPT_NAME="$(basename "$0")"
_ANIME_NAME="unknown_anime" # Default, will be overwritten
_SEGMENT_TIMEOUT="360"         # Default timeout is disabled
_ALLOW_NOTIFICATION="${ANIMEPAHE_DOWNLOAD_NOTIFICATION:-false}" # Allow notifications, defaults to false
_NOTIFICATION_URG="normal" # Default notification urgency

# --- Trap Function ---
cleanup() {
  echo -e "${YELLOW}ℹ Cleaning up temporary files...${NC}" >&2
  # Simpler pattern matching only PID and XXXXXX suffix
  local tmp_pattern="ep*_*.${$}.XXXXXX"

  # Search within the main video directory
  find "${_VIDEO_DIR_PATH:-$HOME/Videos}" -maxdepth 3 -path "*/*/*" -type d -name "$tmp_pattern" -prune -exec rm -rf {} + 2>/dev/null
  # Also check /tmp just in case mktemp defaulted there (unlikely with current script but safe)
  find /tmp -maxdepth 1 -type d -name "$tmp_pattern" -prune -exec rm -rf {} + 2>/dev/null
}

# run cleanup on exit or interrupt
trap cleanup EXIT SIGINT SIGTERM

# --- Helper Functions ---
usage() {
  # $0: script name
  printf "%b\n" "$(grep '^#/' "$0" | cut -c4-)"

  # Unset the EXIT trap to prevent cleanup when displaying help
  trap - EXIT
  exit 1
}

print_info() {
  # ℹ Symbol for info
  [[ -z "${_LIST_LINK_ONLY:-}" ]] && printf "%b\n" "${GREEN}ℹ ${NC}$1" >&2
}

print_warn() {
  # ⚠ Symbol for warning
  [[ -z "${_LIST_LINK_ONLY:-}" ]] && printf "%b\n" "${YELLOW}⚠ WARNING: ${NC}$1" >&2
}

print_error() {
  # ✘ Symbol for error
  printf "%b\n" "${RED}✘ ERROR: ${NC}$1" >&2
  exit 1
}

command_not_found() {
  print_error "$1 command not found! Please install it."
}

set_var() {
  print_info "Checking required tools..."
  _CURL="$(command -v curl)" || command_not_found "curl"
  _JQ="$(command -v jq)" || command_not_found "jq"
  _FZF="$(command -v fzf)" || command_not_found "fzf"
  if [[ -z ${ANIMEPAHE_DL_NODE:-} ]]; then
    _NODE="$(command -v node)" || command_not_found "node"
  else
    _NODE="$ANIMEPAHE_DL_NODE"
  fi
  _FFMPEG="$(command -v ffmpeg)" || command_not_found "ffmpeg"
  _OPENSSL="$(command -v openssl)" || command_not_found "openssl"
  _NOTIFICATION_CMD="$(command -v notify-send)" || print_warn "notify-send"
  # Check for GNU Parallel
  _PARALLEL="$(command -v parallel)" || command_not_found "parallel (GNU Parallel)"
  _MKTEMP="$(command -v mktemp)" || command_not_found "mktemp"
  print_info "${GREEN}✓ All tools found.${NC}"

  _HOST="https://animepahe.ru"
  _ANIME_URL="$_HOST/anime"
  _API_URL="$_HOST/api"
  _REFERER_URL="$_HOST"

  _VIDEO_DIR_PATH="${ANIMEPAHE_VIDEO_DIR:-$HOME/Videos}"
  _ANIME_LIST_FILE="${ANIMEPAHE_LIST_FILE:-$_VIDEO_DIR_PATH/anime.list}"
  _SOURCE_FILE=".source.json" # Relative to anime-specific directory

  print_info "Creating video directory if needed: ${BOLD}${_VIDEO_DIR_PATH}${NC}"
  mkdir -p "$_VIDEO_DIR_PATH" || print_error "Cannot create video directory: ${_VIDEO_DIR_PATH}"
}

set_args() {
  expr "$*" : ".*--help" >/dev/null && usage
  _PARALLEL_JOBS=4                           # Default number of threads/jobs
  while getopts ":hlda:s:e:r:t:o:T:" opt; do # Added T:
    case $opt in
    a) _INPUT_ANIME_NAME="$OPTARG" ;;
    s) _ANIME_SLUG="$OPTARG" ;;
    e) _ANIME_EPISODE="$OPTARG" ;;
    l) _LIST_LINK_ONLY=true ;;
    r) _ANIME_RESOLUTION="$OPTARG" ;;
    t)
      _PARALLEL_JOBS="$OPTARG"
      if [[ ! "$_PARALLEL_JOBS" =~ ^[1-9][0-9]*$ ]]; then # Must be 1 or more
        print_error "-t <num>: Number must be a positive integer."
      fi
      ;;
    o) _ANIME_AUDIO="$OPTARG" ;;
    T) # New Timeout Option
      _SEGMENT_TIMEOUT="$OPTARG"
      # Basic validation: check if positive integer
      if [[ ! "$_SEGMENT_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
        print_error "-T <secs>: Timeout must be a positive integer (seconds)."
      fi
      print_info "${YELLOW}Segment download job timeout set to: ${_SEGMENT_TIMEOUT}s${NC}"
      ;;
    d)
      _DEBUG_MODE=true
      print_info "${YELLOW}Debug mode enabled.${NC}"
      set -x
      ;;
    h) usage ;;
    \?) print_error "Invalid option: -$OPTARG" ;;
    esac
  done
}

get() {
  # Use curl with error checking (download_file handles retries better)
  local output
  output="$("$_CURL" -sS -L --fail "$1" -H "cookie: $_COOKIE" --compressed)"
  if [[ $? -ne 0 ]]; then
    print_warn "Failed to get URL: $1"
    return 1
  fi
  echo "$output"
}

set_cookie() {
  local u
  u="$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 16)"
  _COOKIE="__ddg2_=$u"
  print_info "Set temporary session cookie."
}

set_title() {
  # $1: title
  local title="$1"
  # \033]0;…\007  → ESC ]0; … BEL
  printf "\033]0;%s\007" "$title"
}

send_notification() {
  # $1: Title
  # $2: Body message
  # $3: Urgency (low, normal, critical) - optional, defaults to normal


  if ! command -v "$_NOTIFICATION_CMD" &> /dev/null; then
    return 0
  fi

  local title="${1}"
  local body="${2}"
  local urgency="${3:-$_NOTIFICATION_URG}"

  "$_NOTIFICATION_CMD" -u "$urgency" -i "folder-download-symbolic"  -a "animepahe downloader" "$title" "$body"
}

download_anime_list() {
  print_info "${YELLOW}⟳ Retrieving master anime list...${NC}"
  local content
  content=$(get "$_ANIME_URL") || {
    print_error "Failed getting master list from $_ANIME_URL"
    return 1
  }

  echo "$content" |
    grep "/anime/" |
    sed -E 's/.*anime\//[/;s/" title="/] /;s/\">.*/   /;s/" title/]/' \
      >"$_ANIME_LIST_FILE"

  if [[ $? -eq 0 && -s "$_ANIME_LIST_FILE" ]]; then
    local count
    count=$(wc -l <"$_ANIME_LIST_FILE")
    print_info "${GREEN}✓ Successfully saved ${BOLD}$count${NC}${GREEN} titles to ${BOLD}$_ANIME_LIST_FILE${NC}"
  else
    rm -f "$_ANIME_LIST_FILE" # Remove empty/failed file
    print_error "Failed to parse or save master anime list."
  fi
}

search_anime_by_name() {
  print_info "${YELLOW}⟳ Searching API for anime matching '${BOLD}$1${NC}'...${NC}"
  local d n query
  # URL encode the search query
  query=$(printf %s "$1" | jq -sRr @uri)
  d=$(get "$_HOST/api?m=search&q=${query}") || return 1
  n=$("$_JQ" -r '.total' <<<"$d")

  if [[ "$n" == "null" || "$n" -eq "0" ]]; then
    print_warn "No results found via API for '$1'."
    echo "" # Return empty string
  else
    print_info "${GREEN}✓ Found ${BOLD}$n${NC}${GREEN} potential matches.${NC}"
    # Extract, format, save to list, and return just the title for fzf
    "$_JQ" -r '.data[] | "[\(.session)] \(.title)   "' <<<"$d" |
      tee -a "$_ANIME_LIST_FILE" |
      sort -u -o "$_ANIME_LIST_FILE"{,} # Ensure list is unique after adding

    # Return full formatted lines for fzf, not just titles
    "$_JQ" -r '.data[] | "[\(.session)] \(.title)   "' <<<"$d"
  fi
}

get_episode_list() {
  # $1: anime id (slug)
  # $2: page number
  get "${_API_URL}?m=release&id=${1}&sort=episode_asc&page=${2}"
}

download_source() {
  # $1: anime slug
  # $2: anime name (for source file path)
  local anime_slug="$1"
  local anime_name="$2" # Use the global _ANIME_NAME
  local source_path="$_VIDEO_DIR_PATH/$anime_name/$_SOURCE_FILE"

  print_info "${YELLOW}⟳ Downloading episode list for ${BOLD}$anime_name${NC}...${NC}"
  mkdir -p "$_VIDEO_DIR_PATH/$anime_name" # Ensure directory exists

  local d p n i current_page last_page json_data=()
  current_page=1

  while true; do
    print_info "  Fetching page ${BOLD}$current_page${NC}..."
    d=$(get_episode_list "$anime_slug" "$current_page")
    if [[ $? -ne 0 || -z "$d" || "$d" == "null" ]]; then
      # Handle case where first page fails vs subsequent pages
      if [[ $current_page -eq 1 ]]; then
        print_error "Failed to get first page of episode list."
      else
        print_warn "Failed to get page $current_page, proceeding with downloaded data."
        break # Exit loop, use what we have
      fi
    fi

    # Check if data is valid JSON and has expected structure
    if ! echo "$d" | "$_JQ" -e '.data' >/dev/null; then
      if [[ $current_page -eq 1 ]]; then
        print_error "Invalid data received on first page of episode list."
      else
        print_warn "Invalid data received on page $current_page, proceeding with downloaded data."
        break
      fi
    fi

    # Add current page data to our array
    json_data+=("$(echo "$d" | "$_JQ" -c '.data')") # Store as compact JSON strings

    # Get last page number only once
    [[ -z ${last_page:-} ]] && last_page=$("$_JQ" -r '.last_page // 1' <<<"$d")

    if [[ $current_page -ge $last_page ]]; then
      break # Exit loop if we've reached the last page
    fi
    current_page=$((current_page + 1))
    sleep 0.5 # Small delay between page requests
  done

  # Combine all collected JSON data arrays into a single JSON object
  local combined_json
  # Use jq's slurp (-s) and map/add to merge the arrays inside {data: ...}
  combined_json=$(printf '%s\n' "${json_data[@]}" | "$_JQ" -s 'map(.[]) | {data: .}')

  # Save the combined data
  echo "$combined_json" >"$source_path"

  if [[ $? -eq 0 && -s "$source_path" ]]; then
    local ep_count
    ep_count=$(echo "$combined_json" | "$_JQ" -r '.data | length')
    print_info "${GREEN}✓ Successfully downloaded source info for ${BOLD}$ep_count${NC}${GREEN} episodes to ${BOLD}$source_path${NC}"
  else
    rm -f "$source_path"
    print_error "Failed to save episode source file."
  fi
}

get_episode_link() {
  # $1: episode number
  local num="$1"
  local session_id play_page_content play_url
  local all_options

  print_info "  Looking up session ID for episode ${BOLD}$num${NC}..."
  session_id=$("$_JQ" -r --argjson num "$num" '.data[] | select(.episode == $num) | .session // empty' <"$_VIDEO_DIR_PATH/$_ANIME_NAME/$_SOURCE_FILE")
  if [[ -z "$session_id" ]]; then
    print_warn "Episode $num session ID not found in source file!"
    return 1
  fi

  play_url="${_HOST}/play/${_ANIME_SLUG}/${session_id}"
  print_info "  Fetching play page to find stream sources: ${BOLD}$play_url${NC}"
  play_page_content=$("$_CURL" --compressed -sSL --fail -H "cookie: $_COOKIE" -H "Referer: $_REFERER_URL" "$play_url")
  if [[ $? -ne 0 || -z "$play_page_content" ]]; then
    print_warn "Failed to fetch play page content for episode $num."
    return 1
  fi
  [[ -n "${_DEBUG_MODE:-}" ]] && echo "$play_page_content" >"$_VIDEO_DIR_PATH/$_ANIME_NAME/play_page_${num}.html"

  print_info "  Extracting stream options from play page..."
  # --- NEW PARSING LOGIC ---
  all_options=$(echo "$play_page_content" |
    grep '<button' | grep 'data-src' | grep 'data-av1="0"' |
    # Split into individual button tags with non-AV1 streams
    grep -oP '<button[^>]*data-av1="0"[^>]*>' |
    # Extract resolution, audio, and src from each tag
    awk '{
      if (match($0, /data-resolution="([^"]+)"/, r) &&
        match($0, /data-audio="([^"]+)"/, a) &&
        match($0, /data-src="([^"]+)"/, s))
      print r[1], a[1], s[1]
    }')

  if [[ -z "$all_options" ]]; then
    print_warn "No suitable stream options (non-AV1) found on play page for episode $num."
    return 1
  fi

  #  debug
  [[ -n "${_DEBUG_MODE:-}" ]] && echo "$all_options" >"$_VIDEO_DIR_PATH/$_ANIME_NAME/stream_options_${num}.txt"

  local option_count
  option_count=$(echo "$all_options" | wc -l)
  print_info "    Found ${option_count} potential stream options."

  # --- NEW FILTERING & SELECTION LOGIC ---
  local candidates="$all_options"

  # 1. Filter by Audio Language (_ANIME_AUDIO / -o)
  if [[ -n "${_ANIME_AUDIO:-}" ]]; then
    print_info "  Filtering for audio language: ${BOLD}${_ANIME_AUDIO}${NC}"
    local audio_filtered
    # Use awk for filtering the structured data
    audio_filtered=$(echo "$candidates" | awk -v aud="$_ANIME_AUDIO" '$2 == aud')
    if [[ -z "$audio_filtered" ]]; then
      print_warn "Selected audio language '${_ANIME_AUDIO}' not available. Proceeding without audio filter."
      # Keep $candidates as is
    else
      print_info "    ${GREEN}✓ Audio language filter applied.${NC}"
      candidates="$audio_filtered" # Update the set of candidates
    fi
  fi

  # 2. Filter by Resolution (_ANIME_RESOLUTION / -r) OR Select Best Available
  local final_choice=""
  if [[ -n "${_ANIME_RESOLUTION:-}" ]]; then
    print_info "  Attempting to select resolution: ${BOLD}${_ANIME_RESOLUTION}p${NC}"
    local res_filtered
    # Use awk to filter the remaining candidates by resolution
    res_filtered=$(echo "$candidates" | awk -v res="$_ANIME_RESOLUTION" '$1 == res')

    if [[ -z "$res_filtered" ]]; then
      print_warn "Selected resolution '${_ANIME_RESOLUTION}p' not available with current filters."
      # Fallthrough to select the best available from $candidates
    else
      print_info "    ${GREEN}✓ Specific resolution found.${NC}"
      # Since resolution was specified and found, take the first match
      # (should only be one if audio was also specified and matched)
      final_choice=$(echo "$res_filtered" | head -n 1)
    fi
  fi

  # 3. If no specific resolution was chosen yet, select the highest available
  if [[ -z "$final_choice" ]]; then
    if [[ -z "$candidates" ]]; then
      # This happens if filtering removed all options
      print_warn "No stream options remain after filtering."
      return 1
    fi
    print_info "  Selecting highest available resolution from remaining candidates..."
    # Sort remaining candidates numerically descending by resolution (field 1)
    # and take the first one
    final_choice=$(echo "$candidates" | sort -k1,1nr | head -n 1)
  fi

  # 4. Extract data from the final chosen line
  if [[ -z "$final_choice" ]]; then
    print_warn "Could not determine a final stream URL."
    return 1
  fi

  # Use read to parse the chosen line (res aud src)
  local final_res final_audio final_link
  read -r final_res final_audio final_link <<<"$final_choice"

  if [[ -z "$final_link" ]]; then
    # Should not happen if final_choice was set, but check anyway
    print_warn "Failed to extract final URL from chosen option: [$final_choice]"
    return 1
  fi

  print_info "    Selected stream (Res: ${final_res:-N/A}p, Audio: ${final_audio:-N/A}): ${BOLD}$final_link${NC}"
  echo "$final_link" # Output the final link
  return 0
}

get_playlist_link() {
  # $1: episode stream link (e.g., kwik URL)
  local stream_link="$1"
  local s l

  print_info "    Fetching stream page: ${BOLD}${stream_link}${NC}"
  s="$("$_CURL" --compressed -sS -H "Referer: $_REFERER_URL" -H "cookie: $_COOKIE" "$stream_link")"
  if [[ $? -ne 0 ]]; then
    print_warn "Failed to get stream page content from $stream_link"
    return 1
  fi

  print_info "    Extracting packed Javascript..."
  s="$(echo "$s" |
    grep "<script>eval(" |
    head -n 1 |
    awk -F 'script>' '{print $2}' |
    sed -E 's/<\/script>//' |
    sed -E 's/document/process/g' |
    sed -E 's/querySelector/exit/g' |
    sed -E 's/eval\(/console.log\(/g')"
  if [[ -z "$s" ]]; then
    print_warn "Could not extract packed JS block from stream page."
    return 1
  fi

  print_info "    Executing JS with node.js to find m3u8 URL..."
  l="$("$_NODE" -e "$s" 2>/dev/null |
    grep 'source=' |
    head -n 1 |
    sed -E "s/.m3u8['\"].*/.m3u8/" |
    sed -E "s/.*['\"](https:.*)/\1/")" # More robust extraction

  if [[ -z "$l" || "$l" != *.m3u8 ]]; then
    print_warn "Failed to extract m3u8 link using node.js."
    return 1
  fi

  print_info "    ${GREEN}✓ Found playlist URL.${NC}"
  echo "$l"
  return 0
}

download_file() {
  # ARG 1: URL ($1)
  # ARG 2: Outfile ($2) - THIS IS THE FULL PATH TO SAVE TO
  # ARG 3: MaxRetries ($3, optional default 3)
  # ARG 4: InitialDelay ($4, optional default 2)
  # Uses ENVIRONMENT: _CURL, _REFERER_URL, _COOKIE

  local url="$1"
  local outfile="$2"
  local max_retries=${3:-3}
  local initial_delay=${4:-2}
  local attempt=0 delay=$initial_delay s=0

  # --- REMOVED THE INTERNAL PATH CONSTRUCTION BLOCK ---

  # Only create a filename if outfile is empty (which it shouldn't be btw)
  if [[ -z "$outfile" ]]; then
    # Use parameter expansion instead of sed for better performance
    local filename=${url##*/} # Remove everything before last /
    filename=${filename%%\?*} # Remove query string if present
    filename=${filename%%\#*} # Remove fragment if present

    # Use direct parameter expansion instead of conditional check + assignment
    outfile="${opath:-.}/${filename}.encrypted"
    [[ "$opath" == "." ]] && print_warn "Output path (opath) is not set. Using current directory."
  fi

  # Use the BASENAME of the PASSED outfile path ($2) for messages
  local display_filename=$(basename "$outfile")

  # Debug print - Shows the arguments as received
  # print_warn "DEBUG inside download_file: url='$url' outfile='$outfile' retries='$max_retries' delay='$initial_delay'"

  while [[ $attempt -lt $max_retries ]]; do
    attempt=$((attempt + 1))

    local curl_stderr
    curl_stderr=$({
      # Use the passed 'outfile' variable ($2)
      "$_CURL" --fail -sS -H "Referer: $_REFERER_URL" -H "cookie: $_COOKIE" -C - "$url" -L -g \
        --connect-timeout 10 \
        --retry 2 --retry-delay 1 \
        --compressed \
        -o "$outfile"
      s=$?
    } 2>&1 >/dev/null)

    if [[ "$s" -eq 0 ]]; then
      if [[ -s "$outfile" ]]; then
        return 0 # Success :)
      else
        print_warn "      Download succeeded (curl code 0) but output file is empty/missing: ${BOLD}${display_filename}${NC}"
        s=99
      fi
    fi

    if [[ $attempt -lt $max_retries ]]; then
      print_warn "      Download attempt $attempt/$max_retries failed (curl code: $s) for ${display_filename}. Retrying in $delay seconds..."
    fi
    rm -f "$outfile"
    sleep "$delay"
    delay=$((delay * 2))
  done

  print_warn "Download failed after $max_retries attempts for ${display_filename} ($url)"
  rm -f "$outfile"
  return 1
}

decrypt_file() {
  local encrypted_file="$1"
  local key_hex="$2"
  local of=${encrypted_file%%.encrypted}

  # Ensure output directory exists (though should be created by mktemp)
  mkdir -p "$(dirname "$of")"

  # Run openssl, capture stderr for better error reporting
  local openssl_output
  openssl_output=$("$_OPENSSL" aes-128-cbc -d -K "$key_hex" -iv 0 -in "$encrypted_file" -out "$of" 2>&1)
  if [[ $? -ne 0 ]]; then
    print_warn "Openssl decryption failed for $(basename "$encrypted_file"): $openssl_output"
    rm -f "$of" # Remove potentially corrupt output file (clean up deletes everything when this happens anyway but why not)
    return 1
  fi
  # Optional: Add a verbose log for successful decryption if needed
  # print_info "      ${GREEN}✓ Decrypted: ${BOLD}$(basename "$of")${NC}"
  return 0
}

decrypt_segments() {
  local playlist_file="$1" segment_path="$2" threads="$3"
  local kf kl k encrypted_files=() total_encrypted

  kf="${segment_path}/mon.key" # Define the mon.key file path

  print_info "  Checking playlist for encryption key..."
  # Extract the key URI FIRST
  kl=$(grep "#EXT-X-KEY:METHOD=AES-128" "$playlist_file" | head -n 1 | awk -F 'URI="' '{print $2}' | awk -F '"' '{print $1}')

  # Check if encryption is actually used BEFORE trying to download the key
  if [[ -z "$kl" ]]; then
    print_info "  Playlist indicates stream is not encrypted (No AES-128 key URI found). Skipping decryption."
    # Optional: Check if any .encrypted files exist unexpectedly
    mapfile -t encrypted_files < <(find "$segment_path" -maxdepth 1 -name '*.encrypted' -print 2>/dev/null) # Avoid error if none found
    if [[ ${#encrypted_files[@]} -gt 0 ]]; then
      print_warn "    Playlist shows no encryption, but ${#encrypted_files[@]} *.encrypted files found! Check playlist/downloads."
      # Decide whether to proceed or error out. Let's proceed but warn.
    fi
    return 0 # Success (nothing to decrypt)
  fi

  # --- If we reach here, kl is NOT empty ---
  print_info "  Stream appears encrypted. Downloading key: ${BOLD}$kl${NC}"
  download_file "$kl" "$kf" || {
    print_warn "Failed to download encryption key for this episode: $kl"
    return 1
  } # Use warn + return 1

  # Extract the key hex
  k="$(od -A n -t x1 "$kf" | tr -d ' \n')"
  if [[ -z "$k" ]]; then
    print_warn "Failed to extract encryption key hex for this episode from $kf" # Use warn
    rm -f "$kf"                                                                 # Clean up useless key file
    return 1                                                                    # Return failure
  fi

  # Find encrypted files
  mapfile -t encrypted_files < <(find "$segment_path" -maxdepth 1 -name '*.encrypted' -print)
  total_encrypted=${#encrypted_files[@]}

  if [[ $total_encrypted -eq 0 ]]; then
    # This case means playlist specified a key, but download_segments didn't create .encrypted files (or they were removed)
    print_warn "No *.encrypted files found to decrypt in $segment_path, although playlist specified a key."
    rm -f "$kf" # Clean up key file as it's not needed
    return 0    # Consider it success as there's nothing to do
  fi

  print_info "  Decrypting ${BOLD}$total_encrypted${NC} segments using ${BOLD}$threads${NC} thread(s) via GNU Parallel..."
  # Export only what decrypt_file needs
  export -f decrypt_file print_warn print_info
  export _OPENSSL k                            # Export key hex

  local parallel_opts_decrypt=()
  parallel_opts_decrypt+=("--jobs" "$threads")
  parallel_opts_decrypt+=("--eta")
  # Use specific env passing
  parallel_opts_decrypt+=(--env decrypt_file --env print_warn --env print_info --env _OPENSSL --env k)

  # --- Run GNU Parallel for Decryption ---
  printf '%s\n' "${encrypted_files[@]}" |
    "$_PARALLEL" "${parallel_opts_decrypt[@]}" -- decrypt_file {} "$k" # Pass key hex as arg $2 to decrypt_file

  local parallel_decrypt_status=$?
  # --- End Parallel Decryption ---

  if [[ $parallel_decrypt_status -ne 0 ]]; then
    print_warn "Segment decryption process failed (GNU Parallel status $parallel_decrypt_status)."
    local decrypted_count
    decrypted_count=$(find "$segment_path" -maxdepth 1 -type f ! -name '*.encrypted' ! -name 'mon.key' ! -name 'playlist.m3u8' ! -name 'file.list' | wc -l)
    print_warn "  Attempted: ${total_encrypted}, Successfully decrypted: ${decrypted_count}"
    if [[ -z "${_DEBUG_MODE:-}" ]]; then rm -f "$kf"; fi
    return 1
  fi

  # Verify count after success
  local decrypted_count
  decrypted_count=$(find "$segment_path" -maxdepth 1 -type f ! -name '*.encrypted' ! -name 'mon.key' ! -name 'playlist.m3u8' ! -name 'file.list' | wc -l)
  if [[ $total_encrypted -ne $decrypted_count ]]; then
    print_warn "Number of decrypted files ($decrypted_count) does not match number of encrypted files ($total_encrypted)."
    # return 1 # shouldn't be that strict, but could be useful for debugging
  fi

  print_info "  ${GREEN}✓ Decryption phase complete.${NC}"

  # Cleanup key and encrypted files if not in debug mode
  if [[ -z "${_DEBUG_MODE:-}" ]]; then
    print_info "  Cleaning up key file and encrypted segments..."
    rm -f "$kf"
    # Can still use xargs for simple parallel rm, or just rm directly if quick enough
    printf '%s\n' "${encrypted_files[@]}" | xargs -P "$threads" rm -f
  fi
  return 0
}

download_segments() {
  # Uses environment variables: plist, opath, threads, _CURL, _REFERER_URL, _COOKIE
  # Needs exported functions: download_file, print_info, print_warn, print_error
  # Also uses global _SEGMENT_TIMEOUT if set by -T flag

  local segment_urls=()
  local retval=0

  mapfile -t segment_urls < <(grep "^https" "$plist")
  local total_segments=${#segment_urls[@]}
  if [[ $total_segments -eq 0 ]]; then
    print_warn "No segment URLs found in playlist: $plist"
    return 1
  fi

  print_info "  Downloading ${BOLD}$total_segments${NC} segments using ${BOLD}$threads${NC} thread(s) via GNU Parallel."

  local parallel_opts=()
  parallel_opts+=("--jobs" "$threads")
  parallel_opts+=("--bar")
  parallel_opts+=("--quote")

  if [[ -n "${_SEGMENT_TIMEOUT:-}" ]]; then
    print_info "    (Individual download job timeout: ${_SEGMENT_TIMEOUT}s)"
    parallel_opts+=("--timeout" "${_SEGMENT_TIMEOUT}s")
  fi

  # Export function and variables needed DIRECTLY by the parallel JOB
  export -f download_file print_info print_warn print_error
  export _CURL _REFERER_URL _COOKIE opath # _PV is not needed inside download_file

  # --- Run GNU Parallel ---
  # Explicitly pass necessary env vars/funcs
  # SIMPLIFIED COMMAND STRING: Just call download_file with the URL {}
  printf '%s\n' "${segment_urls[@]}" |
    "$_PARALLEL" "${parallel_opts[@]}" \
      --env download_file --env print_info --env print_warn --env print_error \
      --env _CURL --env _REFERER_URL --env _COOKIE --env opath \
      -- download_file {}

  local parallel_status=$?

  # --- Check Exit Status (Same as before) ---
  if [[ $parallel_status -ne 0 ]]; then
    print_warn "GNU Parallel reported errors or timeouts during segment download (exit status: $parallel_status)."
    retval=1
  fi

  # --- Final Check: Segment Count (Same as before) ---
  local final_download_count
  final_download_count=$(find "$opath" -maxdepth 1 -name '*.encrypted' -print 2>/dev/null | wc -l)
  if [[ "$final_download_count" -ne "$total_segments" ]]; then
    [[ $retval -eq 0 ]] && print_warn "Segment count mismatch after parallel finished. Expected $total_segments, found $final_download_count."
    retval=1
  elif [[ $retval -eq 0 ]]; then
    print_info "  ${GREEN}✓ Segment download phase complete (GNU Parallel).${NC}"
  fi

  # Final reporting on failure (Same as before)
  if [[ $retval -ne 0 ]]; then
    local downloaded_count
    downloaded_count=$(find "$opath" -maxdepth 1 -name '*.encrypted' -print 2>/dev/null | wc -l)
    print_warn "  Failed State -> Expected: ${total_segments}, Actually Downloaded: ${downloaded_count}"
  fi

  return $retval
}

generate_filelist() {
  # $1: playlist file (source for segment names)
  # $2: output file list path
  local playlist_file="$1" outfile="$2" opath
  opath=$(dirname "$outfile") # Get directory path

  print_info "  Generating file list for ffmpeg..."
  # Modify segment URLs from playlist to point to *decrypted* local files
  grep "^https" "$playlist_file" |
    sed -E "s/^https.*\///" |
    # Improved regex to handle various segment extensions and potential query strings
    sed -E 's/(\.(ts|jpg|mp4|m4s|aac))(\?.*|#.*)?$/\1/' |
    sed -E "s/^/file '/" |
    sed -E "s/$/'/" \
      >"$outfile"

  # Check if file list was created and is not empty
  if [[ ! -s "$outfile" ]]; then
    print_warn "Failed to generate or generated empty file list for this episode: $outfile"
    return 1
  fi

  # Verify that the files listed actually exist (decrypted)
  local missing_files=0
  local missing_list=() # Optional: list missing files
  while IFS= read -r line; do
    local segment_file="${line#file \'}"
    segment_file="${segment_file%\'}"
    # Check if the expected decrypted file exists
    if [[ ! -f "${opath}/${segment_file}" ]]; then
      print_warn "    File listed in $(basename "$outfile") not found: ${segment_file}"
      missing_files=$((missing_files + 1))
      # missing_list+=("$segment_file") # Uncomment to collect list
    fi
  done <"$outfile"

  # Check the total count of missing files
  if [[ $missing_files -gt 0 ]]; then
    print_warn "$missing_files segment file(s) listed in $(basename "$outfile") are missing on disk for this episode!"
    return 1
  fi

  print_info "  ${GREEN}✓ File list generated: ${BOLD}$outfile${NC}"
  return 0
}

# --- Main Download Function ---
download_episode() {
  local num="$1"                        # Episode number string
  local v                               # Target video file path
  local l                               # Episode page link (kwik)
  local pl                              # m3u8 playlist link
  local erropt=''                       # ffmpeg error level option
  local opath plist cpath fname threads # Temporary directory variables
  local retval=0                        # Track success/failure

  # Define target path early for checking existence
  v="$_VIDEO_DIR_PATH/$_ANIME_NAME/${num}.mp4"

  # Check if file already exists
  if [[ -f "$v" ]]; then
    print_info "${GREEN}✓ Episode ${BOLD}$num ($v)${NC}${GREEN} already exists. Skipping.${NC}"
    return 0 # Success (already done)
  fi

  # --- Get Links ---
  print_info "Processing Episode ${BOLD}$num${NC}:"
  l=$(get_episode_link "$num") || return 1
  print_info "  Found stream page link: ${BOLD}$l${NC}"

  pl=$(get_playlist_link "$l") || return 1
  print_info "  Found playlist URL: ${BOLD}$pl${NC}"

  # Handle -l option (list link only)
  if [[ -n "${_LIST_LINK_ONLY:-}" ]]; then
    echo "$pl" # Print the link
    return 0   # Success for this mode
  fi

  # --- Prepare for Download ---
  set_title "⏳ $_ANIME_NAME - Episode $num" # Set terminal title
  print_info "Starting download process for Episode ${BOLD}$num${NC}..."

  [[ -z "${_DEBUG_MODE:-}" ]] && erropt="-v error"

  fname="file.list"
  cpath="$(pwd)" # Save current directory (might not be needed if using absolute paths)

  # Create unique temporary directory using mktemp
  opath=$("$_MKTEMP" -d "$_VIDEO_DIR_PATH/$_ANIME_NAME/ep${num}_${$}_XXXXXX")
  if [[ ! -d "$opath" ]]; then
    print_warn "Failed to create temporary directory for episode $num: Check permissions and path."
    return 1
  fi
  print_info "  Created temporary directory: ${BOLD}$opath${NC}"
  plist="${opath}/playlist.m3u8"

  # --- Download & Process Segments ---
  print_info "  Downloading master playlist..."
  # Pass URL, Outfile, Retries (3), Delay (2) EXPLICITLY
  download_file "$pl" "$plist" 3 2 || retval=1

  # Assign the value for 'threads' which download_segments will use from environment
  threads="$_PARALLEL_JOBS"

  if [[ $retval -eq 0 ]]; then
    print_info "  ${CYAN}--- Segment Download Phase ---${NC}"

    # Export environment needed by download_segments AND its jobs
    export -f download_segments download_file print_info print_warn print_error
    # Export necessary variables BY NAME. _PV is no longer needed here.
    export _CURL _REFERER_URL _COOKIE opath plist threads

    # Call download_segments directly
    download_segments || retval=1
  fi

  # The rest of the function proceeds based on the 'retval' flag
  if [[ $retval -eq 0 ]]; then
    set_title "🔑  $_ANIME_NAME - Episode $num - Decrypting"
    print_info "  ${CYAN}--- Segment Decryption Phase ---${NC}"
    # Pass threads explicitly as it's used for parallel decryption jobs
    decrypt_segments "$plist" "$opath" "$threads" || retval=1
  fi

  if [[ $retval -eq 0 ]]; then
    print_info "  ${CYAN}--- File List Generation ---${NC}"
    generate_filelist "$plist" "${opath}/$fname" || retval=1
  fi

  # --- Concatenate ---
  if [[ $retval -eq 0 ]]; then
    set_title "🔗  $_ANIME_NAME - Episode $num - Concatenating"
    print_info "  ${CYAN}--- Concatenation Phase ---${NC}"
    ( # Start Subshell
      cd "$opath" || {
        print_warn "Cannot change directory to temp path $opath" >&2
        exit 1
      }
      print_info "  Running ffmpeg to combine segments into ${BOLD}$v${NC} ..." >&2

      local ffmpeg_output
      if ! ffmpeg_output=$("$_FFMPEG" -f concat -safe 0 -i "$fname" -c copy $erropt -y "$v" 2>&1); then
        print_warn "ffmpeg concatenation failed for episode $num." >&2
        print_info "ffmpeg output:" >&2
        echo "$ffmpeg_output" | sed 's/^/    /' >&2
        exit 1 # Exit subshell with failure
      fi
      exit 0 # Success
    )        # End Subshell
    local subshell_status=$?
    if [[ $subshell_status -ne 0 ]]; then
      retval=1
      # Warning already printed in subshell
      rm -f "$v"
    fi
  fi

  # --- Cleanup and Return ---
  if [[ $retval -ne 0 ]]; then
    # Failure message was printed inside the failing function or timeout logic
    print_warn "Episode ${BOLD}$num${NC} processing failed or timed out. Cleaning up."
    if [[ -d "$opath" ]]; then # Check if temp dir was created
      if [[ -z "${_DEBUG_MODE:-}" ]]; then
        print_info "  Cleaning up temporary directory: ${BOLD}$opath${NC}"
        rm -rf "$opath"
      else
        print_warn "Debug mode: Leaving temporary directory: ${BOLD}$opath${NC}"
      fi
    fi
    rm -f "$v" # Ensure target file is removed on failure
    return 1   # Signal failure for THIS episode
  else
    set_title "✅  $_ANIME_NAME - Episode $num - Finished"
    print_info "${GREEN}✓ Successfully downloaded and assembled Episode ${BOLD}$num${NC} to ${BOLD}$v${NC}"
    if [[ -d "$opath" ]]; then # Check if temp dir exists
      if [[ -z "${_DEBUG_MODE:-}" ]]; then
        print_info "  Cleaning up temporary directory: ${BOLD}$opath${NC}"
        rm -rf "$opath"
      else
        print_warn "Debug mode: Leaving temporary directory: ${BOLD}$opath${NC}"
      fi
    fi
    return 0 # Signal success
  fi
}

# --- Episode Selection / Parsing ---
select_episodes_to_download() {
  local source_path="$_VIDEO_DIR_PATH/$_ANIME_NAME/$_SOURCE_FILE"
  local ep_count
  ep_count=$("$_JQ" -r '.data | length' "$source_path")

  if [[ "$ep_count" -eq 0 ]]; then
    print_error "No episode data found in $source_path!"
  fi

  if [[ "$ep_count" -eq 1 ]]; then
    print_info "Only one episode available, selecting it."
    echo "1" # Return selection
    return 0
  fi

  print_info "Available episodes for ${BOLD}$_ANIME_NAME${NC}:"
  # Use jq with string concatenation (+) for robustness
  # Output to stderr (>&2) so it appears before the prompt
  if ! "$_JQ" -r '.data[] | ("  [ " + (.episode|tostring) + " ]  E" + (.episode|tostring) + " (" + .created_at + ")")' "$source_path" >&2; then
    print_error "Failed to list episodes using jq. Check jq installation and source file."
  fi

  # Prompt user (also to stderr)
  echo -e -n "\n${YELLOW}▶ Which episode(s) to download?${NC} (e.g., 1, 3-5, *): " >&2
  read -r s
  # Check if input was empty
  if [[ -z "$s" ]]; then
    print_error "No episode selection provided."
  fi
  echo "$s" # Return selection
}

download_episodes() {
  local ep_string="$1"
  local any_failures=0
  # $1: episode number string (e.g., "1,3-5,!10,L3,*,-2")
  local source_path="$_VIDEO_DIR_PATH/$_ANIME_NAME/$_SOURCE_FILE"
  local all_available_eps=() include_list=() exclude_list=() final_list=()
  local total_selected=0 success_count=0 fail_count=0

  print_info "${YELLOW}⟳ Parsing episode selection string: ${BOLD}$ep_string${NC}"

  # --- ADDED CHECK --- Verify source file exists and is readable
  if [[ ! -f "$source_path" ]]; then
    print_error "Source file does not exist: $source_path"
  elif [[ ! -r "$source_path" ]]; then
    print_error "Source file is not readable: $source_path"
  fi
  # --- END CHECK ---

  # --- Step 1: Get all available episode numbers ---
  mapfile -t all_available_eps < <("$_JQ" -r '.data[].episode' "$source_path" | sort -n)
  if [[ ${#all_available_eps[@]} -eq 0 ]]; then
    print_error "No available episodes found in source file: $source_path"
  fi
  local first_ep="${all_available_eps[0]}"
  local last_ep="${all_available_eps[-1]}"
  print_info "  Available episodes range from ${BOLD}$first_ep${NC} to ${BOLD}$last_ep${NC} (Total: ${#all_available_eps[@]})"

  # --- Step 2: Parse input string and populate include/exclude lists ---
  IFS=',' read -ra input_parts <<<"$ep_string"

  for part in "${input_parts[@]}"; do
    part=$(echo "$part" | tr -d '[:space:]') # Trim whitespace
    # Also trim potential leading/trailing quotes from individual parts
    part="${part#\"}"
    part="${part%\"}"
    local target_list_ref="include_list" # Default to include list
    local pattern="$part"

    # Check for exclusion prefix
    if [[ "$pattern" == "!"* ]]; then
      target_list_ref="exclude_list"
      pattern="${pattern#!}" # Remove the "!"
      print_info "  Processing exclusion pattern: ${BOLD}$pattern${NC}"
    else
      print_info "  Processing inclusion pattern: ${BOLD}$pattern${NC}"
    fi

# Handle patterns (could have used eval to reduce if..else, but i do my best to avoid it)
    case "$pattern" in
    \*) # Wildcard for all available
      if [[ "$target_list_ref" == "include_list" ]]; then
        include_list+=("${all_available_eps[@]}")
      else
        exclude_list+=("${all_available_eps[@]}")
      fi
      ;;
    L[0-9]*) # Latest N
      local num=${pattern#L}
      local temp_slice=()
      if [[ "$num" -gt 0 && "$num" -le ${#all_available_eps[@]} ]]; then
        temp_slice=("${all_available_eps[@]: -$num}")
      elif [[ "$num" -gt ${#all_available_eps[@]} ]]; then
        print_warn "  Requested latest $num, but only ${#all_available_eps[@]} available. Adding all."
        temp_slice=("${all_available_eps[@]}")
      else
        print_warn "  Invalid number for Latest N: $pattern"
        continue # Skip adding if invalid
      fi
      # Append slice to the correct list
      if [[ "$target_list_ref" == "include_list" ]]; then
        include_list+=("${temp_slice[@]}")
      else
        exclude_list+=("${temp_slice[@]}")
      fi
      ;;
    F[0-9]*) # First N
      local num=${pattern#F}
      local temp_slice=()
      if [[ "$num" -gt 0 && "$num" -le ${#all_available_eps[@]} ]]; then
        temp_slice=("${all_available_eps[@]:0:$num}")
      elif [[ "$num" -gt ${#all_available_eps[@]} ]]; then
        print_warn "  Requested first $num, but only ${#all_available_eps[@]} available. Adding all."
        temp_slice=("${all_available_eps[@]}")
      else
        print_warn "  Invalid number for First N: $pattern"
        continue # Skip adding if invalid
      fi
      # Append slice to the correct list
      if [[ "$target_list_ref" == "include_list" ]]; then
        include_list+=("${temp_slice[@]}")
      else
        exclude_list+=("${temp_slice[@]}")
      fi
      ;;
    [0-9]*-) # From N onwards
      local start_num=${pattern%-}
      for ep in "${all_available_eps[@]}"; do
        if [[ "$ep" -ge "$start_num" ]]; then
          if [[ "$target_list_ref" == "include_list" ]]; then
            include_list+=("$ep")
          else
            exclude_list+=("$ep")
          fi
        fi
      done
      ;;
    -[0-9]*) # Up to N
      local end_num=${pattern#-}
      for ep in "${all_available_eps[@]}"; do
        if [[ "$ep" -le "$end_num" ]]; then
          if [[ "$target_list_ref" == "include_list" ]]; then
            include_list+=("$ep")
          else
            exclude_list+=("$ep")
          fi
        fi
      done
      ;;
    [0-9]*-[0-9]*) # Range N-M
      local s e
      s=$(awk -F '-' '{print $1}' <<<"$pattern")
      e=$(awk -F '-' '{print $2}' <<<"$pattern")
      if [[ ! "$s" =~ ^[0-9]+$ || ! "$e" =~ ^[0-9]+$ || $s -gt $e ]]; then
        print_warn "  Invalid range '$pattern'. Skipping."
        continue
      fi
      for ep in "${all_available_eps[@]}"; do
        if [[ "$ep" -ge "$s" && "$ep" -le "$e" ]]; then
          if [[ "$target_list_ref" == "include_list" ]]; then
            include_list+=("$ep")
          else
            exclude_list+=("$ep")
          fi
        fi
      done
      ;;
    [0-9]*) # Single number
      local found=0
      for ep in "${all_available_eps[@]}"; do
        if [[ "$ep" -eq "$pattern" ]]; then
          if [[ "$target_list_ref" == "include_list" ]]; then
            include_list+=("$pattern")
          else
            exclude_list+=("$pattern")
          fi
          found=1
          break
        fi
      done
      [[ $found -eq 0 ]] && print_warn "  Episode $pattern specified but not found in available list."
      ;;
    *) # Invalid pattern
      print_warn "  Unrecognized pattern '$pattern'. Skipping."
      ;;
    esac
  done

  # --- Step 3: Calculate Final List (Set Difference) ---
  local unique_includes=() unique_excludes=() temp_final_list=()

  # Get unique sorted lists

  if [[ ${#include_list[@]} -eq 0 ]]; then
    unique_includes=() # Ensure it's empty if input list was empty
  else
    mapfile -t unique_includes < <(printf '%s\n' "${include_list[@]}" | sort -n -u)
  fi

  if [[ ${#exclude_list[@]} -eq 0 ]]; then
    unique_excludes=() # Ensure it's empty if exclude list was empty
  else
    mapfile -t unique_excludes < <(printf '%s\n' "${exclude_list[@]}" | sort -n -u)
  fi

  print_info "  Found ${#unique_includes[@]} unique include episodes and ${#unique_excludes[@]} exclude episodes."

  # Create final list by filtering out excluded episodes from included episodes
  for item in "${unique_includes[@]}"; do
    # Simple linear search through exclusions (avoids associative array issues)
    local is_excluded=0
    for ex_item in "${unique_excludes[@]}"; do
      if [[ "$item" == "$ex_item" ]]; then
        is_excluded=1
        break
      fi
    done

    # If not excluded, add to final list
    if [[ $is_excluded -eq 0 ]]; then
      temp_final_list+=("$item")
    fi
  done

  # Assign to final_list (already sorted because unique_includes was sorted)
  final_list=("${temp_final_list[@]}")

  total_selected=${#final_list[@]}

  if [[ $total_selected -eq 0 ]]; then
    # Use print_error only if no episodes were initially selected by include rules
    # If exclusions removed everything, it's a warning/info case, not error
    if [[ ${#unique_includes[@]} -eq 0 ]]; then
      print_error "No episodes selected based on inclusion rules."
    else
      print_warn "No episodes remaining after applying exclusions."
      # Exit gracefully without error?
      exit 0
    fi
  fi

  print_info "${GREEN}✓ Final Download Plan:${NC} ${BOLD}${total_selected}${NC} unique episode(s) -> ${final_list[*]}"
  # Add blank line before header
  echo
  echo -e "${BOLD}${CYAN}======= Starting Episode Downloads =======${NC}"

  # --- Step 4: Download Loop ---
  local current_ep_num=0
  for e in "${final_list[@]}"; do
    current_ep_num=$((current_ep_num + 1))
    # Add blank line before header
    echo
    echo -e "${PURPLE}-------------------- [ Processing Episode ${e} (${current_ep_num}/${total_selected}) ] --------------------${NC}"

    # Call download_episode and check its return status explicitly
    if download_episode "$e"; then
      success_count=$((success_count + 1))
    else
      # download_episode failed (returned non-zero)
      fail_count=$((fail_count + 1))
      any_failures=1

      # Warning message on failure
      print_warn "Episode ${BOLD}${e}${NC} failed to process fully. Skipping to the next episode."
    fi
  done

  # --- Final Summary ---
  # Add blank line before header
  echo
  echo -e "\n${BOLD}${CYAN}======= Download Summary =======${NC}"
  echo -e "${GREEN}✓ Successfully processed: ${BOLD}$success_count${NC}${GREEN} episode(s)${NC}"
  if [[ $fail_count -gt 0 ]]; then
    echo -e "${RED}✘ Failed/Skipped:       ${BOLD}$fail_count${NC}${RED} episode(s)${NC}"
  fi
  echo -e "${BLUE}Total planned:        ${BOLD}$total_selected${NC}${BLUE} episode(s)${NC}"
  # Add blank line after summary
  echo
  echo -e "${GREEN}✓ All tasks completed!${NC}"



  # --- Optional Notification ---
  # Check if _ALLOW_NOTIFICATION vAriable is set TO true
  if [[ "${_ALLOW_NOTIFICATION:-false}" == "true" ]]; then
    "$_NOTIFICATION_CMD"  "Download complete: $_ANIME_NAME " "Success: $success_count Failed: $fail_count"
  fi


  # Exit with non-zero status if any episode failed
  exit $any_failures
}

# --- Name / Slug Helpers ---
remove_brackets() {
  awk -F']' '{print $1}' | sed -E 's/^\[//'
}

remove_slug() {
  # Removes slug like "[slug] Title   " -> "Title   "
  awk -F'] ' '{print $2}'
}

get_slug_from_name() {
  # $1: Anime Title (potentially without trailing spaces)
  # $2: Anime List File (optional, defaults to global var)
  local search_name="$1"
  local list_file="${2:-$_ANIME_LIST_FILE}"

  awk -F'] ' -v name="$search_name" '
        function trim(s) { gsub(/^ +| +$/, "", s); return s }
        BEGIN { IGNORECASE=1 }
        {
            # Trim trailing whitespace from the title field ($2) before comparison
            title = $2
            title = trim(title)
            n = trim(name)
            if (title == n) {
                slug = $1
                sub(/^\[/, "", slug)
                print slug
            }
        }
    ' "$list_file" |
    tail -n 1 # Get the last match if duplicates exist
}

sanitize_filename() {
  # $1: Input string
  # Remove/replace characters invalid for filenames
  echo "$1" | sed -E 's/[^[:alnum:] ,+\-\)\(._]/_/g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' # Trim whitespace too
}

# --- Main Execution ---
main() {
  echo
  echo -e "${BOLD}${CYAN}======= AnimePahe Downloader Script =======${NC}"
  set_args "$@"
  set_var
  set_cookie
  echo
  echo -e "${BOLD}${CYAN}======= Selecting Anime =======${NC}"

  local selected_line # Variable to hold the full line from fzf

  if [[ -n "${_INPUT_ANIME_NAME:-}" ]]; then
    local search_results
    # search_anime_by_name  returns full "[slug] Title" lines
    search_results=$(search_anime_by_name "$_INPUT_ANIME_NAME")
    if [[ -z "$search_results" ]]; then
      print_error "No anime found matching '${_INPUT_ANIME_NAME}' via API search or search failed."
    fi
    print_info "Select anime from search results:"

    # Use fzf to display only the title (field 2 onwards after '] ') but return the whole line
    selected_line=$("$_FZF" --select-1 --exit-0 --delimiter='] ' --with-nth=2.. <<<"$search_results")
    [[ -z "$selected_line" ]] && print_error "No anime selected from search results."

    # Parse slug and name directly from the selected line
    _ANIME_SLUG=$(echo "$selected_line" | awk -F']' '{print $1}' | sed 's/^\[//')
    _ANIME_NAME=$(echo "$selected_line" | awk -F'] ' '{print $2}' | sed 's/[[:space:]]*$//')

  elif [[ -n "${_ANIME_SLUG:-}" ]]; then
    # Slug provided directly, try to find name from list (this part is likely okay)
    print_info "Using provided slug: ${BOLD}$_ANIME_SLUG${NC}"
    if [[ ! -f "$_ANIME_LIST_FILE" ]]; then download_anime_list; fi
    _ANIME_NAME=$(grep "^\[${_ANIME_SLUG}\]" "$_ANIME_LIST_FILE" | tail -n 1 | remove_slug | sed 's/[[:space:]]*$//')
    if [[ -z "$_ANIME_NAME" ]]; then
      print_warn "Could not find anime name for slug ${_ANIME_SLUG} in list. Using slug as name."
      _ANIME_NAME="$_ANIME_SLUG" # Fallback
    fi

  else
    # No name or slug provided, use fzf on the list file
    if [[ ! -f "$_ANIME_LIST_FILE" ]]; then
      print_info "Anime list file (${BOLD}$_ANIME_LIST_FILE${NC}) not found."
      download_anime_list || print_error "Failed to download initial anime list."
    fi
    [[ ! -s "$_ANIME_LIST_FILE" ]] && print_error "Anime list file is empty."

    print_info "Select anime from the list (${BOLD}$_ANIME_LIST_FILE${NC}):"

    # Read full lines from file, display only title part in fzf
    selected_line=$("$_FZF" --select-1 --exit-0 --delimiter='] ' --with-nth=2.. <"$_ANIME_LIST_FILE")
    [[ -z "$selected_line" ]] && print_error "No anime selected from list."

    # Parse slug and name directly from the selected line
    _ANIME_SLUG=$(echo "$selected_line" | awk -F']' '{print $1}' | sed 's/^\[//')
    _ANIME_NAME=$(echo "$selected_line" | awk -F'] ' '{print $2}' | sed 's/[[:space:]]*$//')
  fi

  # Validate slug and sanitize name
  [[ -z "$_ANIME_SLUG" ]] && print_error "Could not determine Anime Slug for '${_ANIME_NAME:-unknown}'."
  # Sanitize the name AFTER extracting it
  _ANIME_NAME=$(sanitize_filename "${_ANIME_NAME:-}")
  [[ -z "$_ANIME_NAME" ]] && print_error "Anime name became empty after sanitization! Check the original name or sanitize_filename function."

  print_info "${GREEN}✓ Selected Anime:${NC} ${BOLD}${_ANIME_NAME}${NC} (Slug: ${_ANIME_SLUG})"
  echo
  echo -e "${BOLD}${CYAN}======= Preparing Download =======${NC}"

  mkdir -p "$_VIDEO_DIR_PATH/$_ANIME_NAME" || print_error "Cannot create target directory: $_VIDEO_DIR_PATH/$_ANIME_NAME"
  download_source "$_ANIME_SLUG" "$_ANIME_NAME" || print_error "Failed to download episode source information."

  # Select episodes if not provided via -e
  if [[ -z "${_ANIME_EPISODE:-}" ]]; then
    _ANIME_EPISODE=$(select_episodes_to_download)
    [[ -z "${_ANIME_EPISODE}" ]] && print_error "No episodes selected for download."
  fi
  print_info "Episode selection: ${BOLD}${_ANIME_EPISODE}${NC}"

  # Download the selected episodes
  download_episodes "$_ANIME_EPISODE"
}

# --- Script Entry Point ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
