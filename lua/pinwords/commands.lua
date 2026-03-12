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

---@param args string
---@param max_slots integer
---@param required boolean
---@return integer|nil
local function parse_slot(args, max_slots, required)
  local slot = tonumber(args)
  if not slot then
    if args ~= "" then
      vim.notify("pinwords: slot must be a number", vim.log.levels.WARN)
      return nil
    end
    if required then
      vim.notify("pinwords: slot is required", vim.log.levels.WARN)
    end
    return nil
  end

  if slot % 1 ~= 0 or slot < 1 or slot > max_slots then
    vim.notify("pinwords: slot must be an integer between 1 and " .. max_slots, vim.log.levels.WARN)
    return nil
  end

  return slot
end

---@param max_slots integer
function M.setup(max_slots)
  vim.api.nvim_create_user_command("PinWord", function(opts)
    ---@cast opts PinwordsCommandOpts
    local slot
    if opts.args ~= "" then
      slot = parse_slot(opts.args, max_slots, true)
      if not slot then
        return
      end
    end

    -- Treat range as visual selection only when '< and '> marks match the range.
    -- This avoids accidentally pinning stale visual marks for line-range calls like :1,3PinWord.
    local raw = selection.resolve(opts)
    if raw ~= nil then
      if raw == "" then
        vim.notify("pinwords: visual selection is empty", vim.log.levels.WARN)
        return
      end

      require("pinwords").set(slot, { raw = raw, whole_word = false })
      return
    end

    require("pinwords").set(slot)
  end, {
    nargs = "?",
    range = true,
    force = true,
    desc = "Pin word (auto allocation). With visual range, pin selection.",
  })

  vim.api.nvim_create_user_command("PinWordSymbol", function(opts)
    ---@cast opts PinwordsCommandOpts
    local slot
    if opts.args ~= "" then
      slot = parse_slot(opts.args, max_slots, true)
      if not slot then
        return
      end
    end
    require("pinwords").set(slot, { source = "symbol" })
  end, {
    nargs = "?",
    force = true,
    desc = "Pin symbol at cursor using Treesitter (falls back to cword).",
  })

  vim.api.nvim_create_user_command("UnpinWord", function(opts)
    ---@cast opts PinwordsCommandOpts
    if opts.args == "" then
      require("pinwords").unpin()
      return
    end

    local slot = parse_slot(opts.args, max_slots, true)
    if not slot then
      return
    end
    require("pinwords").clear(slot)
  end, { nargs = "?", force = true, desc = "Unpin word under cursor, or clear slot." })

  vim.api.nvim_create_user_command("UnpinAllWords", function()
    require("pinwords").clear_all()
  end, { nargs = 0, force = true, desc = "Clear all pinned words." })

  vim.api.nvim_create_user_command("PinWordList", function()
    require("pinwords").pick()
  end, { nargs = 0, force = true, desc = "List global pinned words in interactive picker." })

  vim.api.nvim_create_user_command("PinWordCwordToggle", function()
    require("pinwords").cword_toggle()
  end, { nargs = 0, force = true, desc = "Toggle cursor word highlight (window-local)." })

  vim.api.nvim_create_user_command("PinWordNext", function(opts)
    ---@cast opts PinwordsCommandOpts
    local slot
    if opts.args ~= "" then
      slot = parse_slot(opts.args, max_slots, true)
      if not slot then
        return
      end
    end
    require("pinwords").jump_next(slot)
  end, { nargs = "?", force = true, desc = "Jump to next pinned word occurrence." })

  vim.api.nvim_create_user_command("PinWordPrev", function(opts)
    ---@cast opts PinwordsCommandOpts
    local slot
    if opts.args ~= "" then
      slot = parse_slot(opts.args, max_slots, true)
      if not slot then
        return
      end
    end
    require("pinwords").jump_prev(slot)
  end, { nargs = "?", force = true, desc = "Jump to previous pinned word occurrence." })

  vim.api.nvim_create_user_command("PinWordGrep", function(opts)
    ---@cast opts PinwordsCommandOpts
    local slot
    if opts.args ~= "" then
      slot = parse_slot(opts.args, max_slots, true)
      if not slot then
        return
      end
    end
    require("pinwords").grep({ slot = slot })
  end, { nargs = "?", force = true, desc = "Grep pinned words across project." })

  vim.api.nvim_create_user_command("PinWordLiveGrep", function(opts)
    ---@cast opts PinwordsCommandOpts
    local slot
    if opts.args ~= "" then
      slot = parse_slot(opts.args, max_slots, true)
      if not slot then
        return
      end
    end
    require("pinwords").live_grep({ slot = slot })
  end, { nargs = "?", force = true, desc = "Live grep pinned words across project." })
end

return M
