local new_editor = dofile("tests/pd-stub.lua")

local function close(actual, expected)
  assert(math.abs(actual - expected) < 1e-9,
    "expected " .. expected .. ", got " .. actual)
end

local fixtures = {
  { "linear", 0, { { 0.25, 0 }, { 0.5, 0 }, { 0.75, 0.5 } } },
  { "linear", 0.5, { { 0.25, 0.25 }, { 0.5, 0.5 }, { 0.75, 0.75 } } },
  { "linear", 1, { { 0.25, 0.5 }, { 0.5, 1 }, { 0.75, 1 } } },
  { "square", 0, { { 0.25, 0 }, { 0.5, 0.5 }, { 0.75, 1 } } },
  { "square", 1, { { 0.25, 1 }, { 0.5, 0.5 }, { 0.75, 0 } } },
  { "square", 0.25, { { 0.02, 0 }, { 0.08, 1 }, { 0.125, 0.5 } } },
  { "square", 0.75, { { 0.02, 1 }, { 0.08, 0 }, { 0.125, 0.5 } } },
  { "square", 0.5, { { 1 / 60, 1 }, { 1 / 30, 0.5 }, { 1 / 20, 0 }, { 59 / 60, 0 } } },
  { "triangle", 0, { { 0.25, 0.25 }, { 0.5, 0.5 }, { 0.75, 0.75 } } },
  { "triangle", 0.1, { { 0.1, 0.5 }, { 0.2, 1 }, { 0.4, 0 }, { 0.8, 0 } } },
  { "triangle", 1, { { 1 / 31, 1 }, { 2 / 31, 0 }, { 30 / 31, 0 } } },
  { "sine", 0, { { 0.25, (1 - math.sqrt(0.5)) / 2 }, { 0.5, 0.5 }, { 0.75, (1 + math.sqrt(0.5)) / 2 } } },
  { "sine", 0.1, { { 0.1, 0.5 }, { 0.2, 1 }, { 0.4, 0 }, { 0.8, 0 } } },
  { "sine", 1, { { 1 / 31, 1 }, { 2 / 31, 0 }, { 30 / 31, 0 } } },
  { "stairs", 0, { { 0.01, 0.5 }, { 0.5, 0.5 }, { 0.99, 0.5 } } },
  { "stairs", 1, { { 0.1, 0 }, { 1 / 3, 0.25 }, { 0.5, 0.5 }, { 2 / 3, 0.75 }, { 0.9, 1 } } },
  { "stairs", 0.25, { { 1 / 12, 1 / 12 }, { 1 / 6, 1 / 6 }, { 11 / 12, 11 / 12 } } },
  { "stairs", 0.75, { { 1 / 16, 0 }, { 1 / 8, 1 / 14 }, { 3 / 16, 1 / 7 }, { 15 / 16, 1 } } },
  { "stairs", 0.5, { { 1 / 24, 0 }, { 1 / 12, 1 / 22 }, { 1 / 8, 1 / 11 }, { 23 / 24, 1 } } },
}

for _, fixture in ipairs(fixtures) do
  local kind, h = fixture[1], fixture[2]
  for _, heights in ipairs({ { 0.1, 0.9 }, { 0.9, 0.1 }, { 0.4, 0.4 } }) do
    local a, b = heights[1], heights[2]
    local editor = new_editor()
    editor:in_1_list({ 0, a, 0.5, 1, b })
    editor:in_1_type({ 1, kind })
    editor:in_1_bend({ 1, kind == "linear" and b < a and 1 - h or h })
    close(editor:segment_value(1, 0), a)
    close(editor:segment_value(1, 1), b)
    for _, sample in ipairs(fixture[3]) do
      close(editor:segment_value(1, sample[1]), a + (b - a) * sample[2])
    end
    for i, value in ipairs(editor._out[1].atoms) do
      close(value, editor:segment_value(1, (i - 1) / 256))
      assert(value == value and value >= 0 and value <= 1)
    end
  end
end

