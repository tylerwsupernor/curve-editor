local registered

pd = { Class = {}, Clock = {} }
Path = function()
  return { line_to = function() end }
end
function pd.Class:new()
  local cls = {}
  setmetatable(cls, { __index = self })
  return cls
end
function pd.Class:register()
  registered = self
  return self
end
function pd.Class:set_size(w, h) self._width, self._height = w, h end
function pd.Class:get_size() return self._width, self._height end
function pd.Class:outlet(n, selector, atoms)
  self._out = self._out or {}
  self._out[n] = { selector = selector, atoms = atoms }
end
function pd.Class:repaint() end
function pd.Clock:new() return setmetatable({}, { __index = self }) end
function pd.Clock:register() return self end
function pd.Clock:delay() end
function pd.post(message) pd.last_post = message end

assert(loadfile("src/curve-editor.pd_lua"))()

local function new_editor(atoms)
  local obj = setmetatable({}, { __index = registered })
  assert(obj:initialize(nil, atoms))
  return obj
end

local function close(a, b, epsilon)
  return math.abs(a - b) <= (epsilon or 1e-10)
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
local expected_legacy_state = { 0, 0, 0.5, 1, 1, 0 }
for i, value in ipairs(expected_legacy_state) do assert(legacy._out[2].atoms[i] == value) end

local full = new_editor()
full:in_1_fullrange({ 1 })
full:paint(graphics)
assert_symmetric(full._out[1].atoms)
assert(close(full._out[1].atoms[257], 0.5), "default center sample changed")
assert(full._out[2].atoms[1] == -271828)
assert(full._out[2].atoms[2] == 2)
assert(full._out[2].atoms[3] == 1)
assert(full._out[2].atoms[4] == 0)
assert(full._out[2].atoms[5] == 300 and full._out[2].atoms[6] == 300)

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
migrated:in_1_list({ -271828, 2, 1, 1, 300, 300, 0, 0, 0.5, 1, 1 })
for i, value in ipairs(old_state) do
  assert(migrated._out[2].atoms[i] == value, "malformed load replaced live state")
end

full:in_1_size({ 480, 360 })
assert(full._width == 480 and full._height == 360)
local sized = new_editor()
sized:in_1_list(full._out[2].atoms)
assert(sized._width == 480 and sized._height == 360)

print("curve-editor Lua behavior checks passed")
