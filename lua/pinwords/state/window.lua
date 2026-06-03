local M = {}

-- Per-window ephemeral state lives in this module-local table (never persisted
-- across sessions). Entries are dropped on WinClosed via M.clear. Keeping this
-- in-memory avoids the VimL<->Lua (de)serialization that window variables incur
-- and matches the storage mechanism used by the cword runtime and flash.
---@type table<integer, PinwordsWinState>
local win_states = {}

---@param win integer
---@return PinwordsWinState
local function ensure_win_state(win)
  local win_state = win_states[win]

  if type(win_state) ~= "table" then
    win_state = { match_ids = {}, cword = { enabled = false } }
    win_states[win] = win_state
  end

  if type(win_state.match_ids) ~= "table" then
    win_state.match_ids = {}
  end

  if type(win_state.cword) ~= "table" then
    win_state.cword = { enabled = false }
  end

  if win_state.cword.enabled == nil then
    win_state.cword.enabled = false
  end

  return win_state
end

---@param win integer
---@return PinwordsWinState
function M.get(win)
  return ensure_win_state(win)
end

-- Stored by reference (no copy) to keep the get/mutate/set round-trip on the
-- hot path allocation-free. This facade is plugin-internal: callers obtain a
-- table via M.get and write back the same table for that window, so a single
-- table is never shared across windows.
---@param win integer
---@param win_state PinwordsWinState
---@return nil
function M.set(win, win_state)
  win_states[win] = win_state
end

---@param win integer
---@return nil
function M.clear(win)
  win_states[win] = nil
end

---@return nil
function M.clear_all()
  win_states = {}
end

return M
