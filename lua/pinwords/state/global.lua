local M = {}

---@type PinwordsGlobalState
local global_state = {
  slots = {},
}

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

  return key_count == #order
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
  if type(slots) ~= "table" or not validate_slots_table(slots) then
    return false
  end

  if state.order ~= nil then
    if type(state.order) ~= "table" or not validate_order_table(state.order, slots) then
      return false
    end
  end

  if state.last_used ~= nil then
    if type(state.last_used) ~= "table" or not validate_last_used_table(state.last_used, slots) then
      return false
    end
  end

  if state.tick ~= nil and not validate_tick(state.tick, state.last_used) then
    return false
  end

  return true
end

---@return integer[]
local function ensure_order()
  if type(global_state.order) ~= "table" then
    global_state.order = {}
  end
  return global_state.order
end

---@return table<integer, integer>
local function ensure_last_used()
  if type(global_state.last_used) ~= "table" then
    global_state.last_used = {}
  end
  return global_state.last_used
end

---@return integer
local function ensure_tick()
  local tick = type(global_state.tick) == "number" and global_state.tick or 0

  if type(global_state.last_used) == "table" then
    for _, value in pairs(global_state.last_used) do
      if type(value) == "number" and value > tick then
        tick = value
      end
    end
  end

  global_state.tick = tick
  return tick
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

---Force immediate sync if pending.
---@return nil
function M.flush_sync()
  if sync_pending then
    do_sync()
  end
end

---Initialize global state from vim.g or create new.
---@return nil
function M.init()
  if sync_pending then
    do_sync()
  end

  local ok, saved = pcall(vim.api.nvim_get_var, "pinwords_global")
  if ok and type(saved) == "table" then
    if validate_global_state(saved) then
      global_state = saved
    else
      vim.notify("pinwords: saved state is invalid, resetting", vim.log.levels.WARN)
      global_state = { slots = {} }
    end
  else
    global_state = { slots = {} }
  end

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

---@param max_slots integer
---@return nil
function M.prune(max_slots)
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

---@return table<integer, PinwordsSlot>
function M.get_slots()
  return global_state.slots
end

---@return integer[]|nil
function M.get_order()
  return global_state.order
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
  local order = ensure_order()
  remove_value(order, slot)
  table.insert(order, slot)

  local last_used = ensure_last_used()
  local tick = ensure_tick() + 1
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
function M.find_slot_by_raw_and_pattern(raw, pattern_text)
  for slot, entry in pairs(global_state.slots) do
    if entry.raw == raw and entry.pattern == pattern_text then
      return slot
    end
  end
  return nil
end

---@param raw string
---@return integer[]
function M.find_slots_by_raw(raw)
  local slots = {}

  for slot, entry in pairs(global_state.slots) do
    if entry.raw == raw then
      slots[#slots + 1] = slot
    end
  end

  table.sort(slots)
  return slots
end

---Reset global state and remove the vim.g variable.
---@return nil
function M.teardown()
  sync_pending = false
  global_state = { slots = {} }
  pcall(vim.api.nvim_del_var, "pinwords_global")
end

return M
