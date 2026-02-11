local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

T["visual pin uses selection text"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })
  helpers.set_visual_marks(1, 1, 1, 3)

  vim.cmd("'<,'>PinWord")

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "foo")

  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match ~= nil, true)
  MiniTest.expect.equality(match.pattern, "\\V\\cfoo")
end

T["unpin clears visual pin even if pattern differs (raw match fallback)"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })
  helpers.set_visual_marks(1, 1, 1, 3)

  -- Visual pin uses whole_word=false => pattern differs from default unpin pattern.
  vim.cmd("'<,'>PinWord")
  MiniTest.expect.equality(helpers.match_count() > 0, true)

  vim.cmd("UnpinWord")
  MiniTest.expect.equality(helpers.match_count(), 0)
  MiniTest.expect.equality(next(require("pinwords").list()), nil)
end

T["visual pin supports multi-line selection"] = function()
  helpers.setup_buffer({ "foo bar", "baz qux" })
  helpers.set_visual_marks(1, 1, 2, 3)

  vim.cmd("'<,'>PinWord")

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "foo bar\nbaz")
end

T["visual pin handles multibyte selection on one line"] = function()
  helpers.setup_buffer({ "あいうえお" })
  helpers.set_visual_marks(1, 1, 1, 7)

  vim.cmd("'<,'>PinWord")

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "あいう")
end

T["visual pin handles multibyte selection across lines"] = function()
  helpers.setup_buffer({ "あいう", "かきく" })
  helpers.set_visual_marks(1, 4, 2, 4)

  vim.cmd("'<,'>PinWord")

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "いう\nかき")
end

T["visual pin handles emoji selection on one line"] = function()
  local emoji1 = vim.fn.nr2char(0x1F600)
  local emoji2 = vim.fn.nr2char(0x1F603)
  helpers.setup_buffer({ emoji1 .. emoji2 .. "x" })
  helpers.set_visual_marks(1, 1, 1, 5)

  vim.cmd("'<,'>PinWord")

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, emoji1 .. emoji2)
end

T["visual pin handles combining character selection"] = function()
  local combining_acute = vim.fn.nr2char(0x0301)
  local text = "e" .. combining_acute .. "f"
  helpers.setup_buffer({ text })
  helpers.set_visual_marks(1, 1, 1, 2)

  vim.cmd("'<,'>PinWord")

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "e" .. combining_acute)
end

return T
