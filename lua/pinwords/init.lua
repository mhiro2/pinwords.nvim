---@type table|nil
local commands
---@type table|nil
local flash
---@type table|nil
local highlight
---@type table|nil
local jump
---@type table|nil
local matcher
---@type table|nil
local pattern
---@type table|nil
local picker
---@type table|nil
local runtime
---@type table|nil
local state
---@type table|nil
local symbol

local M = {}
local AUGROUP_NAME = "PinWords"
local config_module = require("pinwords.config")

---@return nil
local function ensure_modules()
  if commands then
    return
  end

  commands = require("pinwords.commands")
  flash = require("pinwords.flash")
  highlight = require("pinwords.highlight")
  jump = require("pinwords.jump")
  matcher = require("pinwords.matcher")
  pattern = require("pinwords.pattern")
  picker = require("pinwords.picker")
  runtime = require("pinwords.runtime")
  state = require("pinwords.state")
end

---@param msg string
local function warn(msg)
  vim.notify("pinwords: " .. msg, vim.log.levels.WARN)
end

---@class PinwordsColorSpec
---@field bg? string         -- background color (hex)
---@field fg? string         -- foreground color (hex)
---@field sp? string         -- special color for underline/undercurl (hex)
---@field bold? boolean
---@field italic? boolean
---@field underline? boolean
---@field undercurl? boolean
---@field underdouble? boolean
---@field underdotted? boolean
---@field underdashed? boolean
---@field strikethrough? boolean
---@field ctermbg? integer
---@field ctermfg? integer

---@alias PinwordsColor string | PinwordsColorSpec

---@class PinwordsColorsConfig
---@field [integer] PinwordsColor  -- slot number => color
---@field cword? PinwordsColor     -- cursor word color

---@class PinwordsConfig
---@field slots integer
---@field whole_word boolean
---@field case_sensitive boolean
---@field auto_allocation PinwordsAutoAllocation
---@field colors? PinwordsColorsConfig
---@field flash PinwordsFlashConfig
---@field telescope PinwordsTelescopeConfig
---@field snacks PinwordsSnacksConfig
---@field fzf_lua PinwordsFzfLuaConfig

---@class PinwordsAutoAllocation
---@field strategy PinwordsAutoAllocationStrategy
---@field on_full PinwordsAutoAllocationOnFull
---@field toggle_same boolean

---@class PinwordsTelescopeConfig
---@field enabled boolean

---@class PinwordsSnacksConfig
---@field enabled boolean

---@class PinwordsFzfLuaConfig
---@field enabled boolean

---@class PinwordsFlashConfig
---@field enabled boolean
---@field timeout_ms integer
---@field hl_group string
---@field priority integer

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
---@field source? "cword"|"symbol"

---@type PinwordsConfig
local config = config_module.default_config()

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

  if slot % 1 ~= 0 or slot < 1 or slot > config.slots then
    vim.notify("pinwords: slot must be an integer between 1 and " .. config.slots, vim.log.levels.WARN)
    return false
  end

  return true
end

---@param opts? PinwordsSetOpts
---@param empty_message? string
---@return string|nil
local function resolve_raw(opts, empty_message)
  local raw = opts and opts.raw
  if not raw then
    if opts and opts.source == "symbol" then
      if not symbol then
        symbol = require("pinwords.symbol")
      end
      raw = symbol.get_symbol_at_cursor()
    end
    if not raw then
      raw = vim.fn.expand("<cword>")
    end
  end
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
    whole_word = value_or(opts and opts.whole_word, config.whole_word),
    case_sensitive = value_or(opts and opts.case_sensitive, config.case_sensitive),
  }
end

---@param pattern_text string|nil
---@return nil
local function flash_feedback(pattern_text)
  if type(pattern_text) ~= "string" or pattern_text == "" then
    return
  end

  local win = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  flash.flash_pattern(win, pattern_text)
end

---Initialize pinwords with optional configuration.
---@param opts? PinwordsConfig
---@return nil
function M.setup(opts)
  ensure_modules()
  config = config_module.sanitize(opts, warn)

  -- Initialize global state
  state.init_global_state()
  flash.setup(config.flash)

  highlight.apply(config.slots, config.colors)
  commands.setup(config.slots)

  -- Prune global state when slots are reduced
  state.prune_global_state(config.slots)
  runtime.setup({
    augroup_name = AUGROUP_NAME,
    slots = config.slots,
    colors = config.colors,
    build_pattern = build_pattern,
  })

  -- Load Telescope extension if enabled and available
  if config.telescope.enabled then
    local ok, telescope = pcall(require, "telescope")
    if not ok then
      warn("telescope.enabled is true but telescope.nvim is not available")
    elseif telescope.load_extension then
      pcall(telescope.load_extension, "pinwords")
    end
  end

  -- Load Snacks integration if enabled and available
  if config.snacks.enabled then
    local ok, snacks_integration = pcall(require, "pinwords.snacks")
    if not ok or type(snacks_integration) ~= "table" then
      warn("snacks.enabled is true but snacks.nvim is not available")
    end
  end

  -- Load fzf-lua integration if enabled and available
  if config.fzf_lua.enabled then
    local ok, fzf_integration = pcall(require, "pinwords.fzf_lua")
    if not ok or type(fzf_integration) ~= "table" then
      warn("fzf_lua.enabled is true but fzf-lua is not available")
    end
  end
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

