---@class PinwordsSlot
---@field raw string
---@field pattern string
---@field hl_group string

---@class PinwordsBufState
---@field slots table<integer, PinwordsSlot>
---@field order? integer[]
---@field last_used? table<integer, integer>
---@field tick? integer

---@class PinwordsWinState
---@field match_ids table<integer, integer>
---@field cword PinwordsCwordState

---@class PinwordsCwordState
---@field enabled boolean
---@field match_id? integer
---@field pattern? string

---@class PinwordsGlobalState
---@field slots table<integer, PinwordsSlot>
---@field order? integer[]
---@field last_used? table<integer, integer>
---@field tick? integer

---@type PinwordsGlobalState
local global_state = {
  slots = {},
}

local M = {}

---@param list integer[]
---@param value integer
local function remove_value(list, value)
  for i = #list, 1, -1 do
    if list[i] == value then
      table.remove(list, i)
    end
  end
end

local function sync_global_state()
  vim.api.nvim_set_var("pinwords_global", global_state)
end

-- Initialize global state from vim.g or create new
function M.init_global_state()
  local ok, saved = pcall(vim.api.nvim_get_var, "pinwords_global")
  if ok and type(saved) == "table" then
    global_state = saved
  else
    global_state = { slots = {} }
  end

  if type(global_state.slots) ~= "table" then
    global_state.slots = {}
  end
end

---@param field table
---@param max_slots integer
---@return boolean
local function prune_table_slots(field, max_slots)
  local changed = false
  for slot in pairs(field) do
    if type(slot) == "number" and slot > max_slots then
      field[slot] = nil
      changed = true
    end
  end
  return changed
end

---@param max_slots integer
---@return nil
function M.prune_global_state(max_slots)
  if type(max_slots) ~= "number" then
    return
  end

  local changed = false

  if type(global_state.slots) == "table" then
    changed = prune_table_slots(global_state.slots, max_slots) or changed
  end

  if type(global_state.order) == "table" then
    for i = #global_state.order, 1, -1 do
      local slot = global_state.order[i]
      if type(slot) == "number" and slot > max_slots then
        table.remove(global_state.order, i)
        changed = true
      end
    end
  end

  if type(global_state.last_used) == "table" then
    changed = prune_table_slots(global_state.last_used, max_slots) or changed
  end

  if changed then
    sync_global_state()
  end
end

---@param state PinwordsBufState
---@return integer[]
local function ensure_order(state)
  if type(state.order) ~= "table" then
    state.order = {}
  end
  return state.order
end

---@param state PinwordsBufState
---@return table<integer, integer>
local function ensure_last_used(state)
  if type(state.last_used) ~= "table" then
    state.last_used = {}
  end
  return state.last_used
end

---@param state PinwordsBufState
---@return integer
local function ensure_tick(state)
  local tick = type(state.tick) == "number" and state.tick or 0

  -- Migration/compat: older versions used os.time() for last_used.
  -- Ensure tick never goes backwards relative to existing last_used values.
  if type(state.last_used) == "table" then
    for _, v in pairs(state.last_used) do
      if type(v) == "number" and v > tick then
        tick = v
      end
    end
  end

  state.tick = tick
  return tick
end

---@param win integer
---@return PinwordsWinState
local function ensure_win_state(win)
  local ok, state = pcall(vim.api.nvim_win_get_var, win, "pinwords")
  local needs_update = false

  if not ok or type(state) ~= "table" then
    state = { match_ids = {}, cword = { enabled = false } }
    needs_update = true
  end

  if type(state.match_ids) ~= "table" then
    state.match_ids = {}
    needs_update = true
  end

  if type(state.cword) ~= "table" then
    state.cword = { enabled = false }
    needs_update = true
  end

  if state.cword.enabled == nil then
    state.cword.enabled = false
    needs_update = true
  end

  if needs_update then
    vim.api.nvim_win_set_var(win, "pinwords", state)
  end

  return state
end

---@return table<integer, PinwordsSlot>
function M.get_slots()
  return global_state.slots
end

---@param slots table<integer, PinwordsSlot>
---@return nil
function M.set_slots(slots)
  global_state.slots = slots
  sync_global_state()
end

