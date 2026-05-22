local typedefs = require "kong.db.schema.typedefs"

return {
  name = "session-validator",
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
          { auth_service_url = {
              type     = "string",
              required = true,
          }},
          { auth_verify_timeout = {
              type    = "integer",
              default = 5000,   -- ms
              gt      = 0,
          }},
        },
    }},
  },
}
