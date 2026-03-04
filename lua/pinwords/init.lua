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
local state

local M = {}
local AUGROUP_NAME = "PinWords"
local COMMAND_NAMES = {
  "PinWord",
  "UnpinWord",
  "UnpinAllWords",
  "PinWordList",
  "PinWordCwordToggle",
  "PinWordNext",
  "PinWordPrev",
}

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
  state = require("pinwords.state")
end

---@param msg string
local function warn(msg)
  vim.notify("pinwords: " .. msg, vim.log.levels.WARN)
end

---@class PinwordsColorSpec
---@field bg? string         -- background color (hex)
---@field fg? string         -- foreground color (hex)
---@field bold? boolean
---@field italic? boolean
---@field underline? boolean
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

---@class PinwordsAutoAllocation
---@field strategy PinwordsAutoAllocationStrategy
---@field on_full PinwordsAutoAllocationOnFull
---@field toggle_same boolean

---@class PinwordsTelescopeConfig
---@field enabled boolean

---@class PinwordsSnacksConfig
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
  colors = nil,
  flash = {
    enabled = true,
    timeout_ms = 120,
    hl_group = "PinWordFlash",
    priority = 250,
  },
  telescope = {
    enabled = false,
  },
  snacks = {
    enabled = false,
  },
}

---@type PinwordsConfig
local config = vim.deepcopy(default_config)

---@param hex string
---@return boolean
local function is_valid_hex(hex)
  return type(hex) == "string" and hex:match("^#%x%x%x%x%x%x$") ~= nil
end

---@param value any
---@param slot_name string
---@return PinwordsColor|nil
local function validate_color(value, slot_name)
  if type(value) == "string" then
    if not is_valid_hex(value) then
      warn(slot_name .. " must be a valid hex color (e.g. #ff6b6b); ignoring")
      return nil
    end
    return value
  elseif type(value) == "table" then
    if value.bg ~= nil and not is_valid_hex(value.bg) then
      warn(slot_name .. ".bg must be a valid hex color; ignoring")
      return nil
    end
    if value.fg ~= nil and not is_valid_hex(value.fg) then
      warn(slot_name .. ".fg must be a valid hex color; ignoring")
      return nil
    end
    return value
  end
  warn(slot_name .. " must be a string or table; ignoring")
  return nil
end

---@param colors table
---@return PinwordsColorsConfig|nil
local function validate_colors_config(colors)
  local validated = {}
  local has_valid = false

  for key, value in pairs(colors) do
    if key == "cword" then
      local valid = validate_color(value, "colors.cword")
      if valid then
        validated.cword = valid
        has_valid = true
      end
    elseif type(key) == "number" and key >= 1 and key % 1 == 0 then
      local valid = validate_color(value, "colors[" .. key .. "]")
      if valid then
        validated[key] = valid
        has_valid = true
      end
    else
      warn("colors key must be a positive integer or 'cword'; ignoring key: " .. tostring(key))
    end
  end

  return has_valid and validated or nil
end

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
  if opts ~= nil and type(opts) ~= "table" then
    warn("setup opts must be a table; fallback to default")
    opts = {}
  end
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

  if type(cfg.telescope) ~= "table" then
    warn("telescope must be a table; fallback to default")
    cfg.telescope = vim.deepcopy(default_config.telescope)
  else
    cfg.telescope.enabled = validate_field(cfg.telescope.enabled, function(v)
      return type(v) == "boolean"
    end, default_config.telescope.enabled, "telescope.enabled must be boolean; fallback to default")
  end

  if type(cfg.snacks) ~= "table" then
    warn("snacks must be a table; fallback to default")
    cfg.snacks = vim.deepcopy(default_config.snacks)
  else
    cfg.snacks.enabled = validate_field(cfg.snacks.enabled, function(v)
      return type(v) == "boolean"
    end, default_config.snacks.enabled, "snacks.enabled must be boolean; fallback to default")
  end

  if type(cfg.flash) ~= "table" then
    warn("flash must be a table; fallback to default")
    cfg.flash = vim.deepcopy(default_config.flash)
  else
    cfg.flash.enabled = validate_field(cfg.flash.enabled, function(v)
      return type(v) == "boolean"
    end, default_config.flash.enabled, "flash.enabled must be boolean; fallback to default")

    cfg.flash.timeout_ms = validate_field(cfg.flash.timeout_ms, function(v)
      return type(v) == "number" and v >= 1 and v % 1 == 0
    end, default_config.flash.timeout_ms, "flash.timeout_ms must be a positive integer; fallback to default")

    cfg.flash.hl_group = validate_field(cfg.flash.hl_group, function(v)
      return type(v) == "string" and v ~= ""
    end, default_config.flash.hl_group, "flash.hl_group must be a non-empty string; fallback to default")

    cfg.flash.priority = validate_field(cfg.flash.priority, function(v)
      return type(v) == "number" and v % 1 == 0
    end, default_config.flash.priority, "flash.priority must be an integer; fallback to default")
  end

  -- Validate colors
  if cfg.colors ~= nil then
    if type(cfg.colors) ~= "table" then
      warn("colors must be a table; ignoring")
      cfg.colors = nil
    else
      cfg.colors = validate_colors_config(cfg.colors)
    end
  end

  return cfg
