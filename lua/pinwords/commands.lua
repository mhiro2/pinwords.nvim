local M = {}
local selection = require("pinwords.commands.selection")

---@class PinwordsCommandOpts
---@field args string
---@field fargs? string[]
---@field bang? boolean
---@field line1? integer
---@field line2? integer
---@field range? integer
---@field count? integer
---@field mods? string

---@class PinwordsCommandDefinition
---@field name string
---@field nargs integer|string
---@field desc string
---@field range? boolean
---@field accepts_slot? boolean
---@field handler fun(pinwords: table, opts: PinwordsCommandOpts, slot: integer|nil)

---@param args string
---@param max_slots integer
---@return integer|nil
local function parse_slot(args, max_slots)
  local slot = tonumber(args)
  if not slot then
    vim.notify("pinwords: slot must be a number", vim.log.levels.WARN)
    return nil
  end

  if slot % 1 ~= 0 or slot < 1 or slot > max_slots then
    vim.notify("pinwords: slot must be an integer between 1 and " .. max_slots, vim.log.levels.WARN)
    return nil
  end

  return slot
end

---@param opts PinwordsCommandOpts
---@param max_slots integer
---@return integer|nil, boolean
local function resolve_optional_slot(opts, max_slots)
  if opts.args == "" then
    return nil, true
  end

  local slot = parse_slot(opts.args, max_slots)
  if not slot then
    return nil, false
  end

  return slot, true
end

---@param pinwords table
---@param opts PinwordsCommandOpts
---@param slot integer|nil
local function handle_pin_word(pinwords, opts, slot)
  -- Treat range as visual selection only when '< and '> marks match the range.
  -- This avoids accidentally pinning stale visual marks for line-range calls like :1,3PinWord.
  local raw = selection.resolve(opts)
  if raw ~= nil then
    if raw == "" then
      vim.notify("pinwords: visual selection is empty", vim.log.levels.WARN)
      return
    end

    pinwords.set(slot, { raw = raw, whole_word = false })
    return
  end

  pinwords.set(slot)
end

---@param pinwords table
---@param _opts PinwordsCommandOpts
---@param slot integer|nil
local function handle_pin_word_symbol(pinwords, _opts, slot)
  pinwords.set(slot, { source = "symbol" })
end

---@param pinwords table
---@param _opts PinwordsCommandOpts
---@param slot integer|nil
local function handle_unpin_word(pinwords, _opts, slot)
  if slot == nil then
    pinwords.unpin()
    return
  end

  pinwords.clear(slot)
end

---@param method "clear_all"|"pick"|"cword_toggle"
---@return fun(pinwords: table)
local function create_no_arg_handler(method)
  return function(pinwords)
    pinwords[method]()
  end
end

---@param method "jump_next"|"jump_prev"
---@return fun(pinwords: table, opts: PinwordsCommandOpts, slot: integer|nil)
local function create_slot_handler(method)
  return function(pinwords, _opts, slot)
    pinwords[method](slot)
  end
end

---@param method "grep"|"live_grep"
---@return fun(pinwords: table, opts: PinwordsCommandOpts, slot: integer|nil)
local function create_picker_handler(method)
  return function(pinwords, _opts, slot)
    pinwords[method]({ slot = slot })
  end
end

---@type PinwordsCommandDefinition[]
local COMMAND_DEFINITIONS = {
  {
    name = "PinWord",
    nargs = "?",
    range = true,
    accepts_slot = true,
    desc = "Pin word (auto allocation). With visual range, pin selection.",
    handler = handle_pin_word,
  },
  {
    name = "PinWordSymbol",
    nargs = "?",
    accepts_slot = true,
    desc = "Pin symbol at cursor using Treesitter (falls back to cword).",
    handler = handle_pin_word_symbol,
  },
  {
    name = "UnpinWord",
    nargs = "?",
    accepts_slot = true,
    desc = "Unpin word under cursor, or clear slot.",
    handler = handle_unpin_word,
  },
  {
    name = "UnpinAllWords",
    nargs = 0,
    desc = "Clear all pinned words.",
    handler = create_no_arg_handler("clear_all"),
  },
  {
    name = "PinWordList",
    nargs = 0,
    desc = "List global pinned words in interactive picker.",
    handler = create_no_arg_handler("pick"),
  },
  {
    name = "PinWordCwordToggle",
    nargs = 0,
    desc = "Toggle cursor word highlight (window-local).",
    handler = create_no_arg_handler("cword_toggle"),
  },
  {
    name = "PinWordNext",
    nargs = "?",
    accepts_slot = true,
    desc = "Jump to next pinned word occurrence.",
    handler = create_slot_handler("jump_next"),
  },
  {
    name = "PinWordPrev",
    nargs = "?",
    accepts_slot = true,
    desc = "Jump to previous pinned word occurrence.",
    handler = create_slot_handler("jump_prev"),
  },
  {
    name = "PinWordGrep",
    nargs = "?",
    accepts_slot = true,
    desc = "Grep pinned words across project.",
    handler = create_picker_handler("grep"),
  },
  {
    name = "PinWordLiveGrep",
    nargs = "?",
    accepts_slot = true,
    desc = "Live grep pinned words across project.",
    handler = create_picker_handler("live_grep"),
  },
}

---@param definition PinwordsCommandDefinition
---@param max_slots integer
---@return fun(opts: table)
local function create_command_handler(definition, max_slots)
  return function(opts)
    ---@cast opts PinwordsCommandOpts
    local slot
    if definition.accepts_slot then
      local ok
      slot, ok = resolve_optional_slot(opts, max_slots)
      if not ok then
        return
      end
    end

    definition.handler(require("pinwords"), opts, slot)
  end
end

---@param definition PinwordsCommandDefinition
---@return vim.api.keyset.user_command
local function create_command_options(definition)
  local opts = {
    nargs = definition.nargs,
    force = true,
    desc = definition.desc,
  }

  if definition.range then
    opts.range = true
  end

  return opts
end

---@param max_slots integer
function M.setup(max_slots)
  for _, definition in ipairs(COMMAND_DEFINITIONS) do
    vim.api.nvim_create_user_command(
      definition.name,
      create_command_handler(definition, max_slots),
      create_command_options(definition)
    )
  end
end

function M.teardown()
  for _, definition in ipairs(COMMAND_DEFINITIONS) do
    pcall(vim.api.nvim_del_user_command, definition.name)
  end
end

return M