---@param slot integer
---@return nil
function M.touch_slot(slot)
  local order = ensure_order(global_state)
  remove_value(order, slot)
  table.insert(order, slot)

  local last_used = ensure_last_used(global_state)
  local tick = ensure_tick(global_state) + 1
  global_state.tick = tick
  last_used[slot] = tick

  sync_global_state()
end

---@param slot integer
---@param entry PinwordsSlot
---@return nil
function M.set_slot(slot, entry)
  global_state.slots[slot] = entry
  sync_global_state()
end

---@param slot integer
---@return nil
function M.clear_slot(slot)
  global_state.slots[slot] = nil
  if type(global_state.order) == "table" then
    remove_value(global_state.order, slot)
  end
  if type(global_state.last_used) == "table" then
    global_state.last_used[slot] = nil
  end
  sync_global_state()
end

---@return nil
function M.clear_all()
  global_state.slots = {}
  global_state.order = {}
  global_state.last_used = {}
  global_state.tick = 0
  sync_global_state()
end

---@param raw_or_pattern string
---@return integer|nil
function M.find_slot_by_raw_or_pattern(raw_or_pattern)
  for slot, entry in pairs(global_state.slots) do
    if entry.raw == raw_or_pattern or entry.pattern == raw_or_pattern then
      return slot
    end
  end
  return nil
end

-- Backward-compatible alias (this function matches both raw and pattern).
-- Prefer find_slot_by_raw_or_pattern for clarity.
---@deprecated
M.find_slot_by_pattern = M.find_slot_by_raw_or_pattern

---@param max_slots integer
---@return integer|nil
local function find_first_empty_slot(max_slots)
  local slots = global_state.slots
  for slot = 1, max_slots do
    if slots[slot] == nil then
      return slot
    end
  end
  return nil
end

---@param max_slots integer
---@return integer|nil
local function find_cycle_slot(max_slots)
  local order = global_state.order
  local last_slot = type(order) == "table" and order[#order] or nil
  if not last_slot then
    return find_first_empty_slot(max_slots)
  end

  local slots = global_state.slots
  for offset = 1, max_slots do
    local slot = ((last_slot + offset - 1) % max_slots) + 1
    if slots[slot] == nil then
      return slot
    end
  end
  return nil
end

---@param max_slots integer
---@return integer|nil
local function find_lru_slot(max_slots)
  local empty = find_first_empty_slot(max_slots)
  if empty then
    return empty
  end

  local slots = global_state.slots
  local last_used = global_state.last_used
  if type(last_used) == "table" then
    local oldest_slot
    local oldest_time
    for slot in pairs(slots) do
      local ts = last_used[slot] or 0
      if not oldest_time or ts < oldest_time then
        oldest_time = ts
        oldest_slot = slot
      end
    end
    if oldest_slot then
      return oldest_slot
    end
  end

  local order = global_state.order
  if type(order) == "table" and #order > 0 then
    return order[1]
  end

  local fallback
  for slot in pairs(slots) do
    if not fallback or slot < fallback then
      fallback = slot
    end
  end
  return fallback
end

---@param strategy string
---@param max_slots integer
---@return integer|nil
function M.find_available_slot(strategy, max_slots)
  if strategy == "cycle" then
    return find_cycle_slot(max_slots)
  elseif strategy == "lru" then
    return find_lru_slot(max_slots)
  else
    return find_first_empty_slot(max_slots)
  end
end

---@param policy string
---@return integer|nil
function M.evict_slot(policy)
  if policy == "no_op" then
    return nil
  end

  local slots = global_state.slots
  local order = global_state.order

  if type(order) == "table" and #order > 0 then
    if policy == "replace_oldest" then
      return order[1]
    end
    if policy == "replace_last" then
      return order[#order]
    end
  end

  local fallback
  for slot in pairs(slots) do
    if not fallback or slot < fallback then
      fallback = slot
    end
  end

  return fallback
end

---@param win integer
---@return PinwordsWinState
function M.get_win_state(win)
  return ensure_win_state(win)
end

---@param win integer
---@param state PinwordsWinState
---@return nil
function M.set_win_state(win, state)
  vim.api.nvim_win_set_var(win, "pinwords", state)
end

return M
