local commands = require("pinwords.commands")
local highlight = require("pinwords.highlight")
local matcher = require("pinwords.matcher")
local pattern = require("pinwords.pattern")
local state = require("pinwords.state")

local M = {}

---@param msg string
local function warn(msg)
  vim.notify("pinwords: " .. msg, vim.log.levels.WARN)
end

---@class PinwordsConfig
---@field slots integer
---@field whole_word boolean
---@field case_sensitive boolean
---@field auto_allocation PinwordsAutoAllocation

---@class PinwordsAutoAllocation
---@field strategy PinwordsAutoAllocationStrategy
---@field on_full PinwordsAutoAllocationOnFull
---@field toggle_same boolean

---@alias PinwordsAutoAllocationStrategy
---| '"first_empty"'
---| '"cycle"'
---| '"lru"'

---@alias PinwordsAutoAllocationOnFull
---| '"replace_oldest"'
---| '"replace_last"'
---| '"no_op"'

---@class PinwordsSetOpts
---@field raw? string
---@field whole_word? boolean
---@field case_sensitive? boolean

---@type PinwordsConfig
local default_config = {
  slots = 9,
  whole_word = true,
  case_sensitive = false,
  auto_allocation = {
    strategy = "first_empty",
    on_full = "replace_oldest",
    toggle_same = true,
  },
}

---@type PinwordsConfig
local config = vim.deepcopy(default_config)

---@param opts? PinwordsConfig
---@return PinwordsConfig
local function sanitize_config(opts)
  local cfg = vim.tbl_deep_extend("force", default_config, opts or {})

  if type(cfg.slots) ~= "number" or cfg.slots < 1 or cfg.slots % 1 ~= 0 then
    warn("slots must be a positive integer; fallback to default")
    cfg.slots = default_config.slots
  end

  if type(cfg.whole_word) ~= "boolean" then
    warn("whole_word must be boolean; fallback to default")
    cfg.whole_word = default_config.whole_word
  end

  if type(cfg.case_sensitive) ~= "boolean" then
    warn("case_sensitive must be boolean; fallback to default")
    cfg.case_sensitive = default_config.case_sensitive
  end

  if type(cfg.auto_allocation) ~= "table" then
    warn("auto_allocation must be a table; fallback to default")
    cfg.auto_allocation = vim.deepcopy(default_config.auto_allocation)
  end

  local strategy = cfg.auto_allocation.strategy
  if strategy ~= "first_empty" and strategy ~= "cycle" and strategy ~= "lru" then
    warn("auto_allocation.strategy must be one of: first_empty, cycle, lru; fallback to default")
    cfg.auto_allocation.strategy = default_config.auto_allocation.strategy
  end

  local on_full = cfg.auto_allocation.on_full
  if on_full ~= "replace_oldest" and on_full ~= "replace_last" and on_full ~= "no_op" then
    warn("auto_allocation.on_full must be one of: replace_oldest, replace_last, no_op; fallback to default")
    cfg.auto_allocation.on_full = default_config.auto_allocation.on_full
  end

  if type(cfg.auto_allocation.toggle_same) ~= "boolean" then
    warn("auto_allocation.toggle_same must be boolean; fallback to default")
    cfg.auto_allocation.toggle_same = default_config.auto_allocation.toggle_same
  end

  return cfg
end

-- Windows where cword highlight is enabled.
-- Key: winid, Value: true
---@type table<integer, boolean>
local cword_enabled_wins = {}

---@param value any
---@param fallback any
---@return any
local function value_or(value, fallback)
  if value == nil then
    return fallback
  end
  return value
end

---@param slot integer
---@return boolean
local function valid_slot(slot)
  if type(slot) ~= "number" then
    vim.notify("pinwords: slot must be a number", vim.log.levels.WARN)
    return false
  end

  if slot < 1 or slot > config.slots then
    vim.notify("pinwords: slot must be between 1 and " .. config.slots, vim.log.levels.WARN)
    return false
  end

  return true
end

---@param opts? PinwordsSetOpts
---@param empty_message? string
---@return string|nil
local function resolve_raw(opts, empty_message)
  local raw = opts and opts.raw or vim.fn.expand("<cword>")
  if raw == "" then
    vim.notify(empty_message or "pinwords: no word to pin", vim.log.levels.WARN)
    return nil
  end
  return raw
end

---@param raw string
---@param opts? PinwordsSetOpts
---@return string
local function build_pattern(raw, opts)
  return pattern.build(raw, {
    whole_word = value_or(opts and opts.whole_word, config.whole_word),
    case_sensitive = value_or(opts and opts.case_sensitive, config.case_sensitive),
  })
end

---@param raw string
---@param slot integer
---@param opts? PinwordsSetOpts
---@return PinwordsSlot
local function build_entry(raw, slot, opts)
  local pattern_text = build_pattern(raw, opts)
  return {
    raw = raw,
    pattern = pattern_text,
    hl_group = "PinWord" .. slot,
  }
end

