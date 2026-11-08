# Cache the inference server's model id so shell startup never blocks on a curl.
# The cache file holds the model id on one line; its mtime is the TTL (refresh in
# background if older than LLM_CACHE_TTL, default 7 days).
#
# llm-refresh [force]  - fetch the model list now and update the cache.
#                        "force" overrides the TTL.
#
# LLM_OPENAI_API_HOST is the origin of the OpenAI-compatible server, set in
# ~/.envrc. LLM_BASE_URL (pi-llama) already carries its /v1 suffix; OLLAMA_HOST
# and friends do not.

_llm_cache_dir="${LLM_CACHE_DIR:-$HOME/.cache/llm}"
_llm_cache_file="$_llm_cache_dir/model"
_llm_cache_ttl="${LLM_CACHE_TTL:-604800}"  # 7 days in seconds

# The models endpoint is OpenAI-shaped for llama.cpp and Strata
# ({"data":[{"id":...}]}); older Ollama returns {"models":[{"name":...]}.
_llm_model_id() {
  jq -r '.data[0].id // .models[0].name // empty'
}

_llm_models_url() {
  local base="${LLM_BASE_URL:-${LLM_OPENAI_API_HOST:-}}"
  [[ -z "$base" ]] && return 1
  base="${base%/}"
  [[ $base == */v1 ]] || base="$base/v1"
  printf '%s/models' "$base"
}

# Base URL for a maki provider, from the origin or an already-suffixed URL. Maki
# appends /chat/completions but not /v1, so the suffix has to be present.
_llm_maki_base_url() {
  local base="${LLM_OPENAI_API_HOST:-}"
  [[ -z "$base" ]] && return 1
  base="${base%/}"
  [[ $base == */v1 ]] || base="$base/v1"
  printf '%s' "$base"
}

# Each harness wants the model differently: pi/pig take a provider flag plus the
# bare id, maki wants "provider/id" in a single -m spec. LLAMA_DEFAULT_MODEL keeps
# its name because the nvim harness decorators read it.
_llm_export() {
  export LLM_OPENAI_MODEL="$1"
  export LLAMA_DEFAULT_MODEL="$1"
  export MAKI_MODEL="${MAKI_PROVIDER:-strata}/$1"
}

# Strata is the maki provider slug (providers.toml). Only exported when a server
# is configured: an empty value would still outrank providers.toml in maki.
_llm_export_bases() {
  local url
  url="$(_llm_maki_base_url)" || return 0
  export STRATA_BASE_URL="$url"
}

_llm_fetch() {
  local url model
  url="$(_llm_models_url)" || return 1
  model="$(curl -ssL --max-time 5 "$url" 2>/dev/null | _llm_model_id)"
  if [[ -n "$model" && "$model" != "null" ]]; then
    mkdir -p "$_llm_cache_dir"
    printf '%s' "$model" > "$_llm_cache_file"
    printf '%s' "$model"
    return 0
  fi
  return 1
}

# Read cache.  If missing or stale, kick off a background refresh (only if
# the server is actually reachable we write; on failure the old value stays).
if [[ -f "$_llm_cache_file" ]]; then
  _llm_export "$(cat "$_llm_cache_file")"
  # mtime in seconds; treat unreadable mtime as stale
  integer cache_age=$(( $(date +%s) - $(stat -c %Y "$_llm_cache_file" 2>/dev/null || echo 0) ))
  if (( cache_age > _llm_cache_ttl )); then
    ( _llm_fetch > /dev/null ) &
  fi
else
  # First run: synchronous fetch (one-time cost)
  _llm_export "$(_llm_fetch)"
fi
_llm_export_bases

llm-refresh() {
  local model
  model="$(_llm_fetch)"
  if [[ -n "$model" ]]; then
    _llm_export "$model"
    echo "LLM_OPENAI_MODEL=$model"
  else
    echo "llm-refresh: failed to reach $(_llm_models_url)" >&2
    return 1
  fi
}