end

-- Windows where cword highlight is enabled (winid -> true)
---@type table<integer, boolean>
local cword_enabled_wins = {}
---@type table<integer, boolean>
local pending_reapply_wins = {}

local cword_timer = nil
local CWORD_DEBOUNCE_MS = 50

---@param args table|nil
---@return integer
local function resolve_autocmd_win(args)
  local win = type(args) == "table" and args.win or nil
  if type(win) ~= "number" or win == 0 then
    win = vim.api.nvim_get_current_win()
  end
  return win
end

---@return nil
local function stop_cword_timer()
  if not cword_timer then
    return
  end
  pcall(function()
    cword_timer:stop()
  end)
  pcall(function()
    cword_timer:close()
  end)
  cword_timer = nil
end

---@param win integer
---@return boolean
local function is_cword_enabled(win)
  if cword_enabled_wins[win] ~= true then
    return false
  end
  if not vim.api.nvim_win_is_valid(win) then
    cword_enabled_wins[win] = nil -- Lazy cleanup
    return false
  end
  return true
end

---@return nil
local function cleanup_stale_cword_wins()
  for win in pairs(cword_enabled_wins) do
    if type(win) ~= "number" or not vim.api.nvim_win_is_valid(win) then
      cword_enabled_wins[win] = nil
    end
  end
end

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

---@param opts? PinwordsConfig
---@return nil
function M.setup(opts)
  ensure_modules()
  config = sanitize_config(opts)

  -- Initialize global state
  state.init_global_state()
  flash.setup(config.flash)

  highlight.apply(config.slots, config.colors)
  commands.setup(config.slots)

  -- Prune global state when slots are reduced
  state.prune_global_state(config.slots)

  -- Rebuild window-local matches from global state
  cleanup_stale_cword_wins()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    matcher.reapply_all_for_window(win)
    if is_cword_enabled(win) then
      update_cword_for_window(win)
    end
  end

  local group = vim.api.nvim_create_augroup(AUGROUP_NAME, { clear = true })

  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    group = group,
    callback = function(args)
      local win = resolve_autocmd_win(args)
      if pending_reapply_wins[win] then
        return
      end
      pending_reapply_wins[win] = true
      vim.schedule(function()
        pending_reapply_wins[win] = nil
      end)

      matcher.reapply_all_for_window(win)
      if is_cword_enabled(win) then
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
      if not is_cword_enabled(win) then
        return
      end
      if cword_timer then
        cword_timer:stop()
      end
      if not cword_timer then
        cword_timer = vim.uv.new_timer()
      end
      cword_timer:start(
        CWORD_DEBOUNCE_MS,
        0,
        vim.schedule_wrap(function()
          -- Use captured win, not current win at timer fire time
          if not is_cword_enabled(win) then
            return
          end
          update_cword_for_window(win)
        end)
      )
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      highlight.apply(config.slots, config.colors)
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      local win = tonumber(args.match)
      if win then
        cword_enabled_wins[win] = nil
        flash.clear_for_window(win)
      end
    end,
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

---@param slot? integer
---@param opts? PinwordsSetOpts
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
    local existing = state.find_slot_by_raw_or_pattern_pair(raw, pattern_text)
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

