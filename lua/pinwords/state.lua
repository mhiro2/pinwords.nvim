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

---@param buf integer
---@return PinwordsBufState
local function ensure_buf_state(buf)
  local ok, state = pcall(vim.api.nvim_buf_get_var, buf, "pinwords")
  if not ok or type(state) ~= "table" then
    state = { slots = {} }
    vim.api.nvim_buf_set_var(buf, "pinwords", state)
  end

  if type(state.slots) ~= "table" then
    state.slots = {}
    vim.api.nvim_buf_set_var(buf, "pinwords", state)
  end

  return state
end

---@param buf integer
---@param max_slots integer
---@return nil
function M.prune_buf_state(buf, max_slots)
  if type(max_slots) ~= "number" then
    return
  end

  local ok, state = pcall(vim.api.nvim_buf_get_var, buf, "pinwords")
  if not ok or type(state) ~= "table" then
    return
  end

  local changed = false

  if type(state.slots) == "table" then
    for slot in pairs(state.slots) do
      if type(slot) == "number" and slot > max_slots then
        state.slots[slot] = nil
        changed = true
      end
    end
  end

  if type(state.order) == "table" then
    for i = #state.order, 1, -1 do
      local slot = state.order[i]
      if type(slot) == "number" and slot > max_slots then
        table.remove(state.order, i)
        changed = true
      end
    end
  end

  if type(state.last_used) == "table" then
    for slot in pairs(state.last_used) do
      if type(slot) == "number" and slot > max_slots then
        state.last_used[slot] = nil
        changed = true
      end
    end
  end

  if changed then
    vim.api.nvim_buf_set_var(buf, "pinwords", state)
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
  if not ok or type(state) ~= "table" then
    state = { match_ids = {}, cword = { enabled = false } }
    vim.api.nvim_win_set_var(win, "pinwords", state)
  end

  if type(state.match_ids) ~= "table" then
    state.match_ids = {}
    vim.api.nvim_win_set_var(win, "pinwords", state)
  end

  if type(state.cword) ~= "table" then
    state.cword = { enabled = false }
    vim.api.nvim_win_set_var(win, "pinwords", state)
  end

  if state.cword.enabled == nil then
    state.cword.enabled = false
    vim.api.nvim_win_set_var(win, "pinwords", state)
  end

  return state
end

---@param buf integer
---@return table<integer, PinwordsSlot>
function M.get_slots(buf)
  local state = ensure_buf_state(buf)
  return state.slots
end

---@param buf integer
---@param slots table<integer, PinwordsSlot>
---@return nil
function M.set_slots(buf, slots)
  local state = ensure_buf_state(buf)
  state.slots = slots
  vim.api.nvim_buf_set_var(buf, "pinwords", state)
end

---@param buf integer
---@param slot integer
---@return nil
function M.touch_slot(buf, slot)
  local state = ensure_buf_state(buf)
  local order = ensure_order(state)
  remove_value(order, slot)
  table.insert(order, slot)

  local last_used = ensure_last_used(state)
  local tick = ensure_tick(state) + 1
  state.tick = tick
  last_used[slot] = tick

  vim.api.nvim_buf_set_var(buf, "pinwords", state)
end

---@param buf integer
---@param slot integer
---@param entry PinwordsSlot
---@return nil
function M.set_slot(buf, slot, entry)
  local state = ensure_buf_state(buf)
  state.slots[slot] = entry
  vim.api.nvim_buf_set_var(buf, "pinwords", state)
end

---@param buf integer
---@param slot integer
---@return nil
function M.clear_slot(buf, slot)
  local state = ensure_buf_state(buf)
  state.slots[slot] = nil
  if type(state.order) == "table" then
    remove_value(state.order, slot)
  end
  if type(state.last_used) == "table" then
    state.last_used[slot] = nil
  end
  vim.api.nvim_buf_set_var(buf, "pinwords", state)
end

---@param buf integer
---@return nil
function M.clear_all(buf)
  local state = ensure_buf_state(buf)
  state.slots = {}
  if type(state.order) == "table" then
    state.order = {}
  end
  if type(state.last_used) == "table" then
    state.last_used = {}
  end
  state.tick = 0
  vim.api.nvim_buf_set_var(buf, "pinwords", state)
end

---@param buf integer
---@param raw_or_pattern string
---@return integer|nil
function M.find_slot_by_raw_or_pattern(buf, raw_or_pattern)
  local state = ensure_buf_state(buf)
  for slot, entry in pairs(state.slots) do
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

---@param buf integer
---@param strategy string
---@param max_slots integer
---@return integer|nil
function M.find_available_slot(buf, strategy, max_slots)
  local state = ensure_buf_state(buf)
  local slots = state.slots

  local function first_empty()
    for slot = 1, max_slots do
      if slots[slot] == nil then
        return slot
      end
    end
    return nil
  end

  if strategy == "cycle" then
    local order = state.order
    local last_slot = type(order) == "table" and order[#order] or nil
    if not last_slot then
      return first_empty()
    end
    for offset = 1, max_slots do
      local slot = ((last_slot + offset - 1) % max_slots) + 1
      if slots[slot] == nil then
        return slot
      end
    end
    return nil
  end

  if strategy == "lru" then
    local empty = first_empty()
    if empty then
      return empty
    end

    local last_used = state.last_used
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

    local order = state.order
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

  return first_empty()
end

---@param buf integer
---@param policy string
---@return integer|nil
function M.evict_slot(buf, policy)
  if policy == "no_op" then
    return nil
  end

  local state = ensure_buf_state(buf)
  local slots = state.slots
  local order = state.order

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

---@param buf integer
---@return nil
function M.clear_buf_state(buf)
  pcall(vim.api.nvim_buf_del_var, buf, "pinwords")
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
