local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

T["get_slots returns empty table initially"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  local slots = state.get_slots()
  MiniTest.expect.equality(type(slots), "table")
  MiniTest.expect.equality(next(slots), nil)
end

T["set_slot stores entry and syncs to global var"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  local entry = {
    raw = "foo",
    pattern = "\\V\\c\\<foo\\>",
    hl_group = "PinWord1",
  }

  state.set_slot(1, entry)

  local slots = state.get_slots()
  MiniTest.expect.equality(slots[1].raw, "foo")
  MiniTest.expect.equality(slots[1].pattern, "\\V\\c\\<foo\\>")
  MiniTest.expect.equality(slots[1].hl_group, "PinWord1")

  local global = vim.g.pinwords_global
  MiniTest.expect.equality(type(global), "table")
  MiniTest.expect.equality(global.slots[1].raw, "foo")
end

T["clear_slot removes entry from slots and order"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  local entry = {
    raw = "foo",
    pattern = "\\V\\c\\<foo\\>",
    hl_group = "PinWord1",
  }

  state.set_slot(1, entry)
  state.touch_slot(1)

  MiniTest.expect.equality(state.get_slots()[1].raw, "foo")

  local global1 = vim.g.pinwords_global
  MiniTest.expect.equality(#global1.order, 1)

  state.clear_slot(1)

  MiniTest.expect.equality(state.get_slots()[1], nil)

  local global2 = vim.g.pinwords_global
  MiniTest.expect.equality(#global2.order, 0)
end

T["clear_all resets all state"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")

  state.set_slot(1, { raw = "foo", pattern = "\\V\\c\\<foo\\>", hl_group = "PinWord1" })
  state.set_slot(2, { raw = "bar", pattern = "\\V\\c\\<bar\\>", hl_group = "PinWord2" })
  state.touch_slot(1)
  state.touch_slot(2)

  MiniTest.expect.equality(state.get_slots()[1].raw, "foo")
  MiniTest.expect.equality(state.get_slots()[2].raw, "bar")

  state.clear_all()

  MiniTest.expect.equality(next(state.get_slots()), nil)

  local global = vim.g.pinwords_global
  MiniTest.expect.equality(#global.order, 0)
  MiniTest.expect.equality(next(global.last_used), nil)
  MiniTest.expect.equality(global.tick, 0)
end

T["find_slot_by_raw_or_pattern finds by raw"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  state.set_slot(1, {
    raw = "foo",
    pattern = "\\V\\c\\<foo\\>",
    hl_group = "PinWord1",
  })

  local slot = state.find_slot_by_raw_or_pattern("foo")
  MiniTest.expect.equality(slot, 1)
end

T["find_slot_by_raw_or_pattern finds by pattern"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  state.set_slot(1, {
    raw = "foo",
    pattern = "\\V\\c\\<foo\\>",
    hl_group = "PinWord1",
  })

  local slot = state.find_slot_by_raw_or_pattern("\\V\\c\\<foo\\>")
  MiniTest.expect.equality(slot, 1)
end

T["find_slot_by_raw_or_pattern returns nil when not found"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  state.set_slot(1, {
    raw = "foo",
    pattern = "\\V\\c\\<foo\\>",
    hl_group = "PinWord1",
  })

  local slot = state.find_slot_by_raw_or_pattern("bar")
  MiniTest.expect.equality(slot, nil)
end

T["touch_slot updates order and last_used"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  state.set_slot(1, {
    raw = "foo",
    pattern = "\\V\\c\\<foo\\>",
    hl_group = "PinWord1",
  })
  state.set_slot(2, {
    raw = "bar",
    pattern = "\\V\\c\\<bar\\>",
    hl_group = "PinWord2",
  })

  state.touch_slot(1)
  state.touch_slot(2)

  local global = vim.g.pinwords_global
  MiniTest.expect.equality(#global.order, 2)
  MiniTest.expect.equality(global.order[1], 1)
  MiniTest.expect.equality(global.order[2], 2)

  local tick1 = global.last_used[1]
  local tick2 = global.last_used[2]
  MiniTest.expect.equality(type(tick1), "number")
  MiniTest.expect.equality(type(tick2), "number")
  MiniTest.expect.equality(tick2 > tick1, true)
end

T["touch_slot removes existing entry from order before appending"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  state.set_slot(1, {
    raw = "foo",
    pattern = "\\V\\c\\<foo\\>",
    hl_group = "PinWord1",
  })
  state.set_slot(2, {
    raw = "bar",
    pattern = "\\V\\c\\<bar\\>",
    hl_group = "PinWord2",
  })

  state.touch_slot(1)
  state.touch_slot(2)
  state.touch_slot(1)

  local global = vim.g.pinwords_global
  MiniTest.expect.equality(#global.order, 2)
  MiniTest.expect.equality(global.order[1], 2)
  MiniTest.expect.equality(global.order[2], 1)
end

T["find_available_slot with first_empty strategy returns first empty"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  state.set_slot(2, {
    raw = "bar",
    pattern = "\\V\\c\\<bar\\>",
    hl_group = "PinWord2",
  })

  local slot = state.find_available_slot("first_empty", 3)
  MiniTest.expect.equality(slot, 1)
end

T["find_available_slot with first_empty returns nil when full"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  state.set_slot(1, { raw = "a", pattern = "a", hl_group = "PinWord1" })
  state.set_slot(2, { raw = "b", pattern = "b", hl_group = "PinWord2" })
  state.set_slot(3, { raw = "c", pattern = "c", hl_group = "PinWord3" })

  local slot = state.find_available_slot("first_empty", 3)
  MiniTest.expect.equality(slot, nil)
end

T["find_available_slot with cycle strategy finds next after last used"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  state.set_slot(1, { raw = "a", pattern = "a", hl_group = "PinWord1" })
  state.set_slot(3, { raw = "c", pattern = "c", hl_group = "PinWord3" })
  state.touch_slot(1)

  local slot = state.find_available_slot("cycle", 3)
  MiniTest.expect.equality(slot, 2)
end

T["find_available_slot with cycle strategy wraps around"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  state.set_slot(1, { raw = "a", pattern = "a", hl_group = "PinWord1" })
  state.set_slot(2, { raw = "b", pattern = "b", hl_group = "PinWord2" })
  state.touch_slot(2)

  local slot = state.find_available_slot("cycle", 3)
  MiniTest.expect.equality(slot, 3)
end

T["find_available_slot with lru strategy finds empty slot first"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  state.set_slot(1, { raw = "a", pattern = "a", hl_group = "PinWord1" })
  state.set_slot(3, { raw = "c", pattern = "c", hl_group = "PinWord3" })
  state.touch_slot(1)
  state.touch_slot(3)

  local slot = state.find_available_slot("lru", 3)
  MiniTest.expect.equality(slot, 2)
end

T["find_available_slot with lru returns least recently used when full"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  state.set_slot(1, { raw = "a", pattern = "a", hl_group = "PinWord1" })
  state.set_slot(2, { raw = "b", pattern = "b", hl_group = "PinWord2" })
  state.set_slot(3, { raw = "c", pattern = "c", hl_group = "PinWord3" })
  state.touch_slot(1)
  state.touch_slot(2)
  state.touch_slot(3)

  state.touch_slot(2)
  state.touch_slot(3)

  local slot = state.find_available_slot("lru", 3)
  MiniTest.expect.equality(slot, 1)
end

T["evict_slot with replace_oldest returns first in order"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  state.set_slot(1, { raw = "a", pattern = "a", hl_group = "PinWord1" })
  state.set_slot(2, { raw = "b", pattern = "b", hl_group = "PinWord2" })
  state.set_slot(3, { raw = "c", pattern = "c", hl_group = "PinWord3" })
  state.touch_slot(1)
  state.touch_slot(2)
  state.touch_slot(3)

  local slot = state.evict_slot("replace_oldest")
  MiniTest.expect.equality(slot, 1)
end

T["evict_slot with replace_last returns last in order"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  state.set_slot(1, { raw = "a", pattern = "a", hl_group = "PinWord1" })
  state.set_slot(2, { raw = "b", pattern = "b", hl_group = "PinWord2" })
  state.set_slot(3, { raw = "c", pattern = "c", hl_group = "PinWord3" })
  state.touch_slot(1)
  state.touch_slot(2)
  state.touch_slot(3)

  local slot = state.evict_slot("replace_last")
  MiniTest.expect.equality(slot, 3)
end

T["evict_slot with no_op returns nil"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  state.set_slot(1, { raw = "a", pattern = "a", hl_group = "PinWord1" })

  local slot = state.evict_slot("no_op")
  MiniTest.expect.equality(slot, nil)
end

T["evict_slot with empty slots returns nil"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  local slot = state.evict_slot("replace_oldest")
  MiniTest.expect.equality(slot, nil)
end

T["prune_global_state removes slots above max"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  state.set_slot(1, { raw = "a", pattern = "a", hl_group = "PinWord1" })
  state.set_slot(5, { raw = "e", pattern = "e", hl_group = "PinWord5" })
  state.set_slot(10, { raw = "j", pattern = "j", hl_group = "PinWord10" })
  state.touch_slot(1)
  state.touch_slot(5)
  state.touch_slot(10)

  state.prune_global_state(3)

  local slots = state.get_slots()
  MiniTest.expect.equality(slots[1].raw, "a")
  MiniTest.expect.equality(slots[5], nil)
  MiniTest.expect.equality(slots[10], nil)

  local global = vim.g.pinwords_global
  MiniTest.expect.equality(#global.order, 1)
end

T["prune_global_state removes large slots from order"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  state.set_slot(1, { raw = "a", pattern = "a", hl_group = "PinWord1" })
  state.set_slot(2, { raw = "b", pattern = "b", hl_group = "PinWord2" })
  state.set_slot(5, { raw = "e", pattern = "e", hl_group = "PinWord5" })
  state.touch_slot(5)
  state.touch_slot(1)
  state.touch_slot(2)

  state.prune_global_state(3)

  local global = vim.g.pinwords_global
  MiniTest.expect.equality(#global.order, 2)
  MiniTest.expect.equality(global.order[1], 1)
  MiniTest.expect.equality(global.order[2], 2)
end

T["prune_global_state removes large slots from last_used"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  state.set_slot(1, { raw = "a", pattern = "a", hl_group = "PinWord1" })
  state.set_slot(5, { raw = "e", pattern = "e", hl_group = "PinWord5" })
  state.touch_slot(5)
  state.touch_slot(1)

  state.prune_global_state(3)

  local global = vim.g.pinwords_global
  MiniTest.expect.equality(global.last_used[1], global.tick)
  MiniTest.expect.equality(global.last_used[5], nil)
end

T["get_win_state returns valid win state"] = function()
  helpers.setup_buffer({ "test" })
  local win = vim.api.nvim_get_current_win()

  local state = require("pinwords.state")
  local win_state = state.get_win_state(win)

  MiniTest.expect.equality(type(win_state), "table")
  MiniTest.expect.equality(type(win_state.match_ids), "table")
  MiniTest.expect.equality(type(win_state.cword), "table")
  MiniTest.expect.equality(win_state.cword.enabled, false)
end

T["set_win_state stores window state"] = function()
  helpers.setup_buffer({ "test" })
  local win = vim.api.nvim_get_current_win()

  local state = require("pinwords.state")
  local new_state = {
    match_ids = { [1] = 123 },
    cword = { enabled = true, match_id = 456, pattern = "test" },
  }

  state.set_win_state(win, new_state)

  local retrieved = state.get_win_state(win)
  MiniTest.expect.equality(retrieved.match_ids[1], 123)
  MiniTest.expect.equality(retrieved.cword.enabled, true)
  MiniTest.expect.equality(retrieved.cword.match_id, 456)
  MiniTest.expect.equality(retrieved.cword.pattern, "test")
end

T["get_win_state initializes missing fields"] = function()
  helpers.setup_buffer({ "test" })
  local win = vim.api.nvim_get_current_win()

  vim.api.nvim_win_set_var(win, "pinwords", {})

  local state = require("pinwords.state")
  local win_state = state.get_win_state(win)

  MiniTest.expect.equality(type(win_state.match_ids), "table")
  MiniTest.expect.equality(type(win_state.cword), "table")
  MiniTest.expect.equality(win_state.cword.enabled, false)
end

T["get_win_state fixes invalid cword.enabled"] = function()
  helpers.setup_buffer({ "test" })
  local win = vim.api.nvim_get_current_win()

  vim.api.nvim_win_set_var(win, "pinwords", {
    match_ids = {},
    cword = {},
  })

  local state = require("pinwords.state")
  local win_state = state.get_win_state(win)

  MiniTest.expect.equality(win_state.cword.enabled, false)
end

T["init_global_state loads existing state"] = function()
  helpers.setup_buffer({ "test" })

  vim.g.pinwords_global = {
    slots = {
      [1] = { raw = "test", pattern = "test", hl_group = "PinWord1" },
    },
  }

  local state = require("pinwords.state")
  state.init_global_state()

  local slots = state.get_slots()
  MiniTest.expect.equality(slots[1].raw, "test")
end

T["init_global_state fixes invalid slots table internally"] = function()
  helpers.setup_buffer({ "test" })

  -- Set invalid global state after setup
  vim.g.pinwords_global = { slots = "invalid" }

  local state = require("pinwords.state")
  state.init_global_state()

  -- After init_global_state, internal slots should be fixed
  local slots = state.get_slots()
  MiniTest.expect.equality(type(slots), "table")
  MiniTest.expect.equality(next(slots), nil)
end

T["find_slot_by_pattern is deprecated but still works"] = function()
  helpers.setup_buffer({ "test" })

  local state = require("pinwords.state")
  state.clear_all()

  state.set_slot(1, {
    raw = "foo",
    pattern = "\\V\\c\\<foo\\>",
    hl_group = "PinWord1",
  })

  local slot = state.find_slot_by_pattern("\\V\\c\\<foo\\>")
  MiniTest.expect.equality(slot, 1)
end

return T
