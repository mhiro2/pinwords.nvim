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

---@param value any
---@param validator fun(v: any): boolean
---@param default any
---@param error_msg string
---@return any
local function validate_field(value, validator, default, error_msg)
  if not validator(value) then
    warn(error_msg)
    return default
  end
  return value
end

---@param opts? PinwordsConfig
---@return PinwordsConfig
local function sanitize_config(opts)
  local cfg = vim.tbl_deep_extend("force", default_config, opts or {})

  local valid_strategies = { first_empty = true, cycle = true, lru = true }
  local valid_on_full = { replace_oldest = true, replace_last = true, no_op = true }

  cfg.slots = validate_field(cfg.slots, function(v)
    return type(v) == "number" and v >= 1 and v % 1 == 0
  end, default_config.slots, "slots must be a positive integer; fallback to default")

  cfg.whole_word = validate_field(cfg.whole_word, function(v)
    return type(v) == "boolean"
  end, default_config.whole_word, "whole_word must be boolean; fallback to default")

  cfg.case_sensitive = validate_field(cfg.case_sensitive, function(v)
    return type(v) == "boolean"
  end, default_config.case_sensitive, "case_sensitive must be boolean; fallback to default")

  if type(cfg.auto_allocation) ~= "table" then
    warn("auto_allocation must be a table; fallback to default")
    cfg.auto_allocation = vim.deepcopy(default_config.auto_allocation)
  else
    cfg.auto_allocation.strategy = validate_field(
      cfg.auto_allocation.strategy,
      function(v)
        return valid_strategies[v]
      end,
      default_config.auto_allocation.strategy,
      "auto_allocation.strategy must be one of: first_empty, cycle, lru; fallback to default"
    )

    cfg.auto_allocation.on_full = validate_field(
      cfg.auto_allocation.on_full,
      function(v)
        return valid_on_full[v]
      end,
      default_config.auto_allocation.on_full,
      "auto_allocation.on_full must be one of: replace_oldest, replace_last, no_op; fallback to default"
    )

    cfg.auto_allocation.toggle_same = validate_field(cfg.auto_allocation.toggle_same, function(v)
      return type(v) == "boolean"
    end, default_config.auto_allocation.toggle_same, "auto_allocation.toggle_same must be boolean; fallback to default")
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
  local pattern_text = raw ~= "" and build_pattern(raw) or nil

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

---@param opts? PinwordsConfig
---@return nil
function M.setup(opts)
  config = sanitize_config(opts)

  -- Initialize global state
  state.init_global_state()

  highlight.apply(config.slots)
  commands.setup(config.slots)

  -- Prune global state when slots are reduced
  state.prune_global_state(config.slots)

  -- Rebuild window-local matches from global state
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

---@param raw string
---@param slot integer
---@param opts? PinwordsSetOpts
local function apply_slot(raw, slot, opts)
  local entry = build_entry(raw, slot, opts)
  state.set_slot(slot, entry)
  state.touch_slot(slot)
  matcher.apply_slot_globally(slot, entry)
end

---@param raw string
---@param pattern_text string
---@return integer|nil
local function find_existing_slot(raw, pattern_text)
  local existing = state.find_slot_by_raw_or_pattern(pattern_text)
  if not existing then
    existing = state.find_slot_by_raw_or_pattern(raw)
  end
  return existing
end

---@param slot? integer
---@param opts? PinwordsSetOpts
---@return nil
function M.set(slot, opts)
  local raw = resolve_raw(opts)
  if not raw then
    return
  end

  if slot ~= nil then
    if not valid_slot(slot) then
      return
    end
    apply_slot(raw, slot, opts)
    return
  end

  local pattern_text = build_pattern(raw, opts)

  if config.auto_allocation.toggle_same then
    local existing = find_existing_slot(raw, pattern_text)
    if existing then
      M.clear(existing)
      return
    end
  end

  local auto_slot = state.find_available_slot(config.auto_allocation.strategy, config.slots)
  if not auto_slot then
    if config.auto_allocation.on_full == "no_op" then
      vim.notify("pinwords: no available slots", vim.log.levels.INFO)
      return
    end

    auto_slot = state.evict_slot(config.auto_allocation.on_full)
    if not auto_slot then
      return
    end
  end

  apply_slot(raw, auto_slot, opts)
end

---@param slot integer
---@return nil
function M.clear(slot)
  if not valid_slot(slot) then
    return
  end

  state.clear_slot(slot)
  matcher.clear_slot_globally(slot)
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
  cword_state.enabled = not cword_state.enabled

  if cword_state.enabled then
    cword_enabled_wins[win] = true
    win_state.cword = cword_state
    state.set_win_state(win, win_state)
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
  local slot = find_existing_slot(raw, pattern_text)
  if slot then
    M.clear(slot)
  end
end

---@return nil
function M.clear_all()
  state.clear_all()
  matcher.clear_all_globally()
end

---@return table<integer, PinwordsSlot>
function M.list()
  return state.get_slots()
end

return M
