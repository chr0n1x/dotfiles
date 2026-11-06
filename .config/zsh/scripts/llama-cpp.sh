# Cache the default llama.cpp model name to avoid a blocking curl at shell
# startup.  The cache file holds the model name on one line; its mtime is
# used as the TTL (refresh in background if older than LLAMA_CACHE_TTL,
# default 7 days).
#
# llama-refresh [force]  - fetch the model list now and update the cache.
#                          "force" overrides the TTL.

_llama_cache_dir="${LLAMA_CACHE_DIR:-$HOME/.cache/llama.cpp}"
_llama_cache_file="$_llama_cache_dir/model"
_llama_cache_ttl="${LLAMA_CACHE_TTL:-604800}"  # 7 days in seconds

# The models endpoint is OpenAI-shaped for llama.cpp and Strata
# ({"data":[{"id":...}]}); older Ollama returns {"models":[{"name":...]}.
_llama_model_id() {
  jq -r '.data[0].id // .models[0].name // empty'
}

# LLAMA_BASE_URL already carries the /v1 suffix; LLAMACPP_HOST does not.
_llama_models_url() {
  local base="${LLAMA_BASE_URL:-${LLAMACPP_HOST:-}}"
  [[ -z "$base" ]] && return 1
  base="${base%/}"
  [[ $base == */v1 ]] || base="$base/v1"
  printf '%s/models' "$base"
}

# Each harness wants the model differently: pi/pig take a provider flag plus
# the bare id, maki wants "provider/id" in a single -m spec.
_llama_export() {
  export LLAMA_DEFAULT_MODEL="$1"
  export CLAUDE_MODEL="$1"
  export MAKI_MODEL="llama-cpp/$1"
}

_llama_fetch() {
  local url model
  url="$(_llama_models_url)" || return 1
  model="$(curl -ssL --max-time 5 "$url" 2>/dev/null | _llama_model_id)"
  if [[ -n "$model" && "$model" != "null" ]]; then
    mkdir -p "$_llama_cache_dir"
    printf '%s' "$model" > "$_llama_cache_file"
    printf '%s' "$model"
    return 0
  fi
  return 1
}

# Read cache.  If missing or stale, kick off a background refresh (only if
# the server is actually reachable we write; on failure the old value stays).
if [[ -f "$_llama_cache_file" ]]; then
  _llama_export "$(cat "$_llama_cache_file")"
  # mtime in seconds; treat unreadable mtime as stale
  integer cache_age=$(( $(date +%s) - $(stat -c %Y "$_llama_cache_file" 2>/dev/null || echo 0) ))
  if (( cache_age > _llama_cache_ttl )); then
    ( _llama_fetch > /dev/null ) &
  fi
else
  # First run: synchronous fetch (one-time cost)
  _llama_export "$(_llama_fetch)"
fi

llama-refresh() {
  local model
  model="$(_llama_fetch)"
  if [[ -n "$model" ]]; then
    _llama_export "$model"
    echo "LLAMA_DEFAULT_MODEL=$model"
  else
    echo "llama-refresh: failed to reach $(_llama_models_url)" >&2
    return 1
  fi
}