---@param win integer
local function update_cword_for_window(win)
  local win_state = state.get_win_state(win)
  local cword_state = win_state.cword
  if type(cword_state) ~= "table" or not cword_state.enabled then
    return
  end

  local raw = vim.fn.expand("<cword>")
  if raw == "" then
    if cword_state.match_id then
      matcher.delete_match_id_for_window(win, cword_state.match_id)
      cword_state.match_id = nil
    end
    cword_state.pattern = nil
    win_state.cword = cword_state
    state.set_win_state(win, win_state)
    return
  end

  local pattern_text = build_pattern(raw)
  if cword_state.pattern == pattern_text then
    return
  end

  local id = matcher.apply_cword_for_window(win, cword_state.match_id, pattern_text)
  cword_state.match_id = id
  cword_state.pattern = pattern_text
  win_state.cword = cword_state
  state.set_win_state(win, win_state)
end

---@param opts? PinwordsConfig
---@return nil
function M.setup(opts)
  config = sanitize_config(opts)

  highlight.apply(config.slots)
  commands.setup(config.slots)

  -- Prune existing state when slots are reduced (and keep order/last_used consistent).
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      state.prune_buf_state(buf, config.slots)
    end
  end

  -- Rebuild window-local matches from buffer state to reflect potential pruning.
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    matcher.reapply_all_for_window(win)
    if cword_enabled_wins[win] then
      update_cword_for_window(win)
    end
  end

  local group = vim.api.nvim_create_augroup("PinWords", { clear = true })

  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    group = group,
    callback = function(args)
      local win = args.win
      if type(win) ~= "number" or win == 0 then
        win = vim.api.nvim_get_current_win()
      end
      matcher.reapply_all_for_window(win)
      if cword_enabled_wins[win] then
        update_cword_for_window(win)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = function()
      if next(cword_enabled_wins) == nil then
        return
      end

      local win = vim.api.nvim_get_current_win()
      if not cword_enabled_wins[win] then
        return
      end
      update_cword_for_window(win)
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
      state.clear_buf_state(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      highlight.apply(config.slots)
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      local win = tonumber(args.match)
      if win then
        cword_enabled_wins[win] = nil
      end
    end,
  })
end

---@param slot? integer
---@param opts? PinwordsSetOpts
---@return nil
function M.set(slot, opts)
  if slot ~= nil then
    if not valid_slot(slot) then
      return
    end

    local raw = resolve_raw(opts)
    if not raw then
      return
    end

    local entry = build_entry(raw, slot, opts)
    local buf = vim.api.nvim_get_current_buf()
    state.set_slot(buf, slot, entry)
    state.touch_slot(buf, slot)
    matcher.apply_slot_for_buffer(buf, slot, entry)
    return
  end

  local raw = resolve_raw(opts)
  if not raw then
    return
  end

  local pattern_text = build_pattern(raw, opts)
  local buf = vim.api.nvim_get_current_buf()

  if config.auto_allocation.toggle_same then
    local existing = state.find_slot_by_raw_or_pattern(buf, pattern_text)
    if not existing then
      existing = state.find_slot_by_raw_or_pattern(buf, raw)
    end
    if existing then
      M.clear(existing)
      return
    end
  end

  local slot_strategy = config.auto_allocation.strategy
  local auto_slot = state.find_available_slot(buf, slot_strategy, config.slots)
  if not auto_slot then
    local policy = config.auto_allocation.on_full
    if policy == "no_op" then
      vim.notify("pinwords: no available slots", vim.log.levels.INFO)
      return
    end

    auto_slot = state.evict_slot(buf, policy)
    if not auto_slot then
      return
    end
  end

  local entry = {
    raw = raw,
    pattern = pattern_text,
    hl_group = "PinWord" .. auto_slot,
  }

  state.set_slot(buf, auto_slot, entry)
  state.touch_slot(buf, auto_slot)
  matcher.apply_slot_for_buffer(buf, auto_slot, entry)
end

---@param slot integer
---@return nil
function M.clear(slot)
  if not valid_slot(slot) then
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  state.clear_slot(buf, slot)
  matcher.clear_slot_for_buffer(buf, slot)
end

---@param opts? PinwordsSetOpts
---@return nil
function M.toggle(opts)
  M.set(nil, opts)
end

---@return nil
function M.cword_toggle()
  local win = vim.api.nvim_get_current_win()
  local win_state = state.get_win_state(win)
  local cword_state = win_state.cword or { enabled = false }
  local enabled = not cword_state.enabled
  cword_state.enabled = enabled

  if enabled then
    win_state.cword = cword_state
    state.set_win_state(win, win_state)
    cword_enabled_wins[win] = true
    update_cword_for_window(win)
  else
    cword_enabled_wins[win] = nil
    if cword_state.match_id then
      matcher.delete_match_id_for_window(win, cword_state.match_id)
    end
    cword_state.match_id = nil
    cword_state.pattern = nil
    win_state.cword = cword_state
    state.set_win_state(win, win_state)
  end
end

---@return nil
function M.unpin()
  local raw = resolve_raw(nil, "pinwords: no word to unpin")
  if not raw then
    return
  end

  local pattern_text = build_pattern(raw)
  local buf = vim.api.nvim_get_current_buf()
  local slot = state.find_slot_by_raw_or_pattern(buf, pattern_text)
  if not slot then
    slot = state.find_slot_by_raw_or_pattern(buf, raw)
  end
  if slot then
    M.clear(slot)
  end
end

---@return nil
function M.clear_all()
  local buf = vim.api.nvim_get_current_buf()
  state.clear_all(buf)
  matcher.clear_all_for_buffer(buf)
end

---@return table<integer, PinwordsSlot>
function M.list()
  local buf = vim.api.nvim_get_current_buf()
  return state.get_slots(buf)
end

return M