for _, kind in ipairs({ "tension", "linear", "square", "triangle", "sine", "stairs" }) do
  local editor = new_editor()
  editor:in_1_list({ 0, 0.1, 0.5, 0.25, 0.8, 0.5, 0.503, 0.2, 0.5, 1, 0.9 })
  editor:in_1_type({ 1, "square" })
  editor:in_1_type({ 2, kind })
  editor:in_1_type({ 3, "square" })
  close(editor.current_values[65], 0.8)
  for _, sample in ipairs({ { 129, 2, 0.5 }, { 130, 3, 129 / 256 } }) do
    local i, segment, x = table.unpack(sample)
    local a, b = editor.points[segment], editor.points[segment + 1]
    close(editor.current_values[i], editor:segment_value(segment, (x - a.x) / (b.x - a.x)))
  end
end

local function painted(editor)
  local paths = {}
  editor:in_1_grid({ 0 })
  editor:paint({
    set_color = function() end,
    fill_ellipse = function() end,
    stroke_path = function(_, path, width)
      paths[#paths + 1] = { points = path.points, width = width }
    end,
  })
  return paths
end

local function normalized(point)
  return (point.x - 12) / 276, 1 - (point.y - 12) / 276
end

for _, fixture in ipairs(fixtures) do
  local kind, h = fixture[1], fixture[2]
  local editor = new_editor()
  editor:in_1_type({ 1, kind })
  editor:in_1_bend({ 1, h })
  local paths = painted(editor)
  assert(#paths == 1, "sampled Results obscures geometry without a Base")
  local points = paths[1].points
  close(points[1].x, 12)
  close(points[1].y, 288)
  close(points[#points].x, 288)
  close(points[#points].y, 12)
  local jumps = 0
  for i = 2, #points do
    local x0, y0 = normalized(points[i - 1])
    local x1, y1 = normalized(points[i])
    assert(x1 >= x0 - 1e-12)
    if kind == "square" or kind == "stairs" then
      assert(math.abs(x1 - x0) < 1e-12 or math.abs(y1 - y0) < 1e-12, "slanted jump in " .. kind)
      if math.abs(y1 - y0) > 1e-12 then
        jumps = jumps + 1
        if x1 > 0 and x1 < 1 then close(editor:segment_value(1, x1), (y0 + y1) / 2) end
      end
    end
  end
  if kind == "square" and h == 0.5 then assert(jumps == 31, "maximum Square density") end
  if kind == "stairs" and h == 0.5 then assert(jumps == 11, "maximum Stairs density") end
  if kind == "stairs" and h == 0 then assert(jumps == 2, "sparse Stairs anchor jumps") end
  if kind == "triangle" and h == 1 then assert(#points == 32, "maximum Triangle density") end

  editor:in_1_fullrange({ 1 })
  local mirrored = painted(editor)
  assert(#mirrored == 2)
  if kind == "square" and h == 0.5 then
    assert(mirrored[2].width < 138 / 30, "dense Square strokes merge into a solid block")
  end
  for i, point in ipairs(mirrored[1].points) do
    close(point.x, 300 - mirrored[2].points[i].x)
    close(point.y, 300 - mirrored[2].points[i].y)
  end
  editor:in_1_bipolar({ 1 })
  local released = painted(editor)
  local negative = released[1].points
  for i, point in ipairs(negative) do
    local x, y = normalized(point)
    local partner = released[2].points[#negative + 1 - i]
    local px, py = normalized(partner)
    close(x, 1 - px)
    close(y, 1 - py)
  end
end

local narrow = new_editor()
narrow:in_1_list({ 0, 0, 0.5, 0.5, 0, 0.5, 0.51, 1, 0.5, 1, 1 })
narrow:in_1_type({ 2, "triangle" })
narrow:in_1_bend({ 2, 1 })
assert(#painted(narrow)[2].points == 32, "narrow segment lost drawn peaks")
assert(#narrow.current_values == 257, "density changed output resolution")

print("curve-editor segment geometry and drawing checks passed")
