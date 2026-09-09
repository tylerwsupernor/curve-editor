local curve_editor = pd.Class:new():register("curve-editor")

local INSET = 12
local LEGACY_SAMPLES = 257
local FULL_RANGE_SAMPLES = 513
local STATE_MAGIC = -271828
local STATE_VERSION = 3
local FULL_RANGE_CODE = 1
local TYPE_NAMES = { "tension", "linear", "square", "triangle", "sine", "stairs" }
local TYPE_CODES = {}
for i, name in ipairs(TYPE_NAMES) do TYPE_CODES[name] = i - 1 end
local CLICK_RADIUS_SQ = 0.0025
local SNAP_EPS = 1e-9
local AMBIG_FRACTION = 0.15
local CURVE_POWER_MAX = 24
local SKEW_K = 3.0
local SEGMENT_SENSITIVITY = 1.5
local DOUBLECLICK_MS = 240
local POINT_GAP = 0.01
local GRID_SUB_DEFAULT = 16

local abs, sqrt, exp, floor = math.abs, math.sqrt, math.exp, math.floor

local function clamp(v, lo, hi) return math.min(hi, math.max(lo, v)) end
local function same(a, b) return abs(a - b) < SNAP_EPS end
local function snap(v, s) return floor(v / s + 0.5) * s end

local function sample_count(self)
  return self.full_range and FULL_RANGE_SAMPLES or LEGACY_SAMPLES
end

local function to_norm(self, x, y)
  local dw = self.width - 2 * INSET
  local dh = self.height - 2 * INSET
  local nx = (x - INSET) / dw
  local ny = 1 - (y - INSET) / dh
  return nx, ny
end

local function binsert_points(points, pt)
  local lo, hi = 1, #points
  while lo <= hi do
    local mid = (lo + hi) // 2
    if pt.x < points[mid].x then hi = mid - 1 else lo = mid + 1 end
  end
  table.insert(points, lo, pt)
  return lo
end

local function copy_values(values)
  local result = {}
  for i, value in ipairs(values) do result[i] = value end
  return result
end

local function new_segment()
  return { type = "tension", linear = 0.5, square = 0.5, triangle = 0, sine = 0, stairs = 0.5 }
end

local function copy_segment(segment, reflected)
  local result = new_segment()
  if segment then
    for key, value in pairs(segment) do result[key] = value end
  end
  if reflected then result.linear = 1 - result.linear end
  return result
end

local function default_segments(points)
  local segments = {}
  for i = 1, #points - 1 do segments[i] = new_segment() end
  return segments
end

