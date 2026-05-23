local RedisCacheHandler = {
  PRIORITY = 100,   -- runs after session-validator (1000); same slot as built-in proxy-cache
  VERSION  = "1.0.0",
}

local redis = require "resty.redis"
local cjson = require "cjson.safe"

-- Headers that must not be stored or replayed.
local SKIP_HEADERS = {
  ["connection"]               = true,
  ["keep-alive"]               = true,
  ["te"]                       = true,
  ["trailers"]                 = true,
  ["transfer-encoding"]        = true,
  ["upgrade"]                  = true,
  ["x-cache-status"]           = true,
  ["x-kong-proxy-latency"]     = true,
  ["x-kong-upstream-latency"]  = true,
  ["x-kong-upstream-status"]   = true,
}

local function redis_connect(host, port, timeout)
  local red = redis:new()
  red:set_timeout(timeout)
  local ok, err = red:connect(host, port)
  if not ok then
    return nil, err
  end
  return red, nil
end

local function cache_key(method, path, query)
  -- User-agnostic key: all authenticated users share cached responses.
  -- To make responses per-user, include kong.ctx.shared X-User-ID here.
  local key = method .. ":" .. path
  if query and query ~= "" then
    key = key .. "?" .. query
  end
  return "cache:" .. key
end

local function method_allowed(conf, method)
  for _, m in ipairs(conf.request_method) do
    if m == method then return true end
  end
  return false
end

local function status_cacheable(conf, status)
  for _, s in ipairs(conf.response_code) do
    if s == status then return true end
  end
  return false
end

local function content_type_cacheable(conf, ct)
  if not ct then return false end
  for _, allowed in ipairs(conf.content_type) do
    if ct:find(allowed, 1, true) then return true end
  end
  return false
end

-- ── access: check cache; exit on hit, continue on miss ───────────────────────
-- Cosockets are allowed in the access phase — same pattern as session-validator.
function RedisCacheHandler:access(conf)
  local method = kong.request.get_method()
  if not method_allowed(conf, method) then
    return
  end

  local path  = kong.request.get_path()
  local query = kong.request.get_raw_query()
  local key   = cache_key(method, path, query)

  local red, err = redis_connect(conf.redis_host, conf.redis_port, conf.redis_timeout)
  if not red then
    -- Fail open: let the request through without caching.
    kong.log.warn("redis-cache: Redis unavailable, bypassing cache: ", err)
    return
  end

  local cached, get_err = red:get(key)
  red:set_keepalive(10000, 10)

  if cached and cached ~= ngx.null then
    local entry = cjson.decode(cached)
    if entry then
      -- Cache hit: return stored response; upstream is never called.
      local headers = entry.headers or {}
      headers["X-Cache-Status"] = "Hit"
      kong.response.exit(entry.status, entry.body, headers)
      return
    end
    kong.log.warn("redis-cache: corrupt entry for key ", key, ", treating as miss")
  end

  -- Cache miss: mark for response phases to store the result.
  kong.ctx.shared.rc_key = key
  kong.ctx.shared.rc_ttl = conf.cache_ttl
end

-- ── header_filter: decide whether this response is worth caching ──────────────
-- Abort caching (clear rc_key) if status or content-type is not in the allow-list.
function RedisCacheHandler:header_filter(conf)
  if not kong.ctx.shared.rc_key then
    return
  end

  local status = kong.response.get_status()
  if not status_cacheable(conf, status) then
    kong.ctx.shared.rc_key = nil
    return
  end

  local ct = kong.response.get_header("Content-Type")
  if not content_type_cacheable(conf, ct) then
    kong.ctx.shared.rc_key = nil
    return
  end

  -- Snapshot response headers, skipping hop-by-hop and Kong-internal ones.
  local headers = {}
  for k, v in pairs(kong.response.get_headers()) do
    if not SKIP_HEADERS[k:lower()] then
      headers[k] = v
    end
  end

  kong.ctx.shared.rc_status  = status
  kong.ctx.shared.rc_headers = headers
  kong.response.set_header("X-Cache-Status", "Miss")
end

-- ── body_filter: accumulate chunks ───────────────────────────────────────────
-- No I/O — cosockets are forbidden in body_filter_by_lua*.
function RedisCacheHandler:body_filter(conf)
  if not kong.ctx.shared.rc_key then
    return
  end

  local chunk = ngx.arg[1]
  local eof   = ngx.arg[2]

  local ctx = kong.ctx.plugin
  if chunk and chunk ~= "" then
    ctx.body = (ctx.body or "") .. chunk
  end

  if eof then
    kong.ctx.shared.rc_body = ctx.body
  end
end

-- ── Timer: write entry to Redis ───────────────────────────────────────────────
-- Runs in a background light thread where cosockets are allowed.
-- ngx.log used instead of kong.log — no active request context in timers.
local function timer_cache_write(premature, host, port, timeout, key, entry_json, ttl)
  if premature then return end
  local red = redis:new()
  red:set_timeout(timeout)
  local ok, err = red:connect(host, port)
  if not ok then
    ngx.log(ngx.ERR, "redis-cache: Redis connect failed on write: ", err)
    return
  end
  local _, set_err = red:setex(key, ttl, entry_json)
  red:set_keepalive(10000, 10)
  if set_err then
    ngx.log(ngx.ERR, "redis-cache: SETEX failed: ", set_err)
  end
end

-- ── log: schedule cache write ────────────────────────────────────────────────
-- Cosockets forbidden in log_by_lua* — delegate to a timer.
function RedisCacheHandler:log(conf)
  local key     = kong.ctx.shared.rc_key
  local status  = kong.ctx.shared.rc_status
  local headers = kong.ctx.shared.rc_headers
  local body    = kong.ctx.shared.rc_body
  local ttl     = kong.ctx.shared.rc_ttl

  if not key or not status then
    return
  end

  local entry_json = cjson.encode({
    status  = status,
    headers = headers or {},
    body    = body or "",
  })

  local ok, err = ngx.timer.at(0, timer_cache_write,
    conf.redis_host, conf.redis_port, conf.redis_timeout,
    key, entry_json, ttl)
  if not ok then
    kong.log.err("redis-cache: failed to schedule cache write timer: ", err)
  end
end

return RedisCacheHandler
