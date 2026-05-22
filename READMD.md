# OSS KONG

### issue
OSS version does not support Redis out of the box

The tradeoff: with memory strategy, each Kong pod caches independently. With 2 replicas, a request hitting pod A will miss the cache on pod B. For a session-validated API this is acceptable — correctness is fine, you just get lower hit rates than you would with shared Redis. If you later want shared caching, that's proxy-cache-advanced on Kong Enterprise, or you'd replace proxy-cache with a custom Lua plugin using lua-resty-redis directly (same pattern as session-writer).