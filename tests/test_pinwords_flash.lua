local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

local FLASH_GROUP = "PinWordFlashTest"

---@param pinwords table
---@param flash_opts? table
local function setup_flash(pinwords, flash_opts)
  vim.api.nvim_set_hl(0, FLASH_GROUP, { reverse = true })

  local opts = {
    enabled = true,
    timeout_ms = 40,
    hl_group = FLASH_GROUP,
    priority = 260,
  }

  if type(flash_opts) == "table" then
    opts = vim.tbl_deep_extend("force", opts, flash_opts)
  end

  pinwords.setup({
    flash = opts,
  })
end

T["set success shows and clears flash"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  local pinwords = require("pinwords")
  setup_flash(pinwords)

  pinwords.set(1)

  MiniTest.expect.equality(helpers.find_match(FLASH_GROUP) ~= nil, true)
  local is_cleared = vim.wait(300, function()
    return helpers.find_match(FLASH_GROUP) == nil
  end, 10)
  MiniTest.expect.equality(is_cleared, true)
end

T["clear success shows flash"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  local pinwords = require("pinwords")
  setup_flash(pinwords)

  pinwords.set(1)
  vim.wait(300, function()
    return helpers.find_match(FLASH_GROUP) == nil
  end, 10)

  pinwords.clear(1)

  MiniTest.expect.equality(helpers.find_match(FLASH_GROUP) ~= nil, true)
end

T["unpin success shows flash"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  local pinwords = require("pinwords")
  setup_flash(pinwords)

  pinwords.set(1)
  vim.wait(300, function()
    return helpers.find_match(FLASH_GROUP) == nil
  end, 10)

  pinwords.unpin()

  MiniTest.expect.equality(helpers.find_match(FLASH_GROUP) ~= nil, true)
end

T["set with empty word does not flash"] = function()
  helpers.setup_buffer({ "   ", "  " })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local pinwords = require("pinwords")
  setup_flash(pinwords)

  pinwords.set(1)

  MiniTest.expect.equality(helpers.find_match(FLASH_GROUP), nil)
end

T["clear with invalid slot does not flash"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  local pinwords = require("pinwords")
  setup_flash(pinwords)

  pinwords.clear(0)

  MiniTest.expect.equality(helpers.find_match(FLASH_GROUP), nil)
end

T["flash.enabled=false disables feedback"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  local pinwords = require("pinwords")
  setup_flash(pinwords, { enabled = false })

  pinwords.set(1)
  pinwords.clear(1)
  pinwords.unpin()

  MiniTest.expect.equality(helpers.find_match(FLASH_GROUP), nil)
end

return T
