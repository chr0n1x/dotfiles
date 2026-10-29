# Cache the default llama.cpp model name to avoid a blocking curl at shell
# startup.  The cache file holds the model name on one line; its mtime is
# used as the TTL (refresh in background if older than LLAMA_CACHE_TTL,
# default 7 days).
#
# llama-refresh [force]  - fetch the model list now and update the cache.
#                          "force" overrides the TTL.

_llama_cache_dir="$HOME/.cache/llama.cpp"
_llama_cache_file="$_llama_cache_dir/model"
_llama_cache_ttl="${LLAMA_CACHE_TTL:-604800}"  # 7 days in seconds

_llama_fetch() {
  local model
  model="$(curl -ssL --max-time 5 "${LLAMACPP_HOST}/v1/models" 2>/dev/null | jq -r '.models[0].name' 2>/dev/null)"
  if [[ -n "$model" && "$model" != "null" ]]; then
    mkdir -p "$_llama_cache_dir"
    printf '%s' "$model" > "$_llama_cache_file"
    printf '%s' "$model"
  fi
}

# Read cache.  If missing or stale, kick off a background refresh (only if
# the server is actually reachable we write; on failure the old value stays).
if [[ -f "$_llama_cache_file" ]]; then
  export LLAMA_DEFAULT_MODEL="$(cat "$_llama_cache_file")"
  # mtime in seconds; treat unreadable mtime as stale
  integer cache_age=$(( $(date +%s) - $(stat -c %Y "$_llama_cache_file" 2>/dev/null || echo 0) ))
  if (( cache_age > _llama_cache_ttl )); then
    ( _llama_fetch > /dev/null ) &
  fi
else
  # First run: synchronous fetch (one-time cost)
  export LLAMA_DEFAULT_MODEL="$(_llama_fetch)"
fi

llama-refresh() {
  local model
  model="$(_llama_fetch)"
  if [[ -n "$model" ]]; then
    export LLAMA_DEFAULT_MODEL="$model"
    export CLAUDE_MODEL="$model"
    echo "LLAMA_DEFAULT_MODEL=$model"
  else
    echo "llama-refresh: failed to reach $LLAMACPP_HOST" >&2
    return 1
  fi
}