---@param slot integer
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

---@param opts? PinwordsSetOpts
---@return nil
function M.toggle(opts)
  M.set(nil, opts)
end

---@return nil
function M.cword_toggle()
  ensure_modules()
  local win = vim.api.nvim_get_current_win()

  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  local win_state = state.get_win_state(win)
  local cword_state = win_state.cword or { enabled = false }
  local was_enabled = cword_state.enabled
  cword_state.enabled = not cword_state.enabled

  if not was_enabled and cword_state.enabled then
    cword_enabled_wins[win] = true
    win_state.cword = cword_state
    state.set_win_state(win, win_state)
    update_cword_for_window(win)
    return
  end

  if was_enabled and not cword_state.enabled then
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
  ensure_modules()
  local raw = resolve_raw(nil, "pinwords: no word to unpin")
  if not raw then
    return
  end

  local pattern_text = build_pattern(raw)
  local slot = state.find_slot_by_raw_or_pattern_pair(raw, pattern_text)
  if slot then
    M.clear(slot)
  end
end

---@return nil
function M.clear_all()
  ensure_modules()
  state.clear_all()
  matcher.clear_all_globally()
end

---@return table<integer, PinwordsSlot>
function M.list()
  ensure_modules()
  return state.get_slots()
end

---Open interactive picker for pinned words.
---Tries enabled pickers in order: snacks -> telescope -> vim.ui.select
---@return nil
function M.pick()
  ensure_modules()

  -- Try snacks
  if config.snacks.enabled then
    local ok, snacks_mod = pcall(require, "pinwords.snacks")
    if ok and type(snacks_mod) == "table" and type(snacks_mod.picker) == "function" then
      snacks_mod.picker()
      return
    end
  end

  -- Try telescope
  if config.telescope.enabled then
    local ok, telescope = pcall(require, "telescope")
    if ok and telescope then
      pcall(telescope.load_extension, "pinwords")
      local ext_ok, ext = pcall(function()
        return telescope.extensions.pinwords.pinwords
      end)
      if ext_ok and ext then
        ext()
        return
      end
    end
  end

  -- Fallback: vim.ui.select
  local slots = state.get_slots()
  local keys = vim.tbl_keys(slots)
  table.sort(keys)

  if #keys == 0 then
    vim.notify("pinwords: no pinned words", vim.log.levels.INFO)
    return
  end

  local items = {}
  for _, slot in ipairs(keys) do
    table.insert(items, { slot = slot, raw = slots[slot].raw })
  end

  vim.ui.select(items, {
    prompt = "Pinned Words (select to unpin):",
    format_item = function(item)
      return string.format("%d: %s", item.slot, item.raw)
    end,
  }, function(choice)
    if choice then
      M.clear(choice.slot)
      vim.notify("pinwords: unpinned slot " .. choice.slot, vim.log.levels.INFO)
    end
  end)
end

---@param slot? integer
---@return boolean success
function M.jump_next(slot)
  ensure_modules()
  if slot ~= nil and not valid_slot(slot) then
    return false
  end
  return jump.next(slot)
end

---@param slot? integer
---@return boolean success
function M.jump_prev(slot)
  ensure_modules()
  if slot ~= nil and not valid_slot(slot) then
    return false
  end
  return jump.prev(slot)
end

--- Flush debounced cword update immediately (for testing)
function M.flush_cword_timer()
  ensure_modules()
  if cword_timer then
    cword_timer:stop()
  end
  local win = vim.api.nvim_get_current_win()
  if is_cword_enabled(win) then
    update_cword_for_window(win)
  end
end

---@return nil
function M.teardown()
  ensure_modules()
  stop_cword_timer()
  pcall(vim.api.nvim_del_augroup_by_name, AUGROUP_NAME)
  flash.clear_all()

  matcher.clear_all_globally()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      matcher.clear_cword_for_window(win)

      local win_state = state.get_win_state(win)
      win_state.cword = { enabled = false }
      state.set_win_state(win, win_state)
    end
  end

  for _, command_name in ipairs(COMMAND_NAMES) do
    pcall(vim.api.nvim_del_user_command, command_name)
  end

  cword_enabled_wins = {}
  pending_reapply_wins = {}
  state.teardown()
end

return M
