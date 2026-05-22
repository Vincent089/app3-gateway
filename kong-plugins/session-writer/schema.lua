local typedefs = require "kong.db.schema.typedefs"

return {
  name = "session-writer",
  fields = {
    { consumer  = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type   = "record",
        fields = {
          { redis_host = {
              type     = "string",
              required = true,
          }},
          { redis_port = {
              type    = "integer",
              default = 6379,
              between = { 0, 65535 },
          }},
          { redis_timeout = {
              type    = "integer",
              default = 2000,   -- ms
              gt      = 0,
          }},
          { session_ttl = {
              type    = "integer",
              default = 28800,  -- 8 hours in seconds
              gt      = 0,
          }},
        },
    }},
  },
}
