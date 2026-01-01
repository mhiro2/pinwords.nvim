local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

T["auto set uses first empty slot"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  require("pinwords").set()

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "foo")
end

T["auto set toggles same word"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  local pinwords = require("pinwords")
  pinwords.set()

  MiniTest.expect.equality(helpers.match_count() > 0, true)

  pinwords.set()
  MiniTest.expect.equality(helpers.match_count(), 0)
  MiniTest.expect.equality(next(pinwords.list()), nil)
end

T["auto set replaces oldest when full"] = function()
  local pinwords = require("pinwords")
  pinwords.setup({ slots = 2, auto_allocation = { on_full = "replace_oldest" } })

  helpers.setup_buffer({ "foo bar baz" })

  pinwords.set(nil, { raw = "foo" })
  pinwords.set(nil, { raw = "bar" })
  pinwords.set(nil, { raw = "baz" })

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1].raw, "baz")
  MiniTest.expect.equality(slots[2].raw, "bar")
end

T["auto set with lru replaces least recently used slot deterministically"] = function()
  local pinwords = require("pinwords")
  pinwords.setup({ slots = 2, auto_allocation = { strategy = "lru", toggle_same = false } })

  helpers.setup_buffer({ "foo bar baz" })

  -- Fill slots manually.
  pinwords.set(1, { raw = "foo" })
  pinwords.set(2, { raw = "bar" })

  -- Touch slot 1 so slot 2 becomes the least-recently used.
  pinwords.set(1, { raw = "foo" })

  -- Auto allocation should replace slot 2.
  pinwords.set(nil, { raw = "baz" })

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1].raw, "foo")
  MiniTest.expect.equality(slots[2].raw, "baz")
end

T["auto set with cycle strategy cycles through slots"] = function()
  local pinwords = require("pinwords")
  pinwords.setup({ slots = 3, auto_allocation = { strategy = "cycle", toggle_same = false } })

  helpers.setup_buffer({ "foo bar baz qux" })

  -- Fill slots 1 and 2
  pinwords.set(1, { raw = "foo" })
  pinwords.set(2, { raw = "bar" })

  -- Next auto allocation should use slot 3 (after last used slot 2)
  pinwords.set(nil, { raw = "baz" })
  local slots = pinwords.list()
  MiniTest.expect.equality(slots[3].raw, "baz")

  -- Next should cycle back to slot 1 (after last used slot 3)
  pinwords.set(nil, { raw = "qux" })
  slots = pinwords.list()
  MiniTest.expect.equality(slots[1].raw, "qux")
end

T["auto set with replace_last replaces most recently used slot"] = function()
  local pinwords = require("pinwords")
  pinwords.setup({ slots = 2, auto_allocation = { on_full = "replace_last", toggle_same = false } })

  helpers.setup_buffer({ "foo bar baz" })

  pinwords.set(nil, { raw = "foo" })
  pinwords.set(nil, { raw = "bar" })
  pinwords.set(nil, { raw = "baz" })

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1].raw, "foo")
  MiniTest.expect.equality(slots[2].raw, "baz")
end

T["auto set with no_op does nothing when slots are full"] = function()
  local pinwords = require("pinwords")
  pinwords.setup({ slots = 2, auto_allocation = { on_full = "no_op", toggle_same = false } })

  helpers.setup_buffer({ "foo bar baz" })

  pinwords.set(nil, { raw = "foo" })
  pinwords.set(nil, { raw = "bar" })

  local before = pinwords.list()
  MiniTest.expect.equality(before[1].raw, "foo")
  MiniTest.expect.equality(before[2].raw, "bar")

  -- Should not add baz when slots are full (should notify)
  helpers.with_notify_override(function(notified)
    pinwords.set(nil, { raw = "baz" })

    -- Should have notified about no available slots
    MiniTest.expect.equality(#notified > 0, true)
  end)

  local after = pinwords.list()
  MiniTest.expect.equality(after[1].raw, "foo")
  MiniTest.expect.equality(after[2].raw, "bar")
  MiniTest.expect.equality(after[3], nil)
end

T["auto set with toggle_same false does not toggle existing word"] = function()
  local pinwords = require("pinwords")
  pinwords.setup({ auto_allocation = { toggle_same = false } })

  helpers.setup_buffer({ "foo bar", "baz" })

  pinwords.set()
  local before = helpers.match_count()
  MiniTest.expect.equality(before > 0, true)

  -- Should not toggle off, but should add to a different slot or do nothing
  pinwords.set()
  local after = helpers.match_count()
  -- With toggle_same=false, it should either add to another slot or keep existing
  -- Since slots are available, it might add to another slot
  MiniTest.expect.equality(after >= before, true)
end

return T
