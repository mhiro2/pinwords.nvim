local matcher = require("pinwords.matcher")
local state = require("pinwords.state")

local M = {}

---@class PinwordsCwordRuntimeConfig
---@field build_pattern fun(raw: string): string
---@field debounce_ms integer

---@type PinwordsCwordRuntimeConfig
local config = {
  build_pattern = function(raw)
    return raw
  end,
  debounce_ms = 50,
}

---@type table<integer, boolean>
local enabled_wins = {}

---@type table<integer, uv.uv_timer_t>
local timers = {}

-- Per-window debounce generation. Bumped on every (re)start so a callback that
-- was already scheduled before a restart can recognize itself as stale. The
-- timer handle is reused, so `timers[win] == timer` alone cannot detect this.
---@type table<integer, integer>
local generations = {}

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
---@return nil
local function clear_timer(win)
  stop_timer(timers[win])
  timers[win] = nil
  generations[win] = nil
end

---@return nil
local function clear_all_timers()
  for win in pairs(timers) do
    clear_timer(win)
  end
end

---@param win integer
---@return string
local function get_cword_for_window(win)
  local ok, raw = pcall(vim.api.nvim_win_call, win, function()
    return vim.fn.expand("<cword>")
  end)
  if not ok or type(raw) ~= "string" then
    return ""
  end
  return raw
end

---@param win integer
---@return nil
local function clear_window(win)
  clear_timer(win)

  local win_state = state.get_win_state(win)
  local cword_state = win_state.cword or { enabled = false }

  if cword_state.match_id then
    matcher.delete_match_id_for_window(win, cword_state.match_id)
  end

  cword_state.match_id = nil
  cword_state.pattern = nil
  cword_state.enabled = false
  win_state.cword = cword_state
  state.set_win_state(win, win_state)
  enabled_wins[win] = nil
end

---@param win integer
---@return nil
local function update_for_window(win)
  local win_state = state.get_win_state(win)
  local cword_state = win_state.cword
  if type(cword_state) ~= "table" or not cword_state.enabled then
    return
  end

  local raw = get_cword_for_window(win)
  local pattern_text = raw ~= "" and config.build_pattern(raw) or nil

  if cword_state.pattern == pattern_text then
    return
  end

  if pattern_text then
    local id = matcher.apply_cword_for_window(win, cword_state.match_id, pattern_text)
    cword_state.match_id = id
    cword_state.pattern = pattern_text
  else
    if cword_state.match_id then
      matcher.delete_match_id_for_window(win, cword_state.match_id)
    end
    cword_state.match_id = nil
    cword_state.pattern = nil
  end

  win_state.cword = cword_state
  state.set_win_state(win, win_state)
end

---@class PinwordsCwordRuntimeSetupOpts
---@field build_pattern? fun(raw: string): string
---@field debounce_ms? integer

---@param opts? PinwordsCwordRuntimeSetupOpts
---@return nil
function M.configure(opts)
  if type(opts) ~= "table" then
    return
  end

  if type(opts.build_pattern) == "function" then
    config.build_pattern = opts.build_pattern
  end

  if type(opts.debounce_ms) == "number" and opts.debounce_ms >= 0 then
    config.debounce_ms = math.floor(opts.debounce_ms)
  end
end

---@param win integer
---@return boolean
function M.is_enabled(win)
  if enabled_wins[win] ~= true then
    return false
  end
  if not vim.api.nvim_win_is_valid(win) then
    enabled_wins[win] = nil
    return false
  end
  return true
end

---@return nil
function M.cleanup_stale_windows()
  for win in pairs(enabled_wins) do
    if type(win) ~= "number" or not vim.api.nvim_win_is_valid(win) then
      enabled_wins[win] = nil
      clear_timer(win)
    end
  end
end

---@param win integer
---@return nil
function M.reapply_for_window(win)
  if not M.is_enabled(win) then
    return
  end
  update_for_window(win)
end

---@param win integer
---@return nil
function M.handle_cursor_moved(win)
  if next(enabled_wins) == nil then
    return
  end
  if not M.is_enabled(win) then
    return
  end

  -- Reuse a single timer per window: stop the pending fire and restart it.
  -- Avoids the new_timer/close churn on every CursorMoved during debounce.
  local timer = timers[win]
  if not timer then
    local ok, t = pcall(vim.uv.new_timer)
    if not ok or not t then
      return
    end
    timer = t
    timers[win] = timer
  else
    pcall(function()
      timer:stop()
    end)
  end

  -- Tag this debounce window. A callback whose generation no longer matches was
  -- scheduled before a later restart (the reused handle keeps timers[win] ==
  -- timer), so it must be skipped to avoid an early/duplicate update.
  local generation = (generations[win] or 0) + 1
  generations[win] = generation

  timer:start(
    config.debounce_ms,
    0,
    vim.schedule_wrap(function()
      if timers[win] ~= timer or generations[win] ~= generation then
        return
      end
      if not M.is_enabled(win) then
        return
      end

      update_for_window(win)
    end)
  )
end

---@param win integer
---@return nil
function M.toggle(win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  local win_state = state.get_win_state(win)
  local cword_state = win_state.cword or { enabled = false }
  local was_enabled = cword_state.enabled
  cword_state.enabled = not cword_state.enabled

  if not was_enabled and cword_state.enabled then
    enabled_wins[win] = true
    win_state.cword = cword_state
    state.set_win_state(win, win_state)
    update_for_window(win)
    return
  end

  if was_enabled and not cword_state.enabled then
    clear_window(win)
  end
end

---@return nil
function M.flush_current()
  local win = vim.api.nvim_get_current_win()
  clear_timer(win)
  if M.is_enabled(win) then
    update_for_window(win)
  end
end

---@param win integer
---@return nil
function M.handle_win_closed(win)
  enabled_wins[win] = nil
  clear_timer(win)
end

---@return nil
function M.clear_all()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      clear_window(win)
    end
  end
end

---@return nil
function M.teardown()
  clear_all_timers()
  M.clear_all()
  enabled_wins = {}
  generations = {}
end

return M
