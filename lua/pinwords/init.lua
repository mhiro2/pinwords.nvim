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
---@type table|nil
local symbol

local M = {}
local AUGROUP_NAME = "PinWords"
local config_module = require("pinwords.config")
local COMMAND_NAMES = {
  "PinWord",
  "PinWordSymbol",
  "UnpinWord",
  "UnpinAllWords",
  "PinWordList",
  "PinWordCwordToggle",
  "PinWordNext",
  "PinWordPrev",
  "PinWordGrep",
  "PinWordLiveGrep",
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
  }
end

---@param win integer
---@return string
local function get_cword_for_window(win)
  local ok, raw = pcall(vim.api.nvim_win_call, win, function()
    return vim.fn.expand("<cword>")
  end)
  if not ok or type(raw) ~= "string" then
    return ""
  end
  return raw
end

---@param win integer
local function update_cword_for_window(win)
  local win_state = state.get_win_state(win)
  local cword_state = win_state.cword
  if type(cword_state) ~= "table" or not cword_state.enabled then
    return
  end

  local raw = get_cword_for_window(win)
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

---Unpin the word under cursor if it is currently pinned.
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

---Clear all pinned words from every slot.
---@return nil
function M.clear_all()
  ensure_modules()
  state.clear_all()
  matcher.clear_all_globally()
end

---Return all currently pinned slots.
---@return table<integer, PinwordsSlot>
function M.list()
  ensure_modules()
  return state.get_slots()
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

  -- Try fzf-lua
  if config.fzf_lua.enabled then
    local ok, fzf_mod = pcall(require, "pinwords.fzf_lua")
    if ok and type(fzf_mod) == "table" and type(fzf_mod.picker) == "function" then
      fzf_mod.picker()
      return
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
  if cword_timer then
    cword_timer:stop()
  end
  local win = vim.api.nvim_get_current_win()
  if is_cword_enabled(win) then
    update_cword_for_window(win)
  end
end

---Tear down pinwords: stop timers, remove autocmds, clear all state.
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