---Pin a word to a slot. If slot is nil, auto-allocate.
---When called without opts.raw, uses word under cursor.
---@param slot? integer Slot number (1-N). nil for auto allocation.
---@param opts? PinwordsSetOpts Options including raw text, whole_word, case_sensitive.
---@return nil
function M.set(slot, opts)
  ensure_modules()
  local raw = resolve_raw(opts)
  if not raw then
    return
  end

  local pattern_text = build_pattern(raw, opts)

  if slot ~= nil then
    if not valid_slot(slot) then
      return
    end
    apply_slot(raw, slot, opts)
    flash_feedback(pattern_text)
    return
  end

  if config.auto_allocation.toggle_same then
    local existing = state.find_slot_by_raw_and_pattern(raw, pattern_text)
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
  flash_feedback(pattern_text)
end

---Clear the pinned word in the given slot.
---@param slot integer Slot number to clear.
---@return nil
function M.clear(slot)
  ensure_modules()
  if not valid_slot(slot) then
    return
  end

  local entry = state.get_slots()[slot]
  state.clear_slot(slot)
  matcher.clear_slot_globally(slot)

  if entry and type(entry.pattern) == "string" then
    flash_feedback(entry.pattern)
  end
end

---Toggle pin for word under cursor (alias for set with auto allocation).
---@param opts? PinwordsSetOpts Options including raw text, whole_word, case_sensitive.
---@return nil
function M.toggle(opts)
  M.set(nil, opts)
end

---Toggle cursor-word highlight for the current window.
---@return nil
function M.cword_toggle()
  ensure_modules()
  runtime.toggle_cword()
end

---Unpin the word under cursor if it is currently pinned.
---@return nil
function M.unpin()
  ensure_modules()
  local raw = resolve_raw(nil, "pinwords: no word to unpin")
  if not raw then
    return
  end

  local pattern_text = build_pattern(raw)
  local slot = state.find_slot_by_raw_and_pattern(raw, pattern_text)
  if slot then
    M.clear(slot)
    return
  end

  local raw_slots = state.find_slots_by_raw(raw)
  if #raw_slots == 1 then
    M.clear(raw_slots[1])
    return
  end

  if #raw_slots > 1 then
    vim.notify("pinwords: multiple pinned slots match current word; specify a slot", vim.log.levels.WARN)
  end
end

---Clear all pinned words from every slot.
---@return nil
function M.clear_all()
  ensure_modules()
  state.clear_all()
  matcher.clear_all_globally()
end

---Return a deep copy of all currently pinned slots.
---@return table<integer, PinwordsSlot>
function M.list()
  ensure_modules()
  return vim.deepcopy(state.get_slots())
end

---Return a deep copy of the current configuration.
---@return PinwordsConfig
function M.get_config()
  return vim.deepcopy(config)
end

---Open interactive picker for pinned words.
---Tries enabled pickers in order: snacks -> telescope -> fzf_lua -> vim.ui.select
---@return nil
function M.pick()
  ensure_modules()
  picker.open(config)
end

---Jump to the next occurrence of a pinned word.
---@param slot? integer Slot number to restrict search, or nil for all slots.
---@return boolean success
function M.jump_next(slot)
  ensure_modules()
  if slot ~= nil and not valid_slot(slot) then
    return false
  end
  return jump.next(slot)
end

---Jump to the previous occurrence of a pinned word.
---@param slot? integer Slot number to restrict search, or nil for all slots.
---@return boolean success
function M.jump_prev(slot)
  ensure_modules()
  if slot ~= nil and not valid_slot(slot) then
    return false
  end
  return jump.prev(slot)
end

---Grep pinned words across the project.
---@param opts? { slot?: integer }
---@return nil
function M.grep(opts)
  ensure_modules()
  require("pinwords.grep").grep(opts)
end

---Live grep pinned words across the project.
---@param opts? { slot?: integer }
---@return nil
function M.live_grep(opts)
  ensure_modules()
  require("pinwords.grep").live_grep(opts)
end

--- Flush debounced cword update immediately (for testing)
function M.flush_cword_timer()
  ensure_modules()
  runtime.flush_cword()
end

---Tear down pinwords: stop timers, remove autocmds, clear all state.
---@return nil
function M.teardown()
  ensure_modules()
  runtime.teardown()
  flash.clear_all()

  matcher.clear_all_globally()
  commands.teardown()

  local grep = package.loaded["pinwords.grep"]
  if grep then
    grep.teardown()
  end

  state.teardown()
end

return M
