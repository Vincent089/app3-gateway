local SessionWriterHandler = {
  PRIORITY = 800,
  VERSION  = "1.0.0",
}

local redis = require "resty.redis"
local cjson = require "cjson.safe"

local function extract_token(authorization)
  if not authorization then return nil end
  return authorization:match("^[Bb]earer%s+(.-)%s*$")
end

-- Timer callbacks run in a background light thread — cosockets are allowed there.
-- Kong patches ngx.socket.tcp to raise in body_filter and log, but not in timers.
-- ngx.log is used instead of kong.log: no active request context in timers.

local function timer_write_session(premature, host, port, timeout, token, session, ttl)
  if premature then return end
  local red = redis:new()
  red:set_timeout(timeout)
  local ok, err = red:connect(host, port)
  if not ok then
    ngx.log(ngx.ERR, "session-writer: Redis connect failed: ", err)
    return
  end
  local _, set_err = red:setex("session:" .. token, ttl, session)
  red:set_keepalive(10000, 10)
  if set_err then
    ngx.log(ngx.ERR, "session-writer: Redis SETEX failed: ", set_err)
  end
end

local function timer_delete_session(premature, host, port, timeout, token)
  if premature then return end
  local red = redis:new()
  red:set_timeout(timeout)
  local ok, err = red:connect(host, port)
  if not ok then
    ngx.log(ngx.ERR, "session-writer: Redis connect failed: ", err)
    return
  end
  red:del("session:" .. token)
  red:set_keepalive(10000, 10)
end

-- Accumulate body chunks; on EOF snapshot status and token into kong.ctx.shared
-- for the log phase. No I/O — cosockets are forbidden in body_filter_by_lua*.
function SessionWriterHandler:body_filter(conf)
  local chunk = ngx.arg[1]
  local eof   = ngx.arg[2]

  local ctx = kong.ctx.plugin
  if chunk and chunk ~= "" then
    ctx.body = (ctx.body or "") .. chunk
  end

  if not eof then
    return
  end

  local status = kong.response.get_status()
  kong.ctx.shared.sw_status = status
  kong.ctx.shared.sw_body   = ctx.body

  if status == 204 then
    kong.ctx.shared.sw_revoke_token =
      extract_token(kong.request.get_header("Authorization"))
  end
end

-- Schedule a background timer to do Redis I/O — no cosockets allowed in
-- log_by_lua* either. ngx.timer.at(0, fn, ...) fires on the next event loop
-- tick in a privileged context where cosockets work. All args are passed by
-- value so the timer needs no shared state.
function SessionWriterHandler:log(conf)
  local status     = kong.ctx.shared.sw_status
  local body_str   = kong.ctx.shared.sw_body
  local revoke_tok = kong.ctx.shared.sw_revoke_token

  if not status then
    return
  end

  -- ── POST /auth → status 200: schedule session write ──────────────────────
  if status == 200 then
    local body = cjson.decode(body_str or "")
    if not body or not body.data or not body.data.token or not body.data.user then
      kong.log.warn("session-writer: /auth response missing expected fields — skipping")
      return
    end

    local token = body.data.token
    local user  = body.data.user

    local groups = user.groups or {}
    if type(groups) ~= "table" then
      groups = {}
    end

    local session = cjson.encode({
      id        = user.id,
      email     = user.email,
      firstname = user.firstname,
      lastname  = user.lastname,
      username  = user.username,
      groups    = groups,
      issued_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    })

    local ok, err = ngx.timer.at(0, timer_write_session,
      conf.redis_host, conf.redis_port, conf.redis_timeout,
      token, session, conf.session_ttl)
    if not ok then
      kong.log.err("session-writer: failed to schedule write timer: ", err)
    end

  -- ── POST /revoke → status 204: schedule session delete ───────────────────
  elseif status == 204 then
    if not revoke_tok then
      kong.log.warn("session-writer: /revoke 204 but no Authorization header")
      return
    end

    local ok, err = ngx.timer.at(0, timer_delete_session,
      conf.redis_host, conf.redis_port, conf.redis_timeout, revoke_tok)
    if not ok then
      kong.log.err("session-writer: failed to schedule delete timer: ", err)
    end
  end
end

return SessionWriterHandler
