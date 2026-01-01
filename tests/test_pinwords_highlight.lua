local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

T["highlight blends with Normal background"] = function()
  local highlight = require("pinwords.highlight")

  -- Save original Normal highlight
  local orig_normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })

  vim.api.nvim_set_hl(0, "Normal", { bg = 0x000000 })
  helpers.clear_hl("PinWord1")
  highlight.apply(1)
  local dark_hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })

  vim.api.nvim_set_hl(0, "Normal", { bg = 0xffffff })
  helpers.clear_hl("PinWord1")
  highlight.apply(1)
  local light_hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })

  -- Restore original Normal highlight
  vim.api.nvim_set_hl(0, "Normal", orig_normal)

  MiniTest.expect.equality(type(dark_hl.bg) == "number", true)
  MiniTest.expect.equality(type(light_hl.bg) == "number", true)
  MiniTest.expect.equality(dark_hl.bg ~= light_hl.bg, true)
end

T["highlight does not overwrite user-defined PinWord groups"] = function()
  local highlight = require("pinwords.highlight")

  -- Set a custom highlight before applying
  local custom_color = 0xff0000 -- Red
  vim.api.nvim_set_hl(0, "PinWord1", { bg = custom_color, fg = 0x00ff00 })

  highlight.apply(3)

  -- Check that the custom highlight is preserved
  local hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
  MiniTest.expect.equality(hl.bg, custom_color)
  MiniTest.expect.equality(hl.fg, 0x00ff00)

  -- Check that other PinWord groups were created
  local hl2 = vim.api.nvim_get_hl(0, { name = "PinWord2", link = false })
  MiniTest.expect.equality(type(hl2.bg) == "number", true)

  local hl3 = vim.api.nvim_get_hl(0, { name = "PinWord3", link = false })
  MiniTest.expect.equality(type(hl3.bg) == "number", true)

  -- Clean up custom highlight
  helpers.clear_hl("PinWord1")
  helpers.clear_hl("PinWord2")
  helpers.clear_hl("PinWord3")
end

T["highlight does not overwrite user-defined PinWordCword"] = function()
  local highlight = require("pinwords.highlight")

  -- Set a custom highlight for PinWordCword
  local custom_color = 0x00ff00 -- Green
  vim.api.nvim_set_hl(0, "PinWordCword", { bg = custom_color, underline = true })

  highlight.apply(1)

  -- Check that the custom highlight is preserved
  local hl = vim.api.nvim_get_hl(0, { name = "PinWordCword", link = false })
  MiniTest.expect.equality(hl.bg, custom_color)
  MiniTest.expect.equality(hl.underline, true)

  -- Clean up custom highlight
  helpers.clear_hl("PinWordCword")
end

return T
