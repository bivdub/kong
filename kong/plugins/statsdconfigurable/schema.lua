local metrics = {
  "request_count",
  "latency",
  "request_size",
  "status_count",
  "response_size",
  "unique_users",
  "request_per_user",
  "upstream_latency",
  "kong_latency",
  "status_counts_per_user"
}

local stat_types = {
  "gauge",
  "timer",
  "counter",
  "histogram",
  "meter",
  "set"
}

local function check_sample_rate(value)
  for i, entry in ipairs(value) do
    if entry.stat_type == "counter" or entry.stat_type == "gauge" and entry.sample_rate == nil then
      return false, "sample rate must be defined for counters and gauges"
    end
  end
  return true
end

local default_metrics = {
  {
    "name" = "request_count",
    "stat_type" = "counter",
    "sample_rate" = 1
  },
  {
    "name" = "latency",
    "stat_type" = "timer"
  },
  {
    "name" = "request_size",
    "stat_type" = "timer"
  },
  {
    "name" = "status_count",
    "stat_type" = "counter",
    "sample_rate" = 1
  },
  {
    "name" = "response_size",
    "stat_type" = "timer"
  },
  {
    "name" = "unique_users",
    "stat_type" = "set"
  },
  {
    "name" = "request_per_user",
    "stat_type" = "counter",
    "sample_rate" = 1
  },
  {
    "name" = "upstream_latency",
    "stat_type" = "timer"
  },
  {
    "name" = "kong_latency",
    "stat_type" = "timer"
  },
  {
    "name" = "status_counts_per_user",
    "stat_type" = "counter",
    "sample_rate" = 1
  }
}

return {
  fields = {
    host = {required = true, type = "string", default = "localhost"},
    port = {required = true, type = "number", default = 8125},
    metrics = {
      type = "table",
      schema = {
        fields = {
          name = {required = true, type = "string", enum = metrics},
          stat_type = {required = true, type = "string", enum = stat_types},
          sample_rate = {required = false, type = "number"}
        }
      }
      required = true,
      default = metrics,
      func = check_sample_rate
    },
    timeout = {type = "number", default = 10000}
  }
}
