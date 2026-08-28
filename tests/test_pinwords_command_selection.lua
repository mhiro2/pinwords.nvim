local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")
local selection = require("pinwords.commands.selection")

local T = helpers.create_test_set()

T["selection matches only aligned visual ranges"] = function()
  helpers.setup_buffer({ "foo", "bar" })
  helpers.set_visual_marks(2, 1, 2, 3)

  MiniTest.expect.equality(selection.matches_range({ range = 0, line1 = 2, line2 = 2 }), false)
  MiniTest.expect.equality(selection.matches_range({ range = 1, line1 = 1, line2 = 1 }), false)
  MiniTest.expect.equality(selection.matches_range({ range = 1, line1 = 2, line2 = 2 }), true)
end

T["selection normalizes reversed marks"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  helpers.set_visual_marks(1, 7, 1, 5)

  MiniTest.expect.equality(selection.get(), "bar")
end

T["selection handles multibyte byte ranges"] = function()
  helpers.setup_buffer({ "あいうえお" })
  helpers.set_visual_marks(1, 1, 1, 7)

  MiniTest.expect.equality(selection.get(), "あいう")
end

T["selection honors exclusive selection"] = function()
  helpers.setup_buffer({ "abc" })
  helpers.set_visual_marks(1, 1, 1, 3)

  local saved = vim.o.selection
  vim.o.selection = "exclusive"
  local ok, result = pcall(selection.get)
  vim.o.selection = saved

  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(result, "ab")
end

T["selection extracts blockwise regions"] = function()
  helpers.setup_buffer({ "abcde", "fghij" })
  helpers.feed_normal([[ggl\<C-v>jll\<Esc>]])

  MiniTest.expect.equality(selection.get(), "bcd\nghi")
end

T["selection extracts linewise regions"] = function()
  helpers.setup_buffer({ "abcde", "fghij", "klmno" })
  helpers.feed_normal([[ggVj\<Esc>]])

  MiniTest.expect.equality(selection.get(), "abcde\nfghij")
end

return T