local function positive_half(points, curvs, segments)
  local pts, bends, metadata = {}, {}, {}
  local first = nil
  for i, pt in ipairs(points) do
    if pt.x >= 0.5 then
      if not first then first = i end
      pts[#pts + 1] = {
        x = pt.x,
        y = pt.y,
        fixed = pt.fixed,
        center = pt.x == 0.5,
      }
    end
  end
  if first then
    for i = first, #points - 1 do
      bends[#bends + 1] = curvs[i] or 0.5
      metadata[#metadata + 1] = copy_segment(segments and segments[i])
    end
  end
  return pts, bends, metadata
end

local function ensure_positive_center(pos, bends, segments)
  if #pos == 0 or pos[1].x ~= 0.5 then
    table.insert(pos, 1, { x = 0.5, y = 0.5, fixed = true, center = true })
    table.insert(bends, 1, 0.5)
    table.insert(segments, 1, new_segment())
  else
    pos[1].x = 0.5
    pos[1].fixed, pos[1].center = true, true
  end
end

local function mirror_positive(points, curvs, segments)
  local pos, pos_curvs, pos_segments = positive_half(points, curvs, segments)
  ensure_positive_center(pos, pos_curvs, pos_segments)
  for _, pt in ipairs(pos) do pt.y = clamp(pt.y, 0.5, 1) end

  local pts, bends, metadata = {}, {}, {}
  for i = #pos, 2, -1 do
    local pt = pos[i]
    pts[#pts + 1] = {
      x = 1 - pt.x,
      y = 1 - pt.y,
      fixed = i == #pos,
    }
    bends[#bends + 1] = 1 - (pos_curvs[i - 1] or 0.5)
    metadata[#metadata + 1] = copy_segment(pos_segments[i - 1], true)
  end
  for _, pt in ipairs(pos) do pts[#pts + 1] = pt end
  for _, bend in ipairs(pos_curvs) do bends[#bends + 1] = bend end
  for _, segment in ipairs(pos_segments) do metadata[#metadata + 1] = segment end
  pts[1].fixed = true
  pts[#pts].fixed = true
  return pts, bends, metadata
end

local function legacy_to_full(points, curvs, segments)
  local pos, bends = {}, copy_values(curvs)
  for i, pt in ipairs(points) do
    pos[i] = {
      x = 0.5 + 0.5 * pt.x,
      y = 0.5 + 0.5 * pt.y,
      fixed = pt.fixed,
      center = i == 1,
    }
  end
  pos[1].x, pos[1].y = 0.5, 0.5
  pos[1].fixed, pos[1].center = true, true
  return mirror_positive(pos, bends, segments)
end

local function full_to_legacy(points, curvs, segments)
  local pos, pos_curvs, pos_segments = positive_half(points, curvs, segments)
  ensure_positive_center(pos, pos_curvs, pos_segments)
  local pts = {}
  for i, pt in ipairs(pos) do
    pts[i] = {
      x = clamp((pt.x - 0.5) * 2, 0, 1),
      y = clamp((pt.y - 0.5) * 2, 0, 1),
      fixed = pt.fixed,
    }
  end
  pts[1].fixed = true
  pts[#pts].fixed = true
  return pts, pos_curvs, pos_segments
end

local function skew_m(m)
  if m <= 0 then return 0 end
  if m >= 1 then return 1 end
  return (exp(SKEW_K * m) - 1) / (exp(SKEW_K) - 1)
end

function curve_editor:initialize(_, atoms)
  self.inlets = 1
  self.outlets = 2
  self.width, self.height = 300, 300
  self:set_size(self.width, self.height)
  self.points = {
    { x = 0, y = 0, fixed = true },
    { x = 1, y = 1, fixed = true },
  }
  self.curvatureOffsets = { 0.5 }
  self.segments = { new_segment() }
  self.base_points = {
    { x = 0, y = 0, fixed = true },
    { x = 1, y = 1, fixed = true },
  }
  self.base_curvatureOffsets = { 0.5 }
  -- Nothing has been layered under Your Curve yet. Until a base message
  -- arrives, Results must equal Your Curve exactly so the output matches
  -- what was drawn, as it did before 1.1.5.
  self.has_base = false
  self.current_values = {}
  self.base_values = {}
  self.results_values = {}
  self.dragging = nil
  self.drag_start_y = nil
  self.drag_start_offset = nil
  self.drag_slope_sign = nil
  self.doubleclickclock = pd.Clock:new():register(self, "dcclock")
  self.dcclock_pending = true
  self.globalmetro = pd.Clock:new():register(self, "glmetro")
  self.glmetro_pending = true
  self._pending = nil
  self.snap_enabled = false
  self.grid_enabled = true
  self.gridsub = GRID_SUB_DEFAULT
  self.full_range = false
  self.bipolar = false
  if atoms and atoms[1] == "fullrange" then
    self.points, self.curvatureOffsets, self.segments = legacy_to_full(self.points, self.curvatureOffsets, self.segments)
    self.base_points, self.base_curvatureOffsets = legacy_to_full(self.base_points, self.base_curvatureOffsets)
    self.full_range = true
  end
  self:interpolate_values()
  return true
end

local function segment_count(segment)
  local kind = segment.type
  local h = segment[kind]
  if kind == "square" then return 1 + floor(14 * (1 - abs(2 * h - 1)) + 0.5) end
  if kind == "stairs" then return 2 + floor(9 * (1 - abs(2 * h - 1)) + 0.5) end
  if kind == "triangle" or kind == "sine" then return 1 + 2 * floor(15 * h + 0.5) end
  return 1
end

local function segment_value(a, b, raw, segment, t)
  t = clamp(t, 0, 1)
  local ay, by = a.y, b.y
  local kind = segment and segment.type or "tension"
  if kind == "tension" then
    local midpoint = 0.5 * (ay + by)
    local d = raw - 0.5
    local power = 1 + skew_m(abs(d) * 2) * (CURVE_POWER_MAX - 1)
    local tn
    if d >= 0 then tn = t ^ power else tn = 1 - (1 - t) ^ power end
    local omt = 1 - tn
    return omt * omt * ay + 2 * omt * tn * midpoint + tn * tn * by
  end
  if t == 0 then return ay end
  if t == 1 then return by end
  if ay == by then return ay end
  local value
  if kind == "linear" then
    local corner = by >= ay and segment.linear or 1 - segment.linear
    value = t <= 0.5 and 2 * t * corner or corner + (2 * t - 1) * (1 - corner)
  elseif kind == "triangle" then
    value = 1 - abs((segment_count(segment) * t % 2) - 1)
  elseif kind == "sine" then
    value = (1 - math.cos(math.pi * segment_count(segment) * t)) * 0.5
  elseif kind == "square" then
    local q = 2 * segment_count(segment) * t
    if same(q, floor(q + 0.5)) then
      value = 0.5
    else
      value = (floor(q) + (segment.square >= 0.5 and 1 or 0)) % 2
    end
  elseif kind == "stairs" then
    local count = segment_count(segment)
    local lower = segment.stairs < 0.5
    local bins = lower and count - 1 or count + 1
    local q = bins * t
    local j = floor(q)
    if same(q, floor(q + 0.5)) then j = floor(q + 0.5) - 0.5 end
    value = lower and (j + 0.5) / bins or j / count
  end
  return ay + (by - ay) * value
end

function curve_editor:segment_value(index, t)
  if self.full_range and not self.bipolar and self.points[index + 1].x <= 0.5 then
    index, t = #self.segments + 1 - index, 1 - t
    return 1 - segment_value(self.points[index], self.points[index + 1], self.curvatureOffsets[index], self.segments[index], t)
  end
  return segment_value(self.points[index], self.points[index + 1], self.curvatureOffsets[index], self.segments[index], t)
end

local function interpolate_points(pts, curvs, vals, N, segments)
  local invN = 1 / (N - 1)
  for i = 1, N do vals[i] = (i - 1) * invN < pts[1].x and pts[1].y or pts[#pts].y end
  for seg = 1, #pts - 1 do
    local a, b = pts[seg], pts[seg + 1]
    local dx = b.x - a.x
    if dx > 0 then
      local metadata = segments and segments[seg]
      local tension = not metadata or metadata.type == "tension"
      local previous_tension = not segments or seg == 1 or segments[seg - 1].type == "tension"
      -- Legacy Tension neighbors overlap at floor(anchor * resolution).
      -- New types own only samples inside their actual anchor interval.
      local start_i = tension and previous_tension and floor(a.x * (N - 1)) + 1
        or math.ceil(a.x * (N - 1)) + 1
      local end_i = floor(b.x * (N - 1) + 1.0000001)
      local inv_dx = 1 / dx
      for i = math.max(1, start_i), math.min(N, end_i) do
        local t = ((i - 1) * invN - a.x) * inv_dx
        vals[i] = segment_value(a, b, curvs[seg] or 0.5, metadata, t)
      end
    end
  end
end

local function mirror_sample_values(values, N)
  local center = (N + 1) // 2
  for i = 1, center - 1 do
    values[i] = 1 - (values[N + 1 - i] or 0)
  end
end

function curve_editor:interpolate_values()
  local N = sample_count(self)
  self.current_values = {}
  self.base_values = {}
  self.results_values = {}
  interpolate_points(self.points, self.curvatureOffsets, self.current_values, N, self.segments)
  interpolate_points(self.base_points, self.base_curvatureOffsets, self.base_values, N)
  if self.full_range and not self.bipolar then
    mirror_sample_values(self.current_values, N)
    mirror_sample_values(self.base_values, N)
  end
  self:composite()
  if self.full_range and not self.bipolar then
    mirror_sample_values(self.results_values, N)
  end
end

function curve_editor:composite()
  local N = sample_count(self)

  if not self.has_base then
    for i = 1, N do
      self.results_values[i] = self.current_values[i] or 0
    end
    return
  end

  -- Trash 2 layer model: your curve is sampled at the base's height. The
  -- base stops competing on output level and instead warps WHERE along your
  -- curve each x lands. A flat drawn line therefore reads as flat, and an
  -- untouched diagonal makes Results equal the Base exactly.
  for i = 1, N do
    local b = self.base_values[i] or 0
    local f = b * (N - 1) + 1
    local j = floor(f)
    if j < 1 then j = 1 end
    if j > N - 1 then j = N - 1 end
    local frac = f - j
    local a = self.current_values[j] or 0
    local c = self.current_values[j + 1] or a
    self.results_values[i] = a + (c - a) * frac
  end
end

function curve_editor:refresh()
  self:interpolate_values()
  self:output_curve()
  self:output_state()
  self:repaint()
end

function curve_editor:flush_pending()
  if not self._pending then return false end
  self.glmetro_pending = true
  self:tick_update()
  return true
end

function curve_editor:cancel_drag(flush)
  if flush then self:flush_pending() end
  self._pending, self.dragging = nil, nil
  self.drag_start_y, self.drag_start_offset, self.drag_slope_sign = nil, nil, nil
  self.dcclock_pending = true
end

function curve_editor:tick_update()
  if self.glmetro_pending == false then return end
  self.globalmetro:delay(8)
  self.glmetro_pending = false

  local p = self._pending
  if p then
    if p.type == "point" then
      local pt = self.points[p.index]
      if pt then
        pt.x, pt.y = p.x, p.y
        if self.full_range and self.bipolar and pt.center and not same(pt.x, 0.5) then
          pt.fixed, pt.center = false, nil
        end
      end
    elseif p.type == "segment" then
      local segment = self.segments[p.index]
      if segment then
        if segment.type == "tension" then
          self.curvatureOffsets[p.index] = p.offset
        else
          segment[segment.type] = p.offset
        end
      end
    end
    if self.full_range and not self.bipolar then
      self.points, self.curvatureOffsets, self.segments = mirror_positive(self.points, self.curvatureOffsets, self.segments)
    end
    self._pending = nil
  end

  self:refresh()
end

function curve_editor:glmetro()
  self.glmetro_pending = true
  if self._pending then self:tick_update() end
end

function curve_editor:output_curve()
  local list = {}
  for i = 1, sample_count(self) do
    list[i] = self.results_values[i]
  end
  self:outlet(1, "list", list)
end

function curve_editor:output_state()
  local list = { STATE_MAGIC, STATE_VERSION, self.full_range and 1 or 0,
    self.bipolar and 1 or 0, self.width, self.height, #self.points }
  for i, pt in ipairs(self.points) do
    list[#list + 1] = pt.x
    list[#list + 1] = pt.y
    if i < #self.points then
      local segment = self.segments[i]
      list[#list + 1] = self.curvatureOffsets[i]
      list[#list + 1] = TYPE_CODES[segment.type]
      for j = 2, #TYPE_NAMES do list[#list + 1] = segment[TYPE_NAMES[j]] end
    end
  end
  self:outlet(2, "list", list)
end

local function finite_number(value)
  local n = tonumber(value)
  if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
  return n
end

-- Shape payload: x1 y1 b1 x2 y2 b2 ... xN yN (3N-1 atoms). Parsing
-- happens entirely in scratch tables so a bad restore cannot partly replace
-- the curve currently on screen.
local function parse_shape(atoms, first, last, label)
  local count = last - first + 1
  if count < 5 or (count + 1) % 3 ~= 0 then
    pd.post("curve-editor: " .. label .. " rejected: " .. count .. " shape atoms don't fit the x y bend triple format")
    return nil
  end
  local n_points = (count + 1) // 3
  local pts, curvs = {}, {}
  local clamped = 0
  for k = 1, n_points do
    local ai = first + 3 * (k - 1)
    local x = finite_number(atoms[ai])
    local y = finite_number(atoms[ai + 1])
    if not x or not y then
      local bad = (not x) and ai or (ai + 1)
      pd.post("curve-editor: " .. label .. " rejected: atom " .. bad .. " is not a finite number")
      return nil
    end
    local cx, cy = clamp(x, 0, 1), clamp(y, 0, 1)
    if cx ~= x then clamped = clamped + 1 end
    if cy ~= y then clamped = clamped + 1 end
    if #pts > 0 and cx <= pts[#pts].x then
      pd.post("curve-editor: " .. label .. " rejected: point x values must increase")
      return nil
    end
    pts[#pts + 1] = { x = cx, y = cy }
    if k < n_points then
      local b = finite_number(atoms[ai + 2])
      if not b then
        pd.post("curve-editor: " .. label .. " rejected: atom " .. (ai + 2) .. " is not a finite number")
        return nil
      end
      curvs[k] = clamp(b, 0, 1)
      if curvs[k] ~= b then clamped = clamped + 1 end
    end
  end
  if clamped > 0 then
    pd.post("curve-editor: clamped " .. clamped .. " out-of-range values on " .. label)
  end
  pts[1].fixed = true
  pts[#pts].fixed = true
  return pts, curvs
end

local function mark_full_range_points(points, label, require_center, exact_center)
  label = label or "load"
  if #points < (require_center and 3 or 2) or not same(points[1].x, 0) or not same(points[#points].x, 1) then
    pd.post("curve-editor: " .. label .. " rejected: full-range state needs exact x endpoints at 0 and 1")
    return false
  end
  local center = nil
  for i, pt in ipairs(points) do
    if pt.x == 0.5 or (not exact_center and same(pt.x, 0.5)) then center = i break end
  end
  if not center and require_center then
    pd.post("curve-editor: " .. label .. " rejected: full-range state needs a point at x 0.5")
    return false
  end
  if center then
    points[center].x = 0.5
    points[center].fixed, points[center].center = true, true
  end
  return true
end

local function reject(label, reason)
  pd.post("curve-editor: " .. label .. " rejected: " .. reason)
end

local function parse_v3(atoms, label)
  local range, flag = finite_number(atoms[3]), finite_number(atoms[4])
  local width, height = finite_number(atoms[5]), finite_number(atoms[6])
  local count = finite_number(atoms[7])
  if (range ~= 0 and range ~= 1) or (flag ~= 0 and flag ~= 1) or
      not width or not height or width % 1 ~= 0 or height % 1 ~= 0 or
      width < 80 or width > 2000 or height < 80 or height > 2000 or
      (range == 0 and (width ~= 300 or height ~= 300)) then
    reject(label, "invalid v3 range, mode or dimensions")
    return
  end
  if not count or count % 1 ~= 0 or count < 2 or #atoms ~= 9 * count then
    reject(label, "v3 point count does not match the complete payload")
    return
  end
  local pts, bends, segments = {}, {}, {}
  for i = 1, count do
    local offset = 8 + (i - 1) * 9
    local x, y = finite_number(atoms[offset]), finite_number(atoms[offset + 1])
    if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 or
        (i > 1 and x <= pts[i - 1].x) then
      reject(label, "v3 coordinates must be normalized with increasing x")
      return
    end
    pts[i] = { x = x, y = y, fixed = i == 1 or i == count }
    if i < count then
      local raw, code = finite_number(atoms[offset + 2]), finite_number(atoms[offset + 3])
      if not raw or raw < 0 or raw > 1 or not code or not TYPE_NAMES[code + 1] then
        reject(label, "invalid v3 Tension bend or type code")
        return
      end
      bends[i] = raw
      local segment = { type = TYPE_NAMES[code + 1] }
      for j = 2, #TYPE_NAMES do
        local value = finite_number(atoms[offset + 2 + j])
        if not value or value < 0 or value > 1 then
          reject(label, "v3 type controls must be within 0..1")
          return
        end
        segment[TYPE_NAMES[j]] = value
      end
      segments[i] = segment
    end
  end
  if pts[1].x ~= 0 or pts[count].x ~= 1 then
    reject(label, "v3 state needs exact x endpoints at 0 and 1")
    return
  end
  return { points = pts, bends = bends, segments = segments,
    full_range = range == 1, bipolar = flag == 1, width = width, height = height, explicit = true }
end

local function parse_state(atoms, label)
  if not atoms or #atoms == 0 then return end
  local versioned = finite_number(atoms[1]) == STATE_MAGIC
  local state
  if versioned and finite_number(atoms[2]) == STATE_VERSION then
    state = parse_v3(atoms, label)
    if not state then return end
  else
    local full_range, bipolar = false, false
    local first, last, width, height = 1, #atoms, 300, 300
    if versioned then
      if finite_number(atoms[2]) ~= 2 or finite_number(atoms[3]) ~= FULL_RANGE_CODE then
        reject(label, "unsupported state header")
        return
      end
      local flag = finite_number(atoms[4])
      width, height = finite_number(atoms[5]), finite_number(atoms[6])
      if not flag or not width or not height then
        reject(label, "v2 mode and dimensions must be finite")
        return
      end
      full_range, bipolar = true, flag ~= 0
      width, height = clamp(floor(width), 80, 2000), clamp(floor(height), 80, 2000)
      first = 7
    elseif last % 3 == 0 then
      local flag = finite_number(atoms[last])
      if not flag then
        reject(label, "trailing bipolar flag must be finite")
        return
      end
      bipolar, last = flag ~= 0, last - 1
    end
    local pts, bends = parse_shape(atoms, first, last, label)
    if not pts then return end
    if pts[1].x ~= 0 or pts[#pts].x ~= 1 then
      reject(label, "shape needs x endpoints at 0 and 1")
      return
    end
    state = { points = pts, bends = bends, segments = default_segments(pts),
      full_range = full_range, bipolar = bipolar, width = width, height = height }
  end
  if state.full_range and not mark_full_range_points(state.points, label, not state.bipolar, state.explicit) then return end
  return state
end

function curve_editor:load_state(atoms)
  local state = parse_state(atoms, "load")
  if not state then return end
  local pts, bends, segments = state.points, state.bends, state.segments
  if state.full_range and not state.bipolar then
    pts, bends, segments = mirror_positive(pts, bends, segments)
  elseif not state.full_range and self.full_range and not state.explicit then
    pts, bends, segments = legacy_to_full(pts, bends, segments)
    state.full_range, state.bipolar = true, false
    state.width, state.height = self.width, self.height
  end
  self:cancel_drag(false)
  if state.full_range ~= self.full_range then
    local convert = state.full_range and legacy_to_full or full_to_legacy
    self.base_points, self.base_curvatureOffsets = convert(self.base_points, self.base_curvatureOffsets)
  end
  self.full_range, self.bipolar = state.full_range, state.bipolar
  self.width, self.height = state.width, state.height
  self:set_size(self.width, self.height)
  self.points, self.curvatureOffsets, self.segments = pts, bends, segments
  self:refresh()
end

function curve_editor:load_base_state(atoms)
  local state = parse_state(atoms, "base load")
  if not state then return end
  local pts, bends = state.points, state.bends
  if state.full_range and not self.full_range then
    pts, bends = full_to_legacy(pts, bends)
  elseif not state.full_range and self.full_range then
    pts, bends = legacy_to_full(pts, bends)
  end
  self.base_points, self.base_curvatureOffsets = pts, bends
  self.has_base = true
  self:interpolate_values()
  self:output_curve()
  self:repaint()
end

function curve_editor:hit_test_point(nx, ny)
  local best_i, best_d, second_d = nil, 1e9, 1e9
  local R = sqrt(CLICK_RADIUS_SQ)
  for i, pt in ipairs(self.points) do
    if not (self.full_range and not self.bipolar and pt.x < 0.5 - SNAP_EPS) then
      local dx, dy = nx - pt.x, ny - pt.y
      local d = sqrt(dx * dx + dy * dy)
      if d < R then
        if d < best_d then
          second_d = best_d
          best_d, best_i = d, i
        elseif d < second_d then
          second_d = d
        end
      end
    end
  end
  if best_i then
    if second_d < 1e9 and (second_d - best_d) <= (R * AMBIG_FRACTION) then
      return nil
    end
    return { type = "point", index = best_i }
  end
  return nil
end

function curve_editor:hit_test_segment(nx, ny)
  local pts = self.points
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    if not (self.full_range and not self.bipolar and b.x <= 0.5 + SNAP_EPS) then
      if nx >= a.x and nx <= b.x then return { type = "segment", index = i } end
    end
  end
  return nil
end

function curve_editor:mouse_down(x, y)
  self:flush_pending()
  local nx, ny = to_norm(self, x, y)
  nx = clamp(nx, 0, 1)
  ny = clamp(ny, 0, 1)
  if self.full_range and not self.bipolar and (nx < 0.5 or ny < 0.5) then return end
  local hit = self:hit_test_point(nx, ny) or self:hit_test_segment(nx, ny)

  if self.dcclock_pending == false then
    self.dcclock_pending = true
    if hit and hit.type == "point" then
      local k = hit.index
      if not self.points[k].fixed then
        table.remove(self.points, k)
        if k <= #self.curvatureOffsets then
          table.remove(self.curvatureOffsets, k)
          table.remove(self.segments, k)
        end
        if k > 1 and self.curvatureOffsets[k - 1] then
          self.curvatureOffsets[k - 1] = 0.5
          self.segments[k - 1].linear = 0.5
        end
      end
      self.dragging = nil
    else
      if self.snap_enabled then
        local step = 1 / self.gridsub
        nx = snap(nx, step)
        ny = snap(ny, step)
      end
      local clear = true
      for _, pt in ipairs(self.points) do
        if abs(nx - pt.x) < POINT_GAP then
          clear = false
          break
        end
      end
      if clear then
        nx = clamp(nx, self.points[1].x + POINT_GAP, self.points[#self.points].x - POINT_GAP)
        local newi = binsert_points(self.points, { x = nx, y = ny, fixed = false })
        table.insert(self.curvatureOffsets, newi, 0.5)
        table.insert(self.segments, newi, new_segment())
        self.dragging = { type = "point", index = newi, x = nx, y = ny }
      else
        self.dragging = nil
      end
    end
    if self.full_range and not self.bipolar then
      self.points, self.curvatureOffsets, self.segments = mirror_positive(self.points, self.curvatureOffsets, self.segments)
      if self.dragging and self.dragging.x then
        for i, pt in ipairs(self.points) do
          if same(pt.x, self.dragging.x) and same(pt.y, self.dragging.y) then
            self.dragging = { type = "point", index = i }
            break
          end
        end
      end
    end
    self._pending = nil
    self.glmetro_pending = true
    self:tick_update()
    return
  end

  self.dcclock_pending = false
  self.doubleclickclock:delay(DOUBLECLICK_MS)

  self.dragging = hit
  if hit and hit.type == "segment" then
    self.drag_start_y = ny
    local segment = self.segments[hit.index]
    self.drag_start_offset = segment.type == "tension" and self.curvatureOffsets[hit.index] or segment[segment.type]
    local a, b = self.points[hit.index], self.points[hit.index + 1]
    self.drag_slope_sign = ((b.y - a.y) >= 0) and 1 or -1
  end
end

function curve_editor:dcclock()
  self.dcclock_pending = true
end

function curve_editor:mouse_drag(x, y)
  if not self.dragging then return end
  local nx, ny = to_norm(self, x, y)

  if self.dragging.type == "point" then
    local miny = (self.full_range and not self.bipolar) and 0.5 or 0
    ny = clamp(ny, miny, 1)
    if self.snap_enabled then
      local step = 1 / self.gridsub
      nx = snap(nx, step)
      ny = snap(ny, step)
    end
    local i = self.dragging.index
    local pt = self.points[i]
    local free_center = pt.center and self.full_range and self.bipolar
    if pt.fixed and not free_center then
      self._pending = { type = "point", index = i, x = pt.x, y = ny }
    else
      local left, right = self.points[i - 1], self.points[i + 1]
      local minx = left and (left.x + POINT_GAP) or 0
      local maxx = right and (right.x - POINT_GAP) or 1
      local newx = clamp(nx, minx, maxx)
      self._pending = { type = "point", index = i, x = newx, y = ny }
    end
  elseif self.dragging.type == "segment" then
    local idx = self.dragging.index
    if self.drag_start_y and self.drag_start_offset then
      local direction = self.segments[idx].type == "tension" and -self.drag_slope_sign or 1
      local new_off = clamp(self.drag_start_offset + (ny - self.drag_start_y) * SEGMENT_SENSITIVITY * (self.snap_enabled and 0.5 or 1) * direction, 0, 1)
      self._pending = { type = "segment", index = idx, offset = new_off }
    end
  end

  self:tick_update()
end

function curve_editor:mouse_up()
  self:flush_pending()
  self.dragging = nil
  self.drag_start_y = nil
  self.drag_start_offset = nil
  self.drag_slope_sign = nil
  self._pending = nil
  self.glmetro_pending = true
  self:tick_update()
end

function curve_editor:in_1_bang()
  if not self:flush_pending() then
    self:output_curve()
    self:output_state()
  end
end

function curve_editor:in_1_snap(atoms)
  self.snap_enabled = (tonumber(atoms[1]) or 0) ~= 0
end

function curve_editor:in_1_grid(atoms)
  self.grid_enabled = (tonumber(atoms[1]) or 0) ~= 0
  self:repaint()
end

function curve_editor:in_1_type(atoms)
  if atoms[3] ~= nil then
    pd.post("curve-editor: type rejected: expected segment index and type name")
    return
  end
  local index = finite_number(atoms[1])
  if not index or index % 1 ~= 0 or index < 1 or index > #self.segments then
    pd.post("curve-editor: type rejected: segment index out of range")
    return
  end
  if self.full_range and not self.bipolar and self.points[index + 1].x <= 0.5 then
    pd.post("curve-editor: type rejected: cannot edit ghost segment")
    return
  end
  local name = atoms[2]
  if not name or not TYPE_CODES[name] then
    pd.post("curve-editor: type rejected: unknown segment type")
    return
  end
  self:cancel_drag(true)
  self.segments[index].type = name
  if self.full_range and not self.bipolar then
    self.points, self.curvatureOffsets, self.segments = mirror_positive(self.points, self.curvatureOffsets, self.segments)
  end
  self:refresh()
end

function curve_editor:in_1_bend(atoms)
  if atoms[3] ~= nil then
    pd.post("curve-editor: bend rejected: expected segment index and value")
    return
  end
  local index = finite_number(atoms[1])
  if not index or index % 1 ~= 0 or index < 1 or index > #self.segments then
    pd.post("curve-editor: bend rejected: segment index out of range")
    return
  end
  if self.full_range and not self.bipolar and self.points[index + 1].x <= 0.5 then
    pd.post("curve-editor: bend rejected: cannot edit ghost segment")
    return
  end
  local value = finite_number(atoms[2])
  if not value or value < 0 or value > 1 then
    pd.post("curve-editor: bend rejected: value must be 0..1")
    return
  end
  self:cancel_drag(true)
  local segment = self.segments[index]
  if segment.type == "tension" then
    local a, b = self.points[index], self.points[index + 1]
    self.curvatureOffsets[index] = b.y >= a.y and 1 - value or value
  else
    segment[segment.type] = value
  end
  if self.full_range and not self.bipolar then
    self.points, self.curvatureOffsets, self.segments = mirror_positive(self.points, self.curvatureOffsets, self.segments)
  end
  self:refresh()
end

function curve_editor:in_1_bipolar(atoms)
  local enabled = (finite_number(atoms[1]) or 0) ~= 0
  self:cancel_drag(true)
  if self.full_range and not enabled then
    self.points, self.curvatureOffsets, self.segments = mirror_positive(self.points, self.curvatureOffsets, self.segments)
  end
  self.bipolar = enabled
  if self.full_range then
    self:interpolate_values()
    self:output_curve()
  end
  self:output_state()
  self:repaint()
end

function curve_editor:in_1_fullrange(atoms)
  local enabled = (finite_number(atoms[1]) or 0) ~= 0
  if enabled == self.full_range then return end
  self:cancel_drag(true)

  if enabled then
    self.points, self.curvatureOffsets, self.segments = legacy_to_full(self.points, self.curvatureOffsets, self.segments)
    self.base_points, self.base_curvatureOffsets = legacy_to_full(self.base_points, self.base_curvatureOffsets)
    self.full_range = true
    self.bipolar = false
  else
    self.points, self.curvatureOffsets, self.segments = full_to_legacy(self.points, self.curvatureOffsets, self.segments)
    self.base_points, self.base_curvatureOffsets = full_to_legacy(self.base_points, self.base_curvatureOffsets)
    self.full_range = false
    self.bipolar = false
    self.width, self.height = 300, 300
    self:set_size(self.width, self.height)
  end
  self:interpolate_values()
  self:output_curve()
  self:output_state()
  self:repaint()
end

function curve_editor:in_1_size(atoms)
  if not self.full_range then
    pd.post("curve-editor: size ignored: enable fullrange first")
    return
  end
  self:cancel_drag(true)
  local width = floor(finite_number(atoms[1]) or self.width)
  local height = floor(finite_number(atoms[2]) or width)
  self.width = clamp(width, 80, 2000)
  self.height = clamp(height, 80, 2000)
  self:set_size(self.width, self.height)
  self:output_state()
  self:repaint()
end

function curve_editor:in_1_base(atoms)
  if atoms[1] == "clear" then
    local pts = {
      { x = 0, y = 0, fixed = true },
      { x = 1, y = 1, fixed = true },
    }
    local curvs = { 0.5 }
    if self.full_range then pts, curvs = legacy_to_full(pts, curvs) end
    self.base_points, self.base_curvatureOffsets = pts, curvs
    self.has_base = false
    self:interpolate_values()
    self:output_curve()
    self:repaint()
    return
  end
  self:load_base_state(atoms)
end

function curve_editor:in_1_gridsub(atoms)
  local n = floor(tonumber(atoms[1]) or GRID_SUB_DEFAULT)
  self.gridsub = clamp(n, 1, 50)
  self:repaint()
end

function curve_editor:in_1_gridup()
  self.gridsub = clamp(self.gridsub + 1, 1, 50)
  self:repaint()
end

function curve_editor:in_1_griddown()
  self.gridsub = clamp(self.gridsub - 1, 1, 50)
  self:repaint()
end

function curve_editor:in_1_list(atoms)
  self:load_state(atoms)
end

-- ---- colors: edit these per plugin ----------------------------------------
-- The paint values to adjust when adding this curve editor into your patch.
-- You can adjust the colors here to match your patch's color palette.
local COLORS = {
  grid      = { 215, 218, 224, 0.6 },
  crosshair = { 215, 218, 224 },
  curve     = { 171, 177, 188 },
  ghost     = { 171, 177, 188, 0.42 },
  point     = { 214, 217, 222 },
  results   = { 180, 160, 200, 0.7 },
}

local function use_color(g, c, alpha)
  g:set_color(c[1], c[2], c[3], alpha or c[4] or 1)
end

local function stroke_values(g, values, first, last, N, dw, dh, color, thickness, last_value)
  local inv = 1 / (N - 1)
  local p = Path(INSET + (first - 1) * inv * dw, INSET + (1 - (values[first] or 0)) * dh)
  for i = first + 1, last do
    local value = (i == last and last_value ~= nil) and last_value or (values[i] or 0)
    p:line_to(INSET + (i - 1) * inv * dw, INSET + (1 - value) * dh)
  end
  use_color(g, color)
  g:stroke_path(p, thickness)
end

local function segment_path(a, b, raw, segment, dw, dh, reflected)
  local path
  local function add(t, y)
    local x = a.x + (b.x - a.x) * t
    if reflected then x, y = 1 - x, 1 - y end
    x, y = INSET + x * dw, INSET + (1 - y) * dh
    if path then path:line_to(x, y) else path = Path(x, y) end
  end
  local kind = segment.type
  add(0, a.y)
  if kind == "square" or kind == "stairs" then
    local count = segment_count(segment)
    local lower = kind == "stairs" and segment.stairs < 0.5
    local bins = kind == "square" and 2 * count or (lower and count - 1 or count + 1)
    for j = 0, bins - 1 do
      local level
      if kind == "square" then
        level = (j + (segment.square >= 0.5 and 1 or 0)) % 2
      else
        level = lower and (j + 0.5) / bins or j / count
      end
      local y = a.y + (b.y - a.y) * level
      add(j / bins, y)
      add((j + 1) / bins, y)
    end
  else
    local steps = kind == "linear" and 2 or
      kind == "triangle" and segment_count(segment) or
      kind == "sine" and segment_count(segment) * 16 or
      math.max(32, math.ceil((b.x - a.x) * dw))
    for j = 1, steps - 1 do
      local t = j / steps
      add(t, segment_value(a, b, raw, segment, t))
    end
  end
  add(1, b.y)
  return path
end

function curve_editor:paint(g)
  local width, height = self:get_size()
  local dw = width - 2 * INSET
  local dh = height - 2 * INSET

  if self.grid_enabled then
    local divs = self.gridsub
    use_color(g, COLORS.grid)
    for i = 0, divs do
      local t = i / divs
      local vline = Path(INSET + t * dw, INSET)
      vline:line_to(INSET + t * dw, INSET + dh)
      g:stroke_path(vline, 1)
      local hline = Path(INSET, INSET + t * dh)
      hline:line_to(INSET + dw, INSET + t * dh)
      g:stroke_path(hline, 1)
    end
    if self.full_range or self.bipolar then
      use_color(g, COLORS.crosshair)
      local vline = Path(INSET + dw / 2, INSET)
      vline:line_to(INSET + dw / 2, INSET + dh)
      g:stroke_path(vline, 2)
      local hline = Path(INSET, INSET + dh / 2)
      hline:line_to(INSET + dw, INSET + dh / 2)
      g:stroke_path(hline, 2)
    end
  end

  local N = sample_count(self)

  local rvals = self.results_values
  if self.has_base then
    stroke_values(g, rvals, 1, N, N, dw, dh, COLORS.results, 3)
  end

  for i, segment in ipairs(self.segments) do
    local a, b = self.points[i], self.points[i + 1]
    if not (self.full_range and not self.bipolar and b.x <= 0.5) then
      local thickness = 4
      if segment.type ~= "tension" and segment.type ~= "linear" then
        local count = segment_count(segment)
        local features = segment.type == "square" and 2 * count or
          segment.type == "stairs" and count + 1 or count
        thickness = clamp((b.x - a.x) * dw / features * 0.45, 1, 4)
      end
      if self.full_range and not self.bipolar then
        use_color(g, COLORS.ghost)
        g:stroke_path(segment_path(a, b, self.curvatureOffsets[i], segment, dw, dh, true), math.min(2, thickness))
      end
      use_color(g, COLORS.curve)
      g:stroke_path(segment_path(a, b, self.curvatureOffsets[i], segment, dw, dh), thickness)
    end
  end

  use_color(g, COLORS.point)
  for _, pt in ipairs(self.points) do
    if not (self.full_range and not self.bipolar and pt.x < 0.5 - SNAP_EPS) then
      local x = INSET + pt.x * dw
      local y = INSET + (1 - pt.y) * dh
      g:fill_ellipse(x - 7.5, y - 7.5, 15, 15)
    end
  end
end
