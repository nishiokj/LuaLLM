-- File: lua/yourplugin/config.lua
local M = {}

M.defaults = {
  zig_server_path = "zig-server",  -- default command; users can override with a full path if needed
  zig_port = 12345,
  zig_host = "127.0.0.1",
}

return M

