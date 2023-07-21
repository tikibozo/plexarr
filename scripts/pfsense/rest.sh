for k in `redis-cli keys ntopng.cache.failed_logins.*`; do redis-cli del $k; done
