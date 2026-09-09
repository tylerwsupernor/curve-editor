local new_editor = dofile("tests/pd-stub.lua")

local function close(a, b, epsilon)
  return math.abs(a - b) <= (epsilon or 1e-10)
end

local function assert_equal(actual, expected, label)
  label = label or "value"
  if type(expected) == "table" then
    assert(type(actual) == "table", label .. " is not a table")
    for key, value in pairs(expected) do assert_equal(actual[key], value, label .. "." .. tostring(key)) end
    for key in pairs(actual) do assert(expected[key] ~= nil, label .. " has extra key " .. tostring(key)) end
  else
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item) end
  return result
end

local types = { "tension", "linear", "square", "triangle", "sine", "stairs" }
local defaults = { type = "tension", linear = 0.5, square = 0.5, triangle = 0, sine = 0, stairs = 0.5 }

local function assert_samples(editor)
  local values = editor._out[1].atoms
  assert(#values == (editor.full_range and 513 or 257))
  for i, value in ipairs(values) do
    assert(value == value and value >= 0 and value <= 1, "invalid sample " .. i)
    if not editor.has_base then assert(value == editor.current_values[i]) end
  end
end

local function assert_rejected(editor, handler, atoms)
  local before = copy({ editor.points, editor.curvatureOffsets, editor.segments,
    editor._out, editor._pending, editor.dragging })
  local output_count = editor._output_count
  pd.last_post = nil
  editor[handler](editor, atoms)
  assert(pd.last_post and pd.last_post:find("rejected", 1, true), "missing rejection from " .. handler)
  assert_equal({ editor.points, editor.curvatureOffsets, editor.segments,
    editor._out, editor._pending, editor.dragging }, before, handler .. " mutated live state")
  assert(editor._output_count == output_count, handler .. " emitted on rejection")
end

local function assert_symmetric(values)
  assert(#values == 513, "expected 513 samples")
  for i = 1, 256 do
    assert(type(values[i]) == "number" and values[i] == values[i])
    assert(close(values[i], 1 - values[514 - i], 1e-9),
      "mirror mismatch at " .. i .. ": " .. values[i] .. " vs " .. (1 - values[514 - i]))
  end
end

local function pixel(nx, ny)
  return 12 + nx * 276, 12 + (1 - ny) * 276
end

local legacy = new_editor()
local graphics = {
  set_color = function() end,
  stroke_path = function() end,
  fill_ellipse = function() end,
}
legacy:in_1_bang()
legacy:paint(graphics)
assert(#legacy._out[1].atoms == 257, "legacy output changed size")
for i, value in ipairs(legacy._out[1].atoms) do
  assert(close(value, (i - 1) / 256), "legacy diagonal changed")
end
legacy:output_state()
local expected_legacy_state = { -271828, 3, 0, 0, 300, 300, 2,
  0, 0, 0.5, 0, 0.5, 0.5, 0, 0, 0.5, 1, 1 }
assert_equal(legacy._out[2].atoms, expected_legacy_state, "classic v3 state")

local full = new_editor()
full:in_1_fullrange({ 1 })
full:paint(graphics)
assert_symmetric(full._out[1].atoms)
assert(close(full._out[1].atoms[257], 0.5), "default center sample changed")
assert(full._out[2].atoms[1] == -271828)
assert(full._out[2].atoms[2] == 3)
assert(full._out[2].atoms[3] == 1)
assert(full._out[2].atoms[4] == 0)
assert(full._out[2].atoms[5] == 300 and full._out[2].atoms[6] == 300)
assert(full._out[2].atoms[7] == 3 and #full._out[2].atoms == 27)

local created_full = new_editor({ "fullrange" })
created_full:in_1_bang()
assert(created_full.full_range and #created_full._out[1].atoms == 513)

local point_count = #full.points
full.dcclock_pending = false
full:mouse_down(pixel(0.25, 0.25))
assert(#full.points == point_count, "ghost side accepted an edit")
full.dcclock_pending = false
full:mouse_down(pixel(0.75, 0.8))
assert(#full.points == point_count + 2, "positive point did not create its mirror")
assert(close(full.points[2].x, 0.25) and close(full.points[2].y, 0.2))
full:mouse_up()

local center_index
for i, point in ipairs(full.points) do
  if point.center then center_index = i break end
end
full._pending = { type = "point", index = center_index, x = 0.5, y = 0.7 }
full.glmetro_pending = true
full:tick_update()
assert(close(full._out[1].atoms[257], 0.7), "zero-crossing point did not move vertically")
assert_symmetric(full._out[1].atoms)

local positive_endpoint = #full.points
full._pending = { type = "point", index = positive_endpoint, x = 1, y = 0.8 }
full.glmetro_pending = true
full:tick_update()
assert_symmetric(full._out[1].atoms)
assert(close(full.points[1].y, 0.2))
local positive_bend = #full.curvatureOffsets
full._pending = { type = "segment", index = positive_bend, offset = 0.82 }
full.glmetro_pending = true
full:tick_update()
assert_symmetric(full._out[1].atoms)

full:in_1_bipolar({ 1 })
full:paint(graphics)
local released_center
for i, point in ipairs(full.points) do
  if point.center then released_center = i break end
end
full._pending = { type = "point", index = released_center, x = 0.6, y = 0.35 }
full.glmetro_pending = true
full:tick_update()
assert(close(full.points[released_center].x, 0.6) and close(full.points[released_center].y, 0.35))
assert(not full.points[released_center].fixed and not full.points[released_center].center)
local before_positive = full._out[1].atoms[513]
full._pending = { type = "point", index = 1, x = 0, y = 0.4 }
full.glmetro_pending = true
full:tick_update()
assert(close(full._out[1].atoms[1], 0.4))
assert(close(full._out[1].atoms[513], before_positive))
local bipolar_saved = full._out[2].atoms
local bipolar_restored = new_editor()
bipolar_restored:in_1_list(bipolar_saved)
assert(bipolar_restored.full_range and bipolar_restored.bipolar)
for i, value in ipairs(bipolar_saved) do assert(bipolar_restored._out[2].atoms[i] == value) end
full:in_1_bipolar({ 0 })
assert_symmetric(full._out[1].atoms)
assert(close(full._out[1].atoms[1], 1 - full._out[1].atoms[513]))

local saved = full._out[2].atoms
local restored = new_editor()
restored:in_1_list(saved)
assert(restored.full_range and not restored.bipolar)
assert_symmetric(restored._out[1].atoms)
for i, value in ipairs(saved) do assert(restored._out[2].atoms[i] == value) end
restored:in_1_fullrange({ 0 })
assert(not restored.full_range and #restored._out[1].atoms == 257)
assert(restored._width == 300 and restored._height == 300)

local layered = new_editor()
layered:in_1_fullrange({ 1 })
layered:in_1_base({ 0, 0, 0.5, 0.6, 0.85, 0.25, 1, 1 })
assert(#layered._out[1].atoms == 513)
assert_symmetric(layered._out[1].atoms)

local migrated = new_editor()
migrated:in_1_fullrange({ 1 })
migrated:in_1_list({ 0, 0, 0.8, 0.5, 0.7, 0.2, 1, 1, 1 })
assert(migrated.full_range and not migrated.bipolar)
assert_symmetric(migrated._out[1].atoms)

local old_state = {}
for i, value in ipairs(migrated._out[2].atoms) do old_state[i] = value end
migrated:in_1_list({ -271828, 2, 1, 1, 300, 300, 0, 0, 0.5, 1 })
for i, value in ipairs(old_state) do
  assert(migrated._out[2].atoms[i] == value, "malformed load replaced live state")
end

full:in_1_size({ 480, 360 })
assert(full._width == 480 and full._height == 360)
local sized = new_editor()
sized:in_1_list(full._out[2].atoms)
assert(sized._width == 480 and sized._height == 360)

local baseline = dofile("tests/tension-baseline.lua")
local baseline_state = { 0, 0.12, 0, 0.173, 0.87, 0.21, 0.409, 0.22, 0.5,
  0.617, 0.76, 0.86, 0.833, 0.18, 1, 1, 0.91 }
for mode = 1, 2 do
  local editor = new_editor(mode == 2 and { "fullrange" } or nil)
  editor:in_1_list(baseline_state)
  assert_equal(editor.current_values, baseline[mode], "1.2.1 Tension baseline " .. mode)
end

for _, old in ipairs({
  { 0, 0.2, 0.8, 0.4, 0.7, 0.2, 1, 0.9 },
  { 0, 0.2, 0.8, 0.4, 0.7, 0.2, 1, 0.9, 1 },
  { -271828, 2, 1, 0, 420, 360, 0, 0, 0.2, 0.5, 0.5, 0.8, 1, 1 },
  { -271828, 2, 1, 1, 480, 360, 0, 0.2, 0.8, 0.4, 0.7, 0.2, 1, 0.9 },
}) do
  local editor = new_editor()
  pd.last_post = nil
  editor:in_1_list(old)
  assert(not pd.last_post, "legacy migration rejected")
  assert(editor._out[2].atoms[2] == 3)
  for _, segment in ipairs(editor.segments) do assert_equal(segment, defaults) end
  assert_samples(editor)
end

local controlled = new_editor()
controlled:in_1_bang()
controlled._pending = { type = "segment", index = 1, offset = 0.6 }
controlled.dragging = { type = "segment", index = 1 }
local nan = 0 / 0
for _, handler in ipairs({ "in_1_type", "in_1_bend" }) do
  local value = handler == "in_1_type" and "linear" or 0.3
  for _, index in ipairs({ 0, -1, 2, 1.5, "bad", math.huge, -math.huge, nan }) do
    assert_rejected(controlled, handler, { index, value })
  end
  for _, atoms in ipairs({ {}, { 1 }, { 1, value, 0 } }) do
    assert_rejected(controlled, handler, atoms)
  end
end
for _, name in ipairs({ "Linear", "unknown", 0, 5, nan }) do
  assert_rejected(controlled, "in_1_type", { 1, name })
end
for _, value in ipairs({ -0.01, 1.01, "bad", math.huge, -math.huge, nan }) do
  assert_rejected(controlled, "in_1_bend", { 1, value })
end
controlled:in_1_type({ 1, "linear" })
assert(controlled.curvatureOffsets[1] == 0.6, "type switch lost pending Tension drag")
assert(not controlled._pending and not controlled.dragging)

for _, heights in ipairs({ { 0.1, 0.9 }, { 0.9, 0.1 }, { 0.4, 0.4 } }) do
  for _, kind in ipairs(types) do
    for _, snapping in ipairs({ false, true }) do
      local editor = new_editor()
      editor:in_1_list({ 0, heights[1], 0.5, 1, heights[2] })
      editor:in_1_type({ 1, kind })
      editor:in_1_bend({ 1, 0.3 })
      editor:in_1_snap({ snapping and 1 or 0 })
      editor:in_1_gridsub({ 3 })
      editor:mouse_down(pixel(0.5, 0.5))
      editor.glmetro_pending = false
      editor:mouse_drag(pixel(0.5, 0.6))
      editor:mouse_up()
      local expected_h = 0.3 + (snapping and 0.075 or 0.15)
      local actual_h = editor.segments[1][kind]
      if kind == "tension" then
        actual_h = heights[2] >= heights[1] and 1 - editor.curvatureOffsets[1] or editor.curvatureOffsets[1]
      end
      assert(close(actual_h, expected_h), kind .. " upward drag / bend mapping")
      assert_samples(editor)
    end
  end
end

local retained = new_editor()
for i, kind in ipairs(types) do
  retained:in_1_type({ 1, kind })
  retained:in_1_bend({ 1, i / 8 })
end
local retained_segment, retained_raw = copy(retained.segments[1]), retained.curvatureOffsets[1]
for i, kind in ipairs(types) do
  retained:in_1_type({ 1, kind })
  retained_segment.type = kind
  assert_equal(retained.segments[1], retained_segment, "inactive controls")
  assert(retained.curvatureOffsets[1] == retained_raw)
  assert(retained._out[2].atoms[11] == i - 1, "type code")
end
retained.dcclock_pending = false
retained:mouse_down(pixel(0.5, 0.7))
retained:mouse_up()
assert_equal(retained.segments[1], retained_segment, "insertion left controls")
assert_equal(retained.segments[2], defaults, "insertion right controls")
assert(retained.curvatureOffsets[1] == retained_raw and retained.curvatureOffsets[2] == 0.5)
retained.dcclock_pending = false
retained:mouse_down(pixel(0.5, 0.7))
retained_segment.linear = 0.5
assert(#retained.points == 2 and #retained.segments == 1 and #retained.curvatureOffsets == 1)
assert_equal(retained.segments[1], retained_segment, "deletion controls")
assert(retained.curvatureOffsets[1] == 0.5)

local mixed = new_editor()
mixed:in_1_list({ 0, 0, 0.5, 0.125, 0.8, 0.5, 0.25, 0.2, 0.5,
  0.5, 0.7, 0.5, 0.625, 0.3, 0.5, 0.875, 0.9, 0.5, 1, 1 })
for i, active in ipairs(types) do
  for j, kind in ipairs(types) do
    mixed:in_1_type({ i, kind })
    mixed:in_1_bend({ i, (i + j) / 16 })
  end
  mixed:in_1_type({ i, active })
end
local classic_mixed = copy(mixed._out[2].atoms)
local function roundtrip(editor)
  local clone = new_editor()
  clone:in_1_list(editor._out[2].atoms)
  assert_equal(clone._out, editor._out, "round trip outputs")
  assert_equal(clone.segments, editor.segments, "round trip controls")
  assert_samples(clone)
end
roundtrip(mixed)
mixed:in_1_fullrange({ 1 })
mixed:in_1_size({ 640, 480 })
roundtrip(mixed)
assert_symmetric(mixed._out[1].atoms)
for i = 1, 6 do
  local negative, positive = mixed.segments[i], mixed.segments[13 - i]
  assert(negative.type == positive.type)
  assert(close(negative.linear, 1 - positive.linear))
  assert(close(mixed.curvatureOffsets[i], 1 - mixed.curvatureOffsets[13 - i]))
  for _, kind in ipairs({ "square", "triangle", "sine", "stairs" }) do
    assert(negative[kind] == positive[kind])
  end
  for _, t in ipairs({ 0, 0.125, 0.5, 0.75, 1 }) do
    assert(close(mixed:segment_value(i, t), 1 - mixed:segment_value(13 - i, 1 - t)))
  end
  assert_rejected(mixed, "in_1_type", { i, "linear" })
  assert_rejected(mixed, "in_1_bend", { i, 0.4 })
end
mixed:in_1_fullrange({ 0 })
for i, value in ipairs(classic_mixed) do
  local field = (i - 8) % 9
  if i >= 8 and field <= 1 then
    assert(close(mixed._out[2].atoms[i], value), "range conversion coordinate")
  else
    assert_equal(mixed._out[2].atoms[i], value, "range conversion retained controls")
  end
end
mixed:in_1_fullrange({ 1 })
mixed:in_1_bipolar({ 1 })
mixed:in_1_type({ 1, "stairs" })
mixed:in_1_bend({ 1, 0.12 })
assert(mixed.segments[12].stairs ~= 0.12, "bipolar edit leaked to positive segment")
roundtrip(mixed)
mixed:in_1_bipolar({ 0 })
assert_symmetric(mixed._out[1].atoms)
mixed:in_1_list(classic_mixed)
assert(not mixed.full_range and mixed.width == 300)
assert_equal(mixed._out[2].atoms, classic_mixed, "explicit classic restore")

local without_center = new_editor({ "fullrange" })
without_center:in_1_bipolar({ 1 })
without_center:in_1_type({ 2, "sine" })
without_center:in_1_bend({ 2, 0.8 })
without_center._pending = { type = "point", index = 2, x = 0.625, y = 0.6 }
without_center.glmetro_pending = true
without_center:tick_update()
local asymmetric_state = copy(without_center._out[2].atoms)
for _, mode in ipairs({ "in_1_bipolar", "in_1_fullrange" }) do
  without_center:in_1_list(asymmetric_state)
  without_center[mode](without_center, { 0 })
  local index = mode == "in_1_bipolar" and 3 or 1
  assert_equal(without_center.segments[index], defaults, "missing center neutral segment")
  assert(without_center.segments[index + 1].sine == 0.8)
end

local valid = copy(classic_mixed)
for _, change in ipairs({
  { 2, 4 }, { 3, 2 }, { 4, 0.5 }, { 5, 79 }, { 5, 300.5 }, { 6, 2001 },
  { 5, 400 }, { 7, 1 }, { 7, 7.5 }, { 7, 8 }, { 8, 0.001 }, { #valid - 1, 0.999 },
  { 9, -0.01 }, { 9, 1.01 }, { 10, -0.1 }, { 10, 1.1 }, { 11, -1 }, { 11, 6 },
  { 11, 0.5 }, { 17, 0 },
}) do
  local bad = copy(valid)
  bad[change[1]] = change[2]
  assert_rejected(mixed, "in_1_list", bad)
end
for i = 1, #valid do
  for _, invalid in ipairs({ "bad", nan, math.huge, -math.huge }) do
    local bad = copy(valid)
    bad[i] = invalid
    assert_rejected(mixed, "in_1_list", bad)
  end
end
for i = 12, 16 do
  for _, invalid in ipairs({ -0.1, 1.1 }) do
    local bad = copy(valid)
    bad[i] = invalid
    assert_rejected(mixed, "in_1_list", bad)
  end
end
local truncated, extra = copy(valid), copy(valid)
table.remove(truncated)
extra[#extra + 1] = 0
assert_rejected(mixed, "in_1_list", truncated)
assert_rejected(mixed, "in_1_list", extra)
local missing_center = copy(asymmetric_state)
missing_center[4] = 0
assert_rejected(mixed, "in_1_list", missing_center)
local too_few = copy(expected_legacy_state)
too_few[3] = 1
assert_rejected(mixed, "in_1_list", too_few)

local near_center = copy(asymmetric_state)
near_center[4], near_center[17] = 0, 0.5 + 1e-10
assert_rejected(mixed, "in_1_list", near_center)
near_center[4] = 1
local precise = new_editor()
precise:in_1_list(near_center)
assert_equal(precise._out[2].atoms, near_center, "asymmetric near-center restore")
precise:in_1_bipolar({ 0 })
assert(#precise.points == 5, "near-center point replaced the actual center")
assert(precise.points[3].x == 0.5 and precise.points[4].x == near_center[17])
precise:in_1_type({ 3, "linear" })
assert(precise.segments[3].type == "linear", "near-center positive segment rejected")
assert_rejected(precise, "in_1_type", { 2, "square" })
roundtrip(precise)

local composition = new_editor()
composition:in_1_list(classic_mixed)
local own_state = copy(composition._out[2].atoms)
local base = new_editor()
base:in_1_list({ 0, 0.2, 0.5, 1, 0.8 })
base:in_1_type({ 1, "square" })
base:in_1_bend({ 1, 0.3 })
composition:in_1_base(base._out[2].atoms)
assert_equal(composition._out[2].atoms, own_state, "Base changed editor state")
for i, value in ipairs(composition.base_values) do
  assert(close(value, 0.2 + 0.6 * (i - 1) / 256), "Base applied segment type")
  local f = value * 256
  local j = math.min(255, math.floor(f))
  local expected = composition.current_values[j + 1] * (1 - (f - j)) + composition.current_values[j + 2] * (f - j)
  assert(close(composition.results_values[i], expected), "Base composition")
end
local old_base = copy(composition.base_points)
assert_rejected(composition, "in_1_base", truncated)
assert_equal(composition.base_points, old_base)
composition:in_1_base({ "clear" })
assert(not composition.has_base)
assert_samples(composition)

print("curve-editor Lua behavior checks passed")
