-- File: lua/yourplugin/init.lua
local uv = vim.loop
local config = require("LuaLLM.config").defaults

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
function M.start_zig_server(callback)
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
        vim.schedule(function() M.write_string_at_cursor(chunk) end)
      
      else
        vim.schedule(function() vim.notify("Zig server closed the connection", vim.log.levels.WARN) end)
        client:close()
      end
    end)
      if callback then
      callback()
    end
  end)
end

function M.get_lines_until_cursor()
  local current_buffer = vim.api.nvim_get_current_buf()
  local current_window = vim.api.nvim_get_current_win()
  local cursor_position = vim.api.nvim_win_get_cursor(current_window)
  local row = cursor_position[1]

  local lines = vim.api.nvim_buf_get_lines(current_buffer, 0, row, true)

  return table.concat(lines, '\n')
end

function M.get_visual_selection()
  local _, srow, scol = unpack(vim.fn.getpos 'v')
  local _, erow, ecol = unpack(vim.fn.getpos '.')

  if vim.fn.mode() == 'V' then
    if srow > erow then
      return vim.api.nvim_buf_get_lines(0, erow - 1, srow, true)
    else
      return vim.api.nvim_buf_get_lines(0, srow - 1, erow, true)
    end
  end

  if vim.fn.mode() == 'v' then
    if srow < erow or (srow == erow and scol <= ecol) then
      return vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
    else
      return vim.api.nvim_buf_get_text(0, erow - 1, ecol - 1, srow - 1, scol, {})
    end
  end

  if vim.fn.mode() == '\22' then
    local lines = {}
    if srow > erow then
      srow, erow = erow, srow
    end
    if scol > ecol then
      scol, ecol = ecol, scol
    end
    for i = srow, erow do
      table.insert(lines, vim.api.nvim_buf_get_text(0, i - 1, math.min(scol - 1, ecol), i - 1, math.max(scol - 1, ecol), {})[1])
    end
    return lines
  end
end

function M.write_string_at_cursor(str)
  vim.schedule(function()
    local current_window = vim.api.nvim_get_current_win()
    local cursor_position = vim.api.nvim_win_get_cursor(current_window)
    local row, col = cursor_position[1], cursor_position[2]

    local lines = vim.split(str, '\n')

    vim.cmd("undojoin")
    vim.api.nvim_put(lines, 'c', true, true)

    local num_lines = #lines
    local last_line_length = #lines[num_lines]
    vim.api.nvim_win_set_cursor(current_window, { row + num_lines - 1, col + last_line_length })
  end)
end

local function get_prompt()
  
  local visual_lines = M.get_visual_selection()
  local prompt = ''
  if visual_lines then
    prompt = table.concat(visual_lines, '\n')
    if replace then
      vim.api.nvim_command 'normal! d'
    else
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
    end
  else
    prompt = M.get_lines_until_cursor()
  end

  return prompt
end


function M.trigger_zig()
  -- Gather input from the screen.
  -- You might adjust this to get a visual selection or other region.
  local input = get_prompt()
  local current_filepath = vim.api.nvim_buf_get_name(0)
  -- Format the prompt as: PROMPT 'current_filepath' + input
  local prompt_message = "PROMPT '" .. current_filepath .. "' + " .. input
  local function send_input()
    uv.write(client, prompt_message, function(err)
      if err then
        vim.schedule(function()
          vim.notify("Error sending data to Zig server: " .. err, vim.log.levels.ERROR)
        end)
      else
        vim.schedule(function() print("Input sent to Zig server") end)
      end
    end)
  end

  -- If the client is not yet connected, connect and then send.
  if not client:is_readable() then
    M.connect_to_zig(send_input)
  else
    send_input()
  end
end

return M

