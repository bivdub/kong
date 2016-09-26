-- Copyright (C) Mashape, Inc.
local ffi = require "ffi"
local cjson = require "cjson"
local system_constants = require "lua_system_constants"
local debug_serializer = require "kong.plugins.log-serializers.debug"
local BasePlugin = require "kong.plugins.base_plugin"

local ngx_log = ngx.log
local ngx_log_ERR = ngx.ERR
local string_find = string.find
local req_read_body = ngx.req.read_body
local req_get_headers = ngx.req.get_headers
local req_get_body_data = ngx.req.get_body_data
local req_get_post_args = ngx.req.get_post_args
local pcall = pcall

local ngx_timer = ngx.timer.at
local string_len = string.len
local O_CREAT = system_constants.O_CREAT()
local O_WRONLY = system_constants.O_WRONLY()
local O_APPEND = system_constants.O_APPEND()
local S_IRUSR = system_constants.S_IRUSR()
local S_IWUSR = system_constants.S_IWUSR()
local S_IRGRP = system_constants.S_IRGRP()
local S_IROTH = system_constants.S_IROTH()

local oflags = bit.bor(O_WRONLY, O_CREAT, O_APPEND)
local mode = bit.bor(S_IRUSR, S_IWUSR, S_IRGRP, S_IROTH)

ffi.cdef[[
int open(char * filename, int flags, int mode);
int write(int fd, void * ptr, int numbytes);
char *strerror(int errnum);
]]

-- fd tracking utility functions
local file_descriptors = {}

local function get_fd(conf_path)
  return file_descriptors[conf_path]
end

local function set_fd(conf_path, file_descriptor)
  file_descriptors[conf_path] = file_descriptor
end

local function string_to_char(str)
  return ffi.cast("uint8_t*", str)
end

-- Log to a file. Function used as callback from an nginx timer.
-- @param `premature` see OpenResty `ngx.timer.at()`
-- @param `conf`     Configuration table, holds http endpoint details
-- @param `message`  Message to be logged
local function log(premature, conf, message)
  if premature then return end

  local msg = cjson.encode(message).."\n"

  local fd = get_fd(conf.path)
  if not fd then
    fd = ffi.C.open(string_to_char(conf.path), oflags, mode)
    if fd < 0 then
      local errno = ffi.errno()
      ngx.log(ngx.ERR, "[debug-log] failed to open the file: ", ffi.string(ffi.C.strerror(errno)))
    else
      set_fd(conf.path, fd)
    end
  end

  ffi.C.write(fd, string_to_char(msg), string_len(msg))
end

local DebugLogHandler = BasePlugin:extend()

DebugLogHandler.PRIORITY = 1

function DebugLogHandler:new()
  DebugLogHandler.super.new(self, "debug-log")
end

function DebugLogHandler:access(conf)
  DebugLogHandler.super.access(self)

  local req_body, res_body = "", ""
  local req_post_args = {}
  local headers = req_get_headers()

  if headers[conf.header_name] == "true" then
    req_read_body()
    req_body = req_get_body_data()

    if content_type and string_find(content_type:lower(), "application/x-www-form-urlencoded", nil, true) then
      local status, res = pcall(req_get_post_args)
      if not status then
        if res == "requesty body in temp file not supported" then
          ngx_log(ngx_log_ERR, "[debug-log] cannot read request body from temporary file. Try increasing the client_body_buffer_size directive.")
        else
          ngx_log(ngx_log_ERR, res)
        end
      else
        req_post_args = res
      end
    end

    -- keep in memory the bodies for this request
    ngx.ctx.debug_log = {
      req_body = req_body,
      res_body = res_body,
      req_post_args = req_post_args
    }
  end
end

function DebugLogHandler:body_filter(conf)
 DebugLogHandler.super.body_filter(self)
  local headers = req_get_headers()

  if headers[conf.header_name] == "true" then
    local chunk = ngx.arg[1]
    local debug_data = ngx.ctx.debug_log or {res_body = ""} -- minimize the number of calls to ngx.ctx while fallbacking on default value
    debug_data.res_body = debug_data.res_body..chunk
    ngx.ctx.debug_log = debug_data
  end
end

function DebugLogHandler:log(conf)
  local headers = req_get_headers()

  if headers[conf.header_name] == "true" then
    DebugLogHandler.super.log(self)
    local message = debug_serializer.serialize(ngx)

    local ok, err = ngx_timer(0, log, conf, message)
    if not ok then
      ngx.log(ngx.ERR, "[debug-log] failed to create timer: ", err)
    end
  end
end

return DebugLogHandler
