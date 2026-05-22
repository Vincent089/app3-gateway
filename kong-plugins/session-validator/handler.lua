local SessionValidatorHandler = {
  PRIORITY = 1000,
  VERSION  = "1.0.0",
}

local redis = require "resty.redis"
local http  = require "resty.http"
local cjson = require "cjson.safe"

local function extract_token(authorization)
  if not authorization then return nil end
  return authorization:match("^[Bb]earer%s+(.-)%s*$")
end

-- Returns session table, or nil + reason ("miss" | "unavailable")
--   miss        → key absent from Redis; the session does not exist
--   unavailable → connection or decode error; Redis is unreachable
local function redis_get_session(conf, token)
  local red = redis:new()
  red:set_timeout(conf.redis_timeout)

  local ok, err = red:connect(conf.redis_host, conf.redis_port)
  if not ok then
    return nil, "unavailable"
  end

  local val, red_err = red:get("session:" .. token)

  red:set_keepalive(10000, 10)

  if red_err then
    return nil, "unavailable"
  end

  if val == ngx.null then
    return nil, "miss"
  end

  local data = cjson.decode(val)
  if not data then
    -- Corrupted entry — let /verify be the authority rather than silently 401-ing
    return nil, "unavailable"
  end

  return data, nil
end

-- Returns session table, or nil + http status code (401 | 503)
local function auth_service_verify(conf, token)
  local httpc = http.new()
  httpc:set_timeout(conf.auth_verify_timeout)

  local res, err = httpc:request_uri(conf.auth_service_url .. "/verify", {
    method  = "GET",
    headers = { ["Authorization"] = "Bearer " .. token },
  })

  if err or not res then
    return nil, 503
  end

  if res.status == 401 then
    return nil, 401
  end

  if res.status ~= 200 then
    return nil, 503
  end

  local body = cjson.decode(res.body)
  if not body or not body.data or not body.data.user then
    return nil, 503
  end

  return body.data.user, nil
end

function SessionValidatorHandler:access(conf)
  local token = extract_token(kong.request.get_header("Authorization"))

  if not token then
    return kong.response.exit(401, { message = "Unauthorized" })
  end

  local session, reason = redis_get_session(conf, token)

  if reason == "miss" then
    return kong.response.exit(401, { message = "Unauthorized" })
  end

  if reason == "unavailable" then
    local fallback, status = auth_service_verify(conf, token)

    if status == 401 then
      return kong.response.exit(401, { message = "Unauthorized" })
    end

    if not fallback then
      return kong.response.exit(503, { message = "Service Unavailable" })
    end

    session = fallback
  end

  local groups = session.groups or {}
  if type(groups) == "table" then
    groups = table.concat(groups, ",")
  end

  kong.service.request.set_header("X-User-ID",      session.id or "")
  kong.service.request.set_header("X-User-Groups",  groups)
  kong.service.request.set_header("X-Trail-ID",     ngx.var.request_id)
  kong.service.request.set_header("X-Request-Time", tostring(math.floor(ngx.now() * 1000)))

  -- Upstream trusts injected headers only; strip the raw token
  kong.service.request.clear_header("Authorization")
end

return SessionValidatorHandler
