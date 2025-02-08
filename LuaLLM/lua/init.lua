-- File: lua/yourplugin/init.lua
local uv = vim.loop
local config = require("yourplugin.config").defaults

local M = {}

-- Allow users to override default configuration.
function M.setup(user_config)
  if user_config then
    for k, v in pairs(user_config) do
      config[k] = v
    end
  end
end

-- Starts the Zig server as a Neovim job.
function M.start_zig_server()
  local args = { "--port", tostring(config.zig_port) }
  local job_id = vim.fn.jobstart({ config.zig_server_path, unpack(args) }, {
    on_stdout = function(_, data, _)
      if data then
        vim.schedule(function() print("Zig server stdout:\n" .. table.concat(data, "\n")) end)
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        vim.schedule(function() print("Zig server stderr:\n" .. table.concat(data, "\n")) end)
      end
    end,
    on_exit = function(_, exit_code, _)
      vim.schedule(function() print("Zig server exited with code: " .. exit_code) end)
    end,
  })

  if job_id <= 0 then
    vim.notify("Failed to start Zig server job", vim.log.levels.ERROR)
  else
    vim.notify("Zig server started (job id " .. job_id .. ")")
  end
end

-- TCP Client for connecting to the Zig server.
local client = uv.new_tcp()

function M.connect_to_zig()
  client:connect(config.zig_host, config.zig_port, function(err)
    if err then
      return vim.schedule(function() vim.notify("Error connecting to Zig server: " .. err, vim.log.levels.ERROR) end)
    end
    vim.schedule(function() vim.notify("Connected to Zig server at " .. config.zig_host .. ":" .. config.zig_port) end)
    client:read_start(function(err, chunk)
      if err then
        return vim.schedule(function() vim.notify("Error reading from Zig server: " .. err, vim.log.levels.ERROR) end)
      end
      if chunk then
        vim.schedule(function() print("Received from Zig server: " .. chunk) end)
      else
        vim.schedule(function() vim.notify("Zig server closed the connection", vim.log.levels.WARN) end)
        client:close()
      end
    end)
  end)
end

function M.send_to_zig(input)
  if not client then
    return vim.notify("No TCP client available to send data", vim.log.levels.ERROR)
  end
  client:write(input, function(err)
    if err then
      vim.schedule(function() vim.notify("Error sending data: " .. err, vim.log.levels.ERROR) end)
    else
      vim.schedule(function() print("Data sent to Zig server") end)
    end
  end)
end

return M

