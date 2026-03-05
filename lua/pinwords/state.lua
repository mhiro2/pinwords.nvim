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

local sync_pending = false

local function do_sync()
  sync_pending = false
  local ok, err = pcall(vim.api.nvim_set_var, "pinwords_global", global_state)
  if not ok then
    vim.notify("pinwords: failed to sync global state: " .. tostring(err), vim.log.levels.WARN)
  end
end

local function schedule_sync()
  if sync_pending then
    return
  end
  sync_pending = true
  vim.schedule(do_sync)
end

--- Force immediate sync if pending (for testing)
function M.flush_sync()
  if sync_pending then
    do_sync()
  end
end

---@param list integer[]
---@param value integer
local function remove_value(list, value)
  for i = 1, #list do
    if list[i] == value then
      table.remove(list, i)
      return
    end
  end
end

---@param value any
---@return boolean
local function is_positive_integer(value)
  return type(value) == "number" and value % 1 == 0 and value >= 1
end

---@param value any
---@return boolean
local function is_non_negative_integer(value)
  return type(value) == "number" and value % 1 == 0 and value >= 0
end

---@param entry any
---@return boolean
local function validate_slot_entry(entry)
  return type(entry) == "table"
    and type(entry.raw) == "string"
    and type(entry.pattern) == "string"
    and type(entry.hl_group) == "string"
end

---@param slots table
---@return boolean
local function validate_slots_table(slots)
  for slot, entry in pairs(slots) do
    if not is_positive_integer(slot) then
      return false
    end
    if not validate_slot_entry(entry) then
      return false
    end
  end
  return true
end

---@param order table
---@param slots table
---@return boolean
local function validate_order_table(order, slots)
  local seen = {}
  local key_count = 0
  for i = 1, #order do
    local slot = order[i]
    if not is_positive_integer(slot) then
      return false
    end
    if slots[slot] == nil or seen[slot] then
      return false
    end
    seen[slot] = true
  end

  for key in pairs(order) do
    if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
      return false
    end
    key_count = key_count + 1
  end
  if key_count ~= #order then
    return false
  end
  return true
end

---@param last_used table
---@param slots table
---@return boolean
local function validate_last_used_table(last_used, slots)
  for slot, used_tick in pairs(last_used) do
    if not is_positive_integer(slot) then
      return false
    end
    if slots[slot] == nil then
      return false
    end
    if not is_non_negative_integer(used_tick) then
      return false
    end
  end
  return true
end

---@param tick any
---@param last_used table|nil
---@return boolean
local function validate_tick(tick, last_used)
  if not is_non_negative_integer(tick) then
    return false
  end
  if type(last_used) ~= "table" then
    return true
  end
  for _, used_tick in pairs(last_used) do
    if used_tick > tick then
      return false
    end
  end
  return true
end

---@param state table
---@return boolean
local function validate_global_state(state)
  if type(state) ~= "table" then
    return false
  end
  local slots = state.slots
  if type(slots) ~= "table" then
    return false
  end

  if not validate_slots_table(slots) then
    return false
  end

  if state.order ~= nil then
    if type(state.order) ~= "table" then
      return false
    end
    if not validate_order_table(state.order, slots) then
      return false
    end
  end

  if state.last_used ~= nil then
    if type(state.last_used) ~= "table" then
      return false
    end
    if not validate_last_used_table(state.last_used, slots) then
      return false
    end
  end

  if state.tick ~= nil and not validate_tick(state.tick, state.last_used) then
    return false
  end

  return true
end

---Initialize global state from vim.g or create new.
---@return nil
function M.init_global_state()
  -- Flush any pending sync to ensure we load the latest state
  if sync_pending then
    do_sync()
  end
  local ok, saved = pcall(vim.api.nvim_get_var, "pinwords_global")
  if ok and type(saved) == "table" then
    -- Validate saved state in detail
    if validate_global_state(saved) then
      global_state = saved
    else
      vim.notify("pinwords: saved state is invalid, resetting", vim.log.levels.WARN)
      global_state = { slots = {} }
    end
  else
    global_state = { slots = {} }
  end

  -- Validate each field
  if type(global_state.slots) ~= "table" then
    global_state.slots = {}
  end
  if type(global_state.order) ~= "table" then
    global_state.order = {}
  end
  if type(global_state.last_used) ~= "table" then
    global_state.last_used = {}
  end
  if type(global_state.tick) ~= "number" then
    global_state.tick = 0
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

---Remove slots exceeding max_slots from global state.
---@param max_slots integer Maximum number of slots to keep.
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
    schedule_sync()
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
  local ok, win_state = pcall(vim.api.nvim_win_get_var, win, "pinwords")
  local needs_update = false

  if not ok or type(win_state) ~= "table" then
    win_state = { match_ids = {}, cword = { enabled = false } }
    needs_update = true
  end

  if type(win_state.match_ids) ~= "table" then
    win_state.match_ids = {}
    needs_update = true
  end

  if type(win_state.cword) ~= "table" then
    win_state.cword = { enabled = false }
    needs_update = true
  end

  if win_state.cword.enabled == nil then
    win_state.cword.enabled = false
    needs_update = true
  end

  if needs_update then
    local set_ok = pcall(vim.api.nvim_win_set_var, win, "pinwords", win_state)
    -- Window may become invalid before we can set the state.
    -- Return the initialized state anyway for consistency.
    local _ = set_ok
  end

  return win_state
end

---@return table<integer, PinwordsSlot>
function M.get_slots()
  return global_state.slots
end

---@param slots table<integer, PinwordsSlot>
---@return nil
function M.set_slots(slots)
  global_state.slots = slots
  schedule_sync()
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

  schedule_sync()
end

---@param slot integer
---@param entry PinwordsSlot
---@return nil
function M.set_slot(slot, entry)
  global_state.slots[slot] = entry
  schedule_sync()
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
  schedule_sync()
end

---@return nil
function M.clear_all()
  global_state.slots = {}
  global_state.order = {}
  global_state.last_used = {}
  global_state.tick = 0
  schedule_sync()
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

---@param raw string
---@param pattern_text string
---@return integer|nil
function M.find_slot_by_raw_or_pattern_pair(raw, pattern_text)
  for slot, entry in pairs(global_state.slots) do
    if entry.raw == raw or entry.pattern == pattern_text then
      return slot
    end
  end
  return nil
end

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

  local order = global_state.order
  if type(order) == "table" and #order > 0 then
    return order[1]
  end

  -- Fallback: return any slot
  for slot in pairs(global_state.slots) do
    return slot
  end
  return nil
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
---@param win_state PinwordsWinState
---@return nil
function M.set_win_state(win, win_state)
  pcall(vim.api.nvim_win_set_var, win, "pinwords", win_state)
end

---Reset global state and remove the vim.g variable.
---@return nil
function M.teardown()
  global_state = { slots = {} }
  pcall(vim.api.nvim_del_var, "pinwords_global")
end

return M
