local M = {}

---@class PinwordsFlashConfig
---@field enabled boolean
---@field timeout_ms integer
---@field hl_group string
---@field priority integer

---@class PinwordsFlashWinState
---@field match_id integer|nil
---@field timer uv.uv_timer_t|nil

---@type PinwordsFlashConfig
local default_config = {
  enabled = true,
  timeout_ms = 120,
  hl_group = "PinWordFlash",
  priority = 250,
}

---@type PinwordsFlashConfig
local config = vim.deepcopy(default_config)

---@type table<integer, PinwordsFlashWinState>
local win_states = {}

---@param timer uv.uv_timer_t|nil
---@return nil
local function stop_timer(timer)
  if not timer then
    return
  end
  pcall(function()
    timer:stop()
  end)
  pcall(function()
    timer:close()
  end)
end

---@param win integer
---@param fn fun(): any
---@return any
local function with_win(win, fn)
  return vim.api.nvim_win_call(win, fn)
end

---@param win integer
---@param match_id integer
---@return nil
local function delete_match_id(win, match_id)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  pcall(with_win, win, function()
    vim.fn.matchdelete(match_id)
  end)
end

---@param win integer
---@return nil
local function clear_window(win)
  local win_state = win_states[win]
  if type(win_state) ~= "table" then
    return
  end

  if type(win_state.match_id) == "number" then
    delete_match_id(win, win_state.match_id)
  end

  stop_timer(win_state.timer)
  win_states[win] = nil
end

---@param cfg PinwordsFlashConfig
---@return nil
function M.setup(cfg)
  if type(cfg) ~= "table" then
    cfg = {}
  end
  config = vim.tbl_deep_extend("force", default_config, cfg)
  if not config.enabled then
    M.clear_all()
  end
end

---@param win integer
---@param pattern string
---@param hl_group? string
---@param priority? integer
---@param timeout_ms? integer
---@return nil
function M.flash_pattern(win, pattern, hl_group, priority, timeout_ms)
  if not config.enabled then
    return
  end
  if type(win) ~= "number" or not vim.api.nvim_win_is_valid(win) then
    return
  end
  if type(pattern) ~= "string" or pattern == "" then
    return
  end

  clear_window(win)

  local group = hl_group or config.hl_group
  local flash_priority = priority or config.priority
  local duration = timeout_ms or config.timeout_ms

  local ok_match, match_id = pcall(with_win, win, function()
    return vim.fn.matchadd(group, pattern, flash_priority)
  end)
  if not ok_match or type(match_id) ~= "number" then
    return
  end

  local ok_timer, timer = pcall(vim.uv.new_timer)
  if not ok_timer or not timer then
    delete_match_id(win, match_id)
    return
  end

  win_states[win] = {
    match_id = match_id,
    timer = timer,
  }

  timer:start(
    duration,
    0,
    vim.schedule_wrap(function()
      local win_state = win_states[win]
      if not win_state or win_state.timer ~= timer then
        stop_timer(timer)
        return
      end
      clear_window(win)
    end)
  )
end

---@param win integer
---@return nil
function M.clear_for_window(win)
  clear_window(win)
end

---@return nil
function M.clear_all()
  for win in pairs(win_states) do
    clear_window(win)
  end
end

return M
