local cjson = require "cjson"
local utils = require "kong.tools.utils"
local helpers = require "spec.helpers"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_stringx = require "pl.stringx"

local FILE_LOG_PATH = os.tmpname()

describe("Plugin: debug-log (log)", function()
  local client
  setup(function()
    assert(helpers.start_kong())

    local api1 = assert(helpers.dao.apis:insert {
      request_host = "debug_logging.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name = "debug-log",
      config = {
        header_name = "X-Kong-Debug",
        path = FILE_LOG_PATH
      }
    })
  end)
  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = helpers.proxy_client()
  end)
  after_each(function()
    if client then client:close() end
  end)

  it("logs request and response to file", function()
    local uuid = utils.random_string()

    -- Making the request
    local res = assert(client:send({
      method = "GET",
      path = "/status/200",
      headers = {
        ["debug-log-uuid"] = uuid,
        ["X-Kong-Debug"] = "true",
        ["Host"] = "debug_logging.com"
      }
    }))
    assert.res_status(200, res)

    helpers.wait_until(function()
      return pl_path.exists(FILE_LOG_PATH) and pl_path.getsize(FILE_LOG_PATH) > 0
    end, 10)

    local file_log = pl_file.read(FILE_LOG_PATH)
    local log_message = cjson.decode(pl_stringx.strip(file_log))
    assert.same("127.0.0.1", log_message.client_ip)
    assert.same(uuid, log_message.request.headers["debug-log-uuid"])

    os.remove(FILE_LOG_PATH)
  end)

  it("does not to file", function()
    local uuid = utils.random_string()

    -- Making the request
    local res = assert(client:send({
      method = "GET",
      path = "/status/200",
      headers = {
        ["debug-log-uuid"] = uuid,
        ["X-Kong-Debug"] = "false",
        ["Host"] = "debug_logging.com"
      }
    }))
    assert.res_status(200, res)

    helpers.wait_until(function()
      return pl_path.exists(FILE_LOG_PATH) and pl_path.getsize(FILE_LOG_PATH) > 0
    end, 10)

    local file_log = pl_file.read(FILE_LOG_PATH)
    local log_message = cjson.decode(pl_stringx.strip(file_log))
    assert.not_equal(uuid, log_message.request.headers["debug-log-uuid"]) -- actually, shouldn't have anything

    os.remove(FILE_LOG_PATH)
  end)
 
end)
