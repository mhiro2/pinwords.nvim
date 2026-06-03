---@class PinwordsSlot
---@field raw string
---@field pattern string
---@field hl_group string
---@field whole_word boolean   -- match semantics captured at pin time
---@field case_sensitive boolean

---@class PinwordsCwordState
---@field enabled boolean
---@field match_id? integer
---@field pattern? string

---@class PinwordsWinState
---@field match_ids table<integer, integer>
---@field cword PinwordsCwordState

---@class PinwordsGlobalState
---@field slots table<integer, PinwordsSlot>
---@field order? integer[]
---@field last_used? table<integer, integer>
---@field tick? integer

local allocation = require("pinwords.state.allocation")
local global_state = require("pinwords.state.global")
local window_state = require("pinwords.state.window")

local M = {}

---@return nil
function M.flush_sync()
  global_state.flush_sync()
end

---@return nil
function M.init_global_state()
  global_state.init()
end

---@param max_slots integer
---@return nil
function M.prune_global_state(max_slots)
  global_state.prune(max_slots)
end

---@return table<integer, PinwordsSlot>
function M.get_slots()
  return global_state.get_slots()
end

---@param slots table<integer, PinwordsSlot>
---@return nil
function M.set_slots(slots)
  global_state.set_slots(slots)
end

---@param slot integer
---@return nil
function M.touch_slot(slot)
  global_state.touch_slot(slot)
end

---@param slot integer
---@param entry PinwordsSlot
---@return nil
function M.set_slot(slot, entry)
  global_state.set_slot(slot, entry)
end

---@param slot integer
---@return nil
function M.clear_slot(slot)
  global_state.clear_slot(slot)
end

---@return nil
function M.clear_all()
  global_state.clear_all()
end

---@param raw_or_pattern string
---@return integer|nil
function M.find_slot_by_raw_or_pattern(raw_or_pattern)
  return global_state.find_slot_by_raw_or_pattern(raw_or_pattern)
end

---@param raw string
---@param pattern_text string
---@return integer|nil
function M.find_slot_by_raw_and_pattern(raw, pattern_text)
  return global_state.find_slot_by_raw_and_pattern(raw, pattern_text)
end

---@param raw string
---@return integer[]
function M.find_slots_by_raw(raw)
  return global_state.find_slots_by_raw(raw)
end

---@param strategy string
---@param max_slots integer
---@return integer|nil
function M.find_available_slot(strategy, max_slots)
  return allocation.find_available_slot(strategy, max_slots)
end

---@param policy string
---@return integer|nil
function M.evict_slot(policy)
  return allocation.evict_slot(policy)
end

---@param win integer
---@return PinwordsWinState
function M.get_win_state(win)
  return window_state.get(win)
end

---@param win integer
---@param win_state PinwordsWinState
---@return nil
function M.set_win_state(win, win_state)
  window_state.set(win, win_state)
end

---@param win integer
---@return nil
function M.clear_win_state(win)
  window_state.clear(win)
end

---@return nil
function M.teardown()
  global_state.teardown()
  window_state.clear_all()
end

return M
