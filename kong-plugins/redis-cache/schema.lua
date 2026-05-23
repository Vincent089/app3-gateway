local typedefs = require "kong.db.schema.typedefs"

return {
  name = "redis-cache",
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
          { cache_ttl = {
              type    = "integer",
              default = 60,     -- seconds
              gt      = 0,
          }},
          { request_method = {
              type     = "array",
              elements = { type = "string" },
              default  = { "GET", "HEAD" },
          }},
          { response_code = {
              type     = "array",
              elements = { type = "integer" },
              default  = { 200 },
          }},
          { content_type = {
              type     = "array",
              elements = { type = "string" },
              default  = { "application/json" },
          }},
        },
    }},
  },
}
