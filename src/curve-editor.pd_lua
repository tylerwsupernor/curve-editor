local curve_editor = pd.Class:new():register("curve-editor")

local INSET = 12
local LEGACY_SAMPLES = 257
local FULL_RANGE_SAMPLES = 513
local STATE_MAGIC = -271828
local STATE_VERSION = 2
local FULL_RANGE_CODE = 1
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

local function positive_half(points, curvs)
  local pts, bends = {}, {}
  local first = nil
  for i, pt in ipairs(points) do
    if pt.x >= 0.5 - SNAP_EPS then
      if not first then first = i end
      pts[#pts + 1] = {
        x = pt.x,
        y = pt.y,
        fixed = pt.fixed,
        center = same(pt.x, 0.5),
      }
    end
  end
  if first then
    for i = first, #points - 1 do bends[#bends + 1] = curvs[i] or 0.5 end
  end
  return pts, bends
end

local function mirror_positive(points, curvs)
  local pos, pos_curvs = positive_half(points, curvs)
  if #pos == 0 or not same(pos[1].x, 0.5) then
    table.insert(pos, 1, { x = 0.5, y = 0.5, fixed = true, center = true })
    table.insert(pos_curvs, 1, 0.5)
  else
    pos[1].x = 0.5
    pos[1].y = clamp(pos[1].y, 0.5, 1)
    pos[1].fixed, pos[1].center = true, true
  end
  for i = 2, #pos do pos[i].y = clamp(pos[i].y, 0.5, 1) end

  local pts, bends = {}, {}
  for i = #pos, 2, -1 do
    local pt = pos[i]
    pts[#pts + 1] = {
      x = 1 - pt.x,
      y = 1 - pt.y,
      fixed = i == #pos,
    }
    bends[#bends + 1] = 1 - (pos_curvs[i - 1] or 0.5)
  end
  for _, pt in ipairs(pos) do pts[#pts + 1] = pt end
  for _, bend in ipairs(pos_curvs) do bends[#bends + 1] = bend end
  pts[1].fixed = true
  pts[#pts].fixed = true
  return pts, bends
end

local function legacy_to_full(points, curvs)
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
  return mirror_positive(pos, bends)
end

local function full_to_legacy(points, curvs)
  local pos, pos_curvs = positive_half(points, curvs)
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
  return pts, pos_curvs
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
    self.points, self.curvatureOffsets = legacy_to_full(self.points, self.curvatureOffsets)
    self.base_points, self.base_curvatureOffsets = legacy_to_full(self.base_points, self.base_curvatureOffsets)
    self.full_range = true
  end
  self:interpolate_values()
  return true
end

local function interpolate_points(pts, curvs, vals, N)
  local invN = 1 / (N - 1)

  if #pts < 2 then
    for i = 1, N do vals[i] = 0 end
    return
  end

  for seg = 1, #pts - 1 do
    local a, b = pts[seg], pts[seg + 1]
    local dx = b.x - a.x
    if dx > 1e-9 then
      local start_i = floor(a.x * (N - 1)) + 1
      local end_i = floor(b.x * (N - 1) + 1.0000001)
      if start_i < 1 then start_i = 1 end
      if end_i > N then end_i = N end

      local inv_dx = 1 / dx
      local ay, by = a.y, b.y
      local midpoint = 0.5 * (ay + by)

      local raw = curvs[seg] or 0.5
      local d = raw - 0.5
      local sign = (d >= 0) and 1 or -1
      local m = abs(d) * 2
      local power = 1 + skew_m(m) * (CURVE_POWER_MAX - 1)

      for i = start_i, end_i do
        local x = (i - 1) * invN
        local t = (x - a.x) * inv_dx
        if t < 0 then t = 0 elseif t > 1 then t = 1 end

        local tn
        if sign >= 0 then
          tn = t ^ power
        else
          tn = 1 - (1 - t) ^ power
        end

        local omt = 1 - tn
        vals[i] = omt * omt * ay + 2 * omt * tn * midpoint + tn * tn * by
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
  interpolate_points(self.points, self.curvatureOffsets, self.current_values, N)
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
      if self.curvatureOffsets[p.index] ~= nil then
        self.curvatureOffsets[p.index] = p.offset
      end
    end
    if self.full_range and not self.bipolar then
      self.points, self.curvatureOffsets = mirror_positive(self.points, self.curvatureOffsets)
    end
    self._pending = nil
  end

  self:interpolate_values()
  self:output_curve()
  self:output_state()
  self:repaint()
end

function curve_editor:glmetro()
  self.glmetro_pending = true
end

function curve_editor:output_curve()
  local list = {}
  for i = 1, sample_count(self) do
    list[i] = self.results_values[i]
  end
  self:outlet(1, "list", list)
end

function curve_editor:output_state()
  local list = {}
  local n = 0
  -- Full-range header: magic, state version, range code, bipolar mode,
  -- width, height. The remaining atoms are the ordinary shape payload.
  if self.full_range then
    n = 1; list[n] = STATE_MAGIC
    n = n + 1; list[n] = STATE_VERSION
    n = n + 1; list[n] = FULL_RANGE_CODE
    n = n + 1; list[n] = self.bipolar and 1 or 0
    n = n + 1; list[n] = self.width
    n = n + 1; list[n] = self.height
  end
  for i, pt in ipairs(self.points) do
    n = n + 1; list[n] = pt.x
    n = n + 1; list[n] = pt.y
    if i < #self.points then
      n = n + 1; list[n] = self.curvatureOffsets[i] or 0.5
    end
  end
  if not self.full_range then
    n = n + 1; list[n] = self.bipolar and 1 or 0
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
  if count < 2 or (count + 1) % 3 ~= 0 then
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

local function mark_full_range_points(points, label, require_center)
  label = label or "load"
  if #points < 3 or not same(points[1].x, 0) or not same(points[#points].x, 1) then
    pd.post("curve-editor: " .. label .. " rejected: full-range state needs exact x endpoints at 0 and 1")
    return false
  end
  local center = nil
  for i, pt in ipairs(points) do
    if same(pt.x, 0.5) then center = i break end
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

function curve_editor:load_state(atoms)
  if not atoms or #atoms == 0 then return end

  local full_range = finite_number(atoms[1]) == STATE_MAGIC
  local bipolar = false
  local width, height = self.width, self.height
  local first, last = 1, #atoms
  if full_range then
    if finite_number(atoms[2]) ~= STATE_VERSION or finite_number(atoms[3]) ~= FULL_RANGE_CODE then
      pd.post("curve-editor: load rejected: unsupported full-range state header")
      return
    end
    local flag = finite_number(atoms[4])
    if not flag then
      pd.post("curve-editor: load rejected: atom 4 is not a finite number (bipolar flag)")
      return
    end
    bipolar = flag ~= 0
    width = finite_number(atoms[5])
    height = finite_number(atoms[6])
    if not width or not height then
      pd.post("curve-editor: load rejected: full-range size is not finite")
      return
    end
    width = clamp(floor(width), 80, 2000)
    height = clamp(floor(height), 80, 2000)
    first = 7
  else
    if last % 3 == 0 then
      local flag = finite_number(atoms[last])
      if not flag then
        pd.post("curve-editor: load rejected: atom " .. last .. " is not a finite number (bipolar flag)")
        return
      end
      bipolar = flag ~= 0
      last = last - 1
    end
  end

  local pts, curvs = parse_shape(atoms, first, last, "load")
  if not pts then return end
  if full_range then
    if not mark_full_range_points(pts, "load", not bipolar) then return end
    if not bipolar then pts, curvs = mirror_positive(pts, curvs) end
  elseif self.full_range then
    pts, curvs = legacy_to_full(pts, curvs)
    full_range = true
    -- The old trailing flag only controlled a crosshair. It must not turn a
    -- legacy positive-only save into independently editable bipolar data.
    bipolar = false
  end

  self.full_range = full_range
  self.bipolar = bipolar
  self.width, self.height = width, height
  self:set_size(width, height)
  self.points, self.curvatureOffsets = pts, curvs
  self:interpolate_values()
  self:output_curve()
  self:output_state()
  self:repaint()
end

function curve_editor:load_base_state(atoms)
  if not atoms or #atoms == 0 then return end
  local full_range = finite_number(atoms[1]) == STATE_MAGIC
  local base_bipolar = false
  local first, last = 1, #atoms
  if full_range then
    if finite_number(atoms[2]) ~= STATE_VERSION or finite_number(atoms[3]) ~= FULL_RANGE_CODE or
        not finite_number(atoms[4]) or not finite_number(atoms[5]) or not finite_number(atoms[6]) then
      pd.post("curve-editor: base load rejected: unsupported full-range state header")
      return
    end
    base_bipolar = finite_number(atoms[4]) ~= 0
    first = 7
  elseif last % 3 == 0 then
    if not finite_number(atoms[last]) then
      pd.post("curve-editor: base load rejected: trailing bipolar flag is not a finite number")
      return
    end
    last = last - 1
  end
  local pts, curvs = parse_shape(atoms, first, last, "base load")
  if not pts then return end
  if full_range then
    if not mark_full_range_points(pts, "base load", not base_bipolar) then return end
    if not self.full_range then pts, curvs = full_to_legacy(pts, curvs) end
  elseif self.full_range then
    pts, curvs = legacy_to_full(pts, curvs)
  end
  self.base_points, self.base_curvatureOffsets = pts, curvs
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
        end
        if k > 1 and self.curvatureOffsets[k - 1] then
          self.curvatureOffsets[k - 1] = 0.5
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
        self.dragging = { type = "point", index = newi, x = nx, y = ny }
      else
        self.dragging = nil
      end
    end
    if self.full_range and not self.bipolar then
      self.points, self.curvatureOffsets = mirror_positive(self.points, self.curvatureOffsets)
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
    self.drag_start_offset = self.curvatureOffsets[hit.index] or 0.5
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
      if not same(ny, pt.y) then
        self._pending = { type = "point", index = i, x = pt.x, y = ny }
      end
    else
      local left, right = self.points[i - 1], self.points[i + 1]
      local minx = left and (left.x + POINT_GAP) or 0
      local maxx = right and (right.x - POINT_GAP) or 1
      local newx = clamp(nx, minx, maxx)
      if not (same(newx, pt.x) and same(ny, pt.y)) then
        self._pending = { type = "point", index = i, x = newx, y = ny }
      end
    end
  elseif self.dragging.type == "segment" then
    local idx = self.dragging.index
    if self.drag_start_y and self.drag_start_offset then
      local sgn = self.drag_slope_sign or 1
      local new_off = clamp(self.drag_start_offset - (ny - self.drag_start_y) * (SEGMENT_SENSITIVITY * (self.snap_enabled and 0.5 or 1.0)) * sgn, 0, 1)
      if not same(new_off, self.curvatureOffsets[idx]) then
        self._pending = { type = "segment", index = idx, offset = new_off }
      end
    end
  end

  self:tick_update()
end

function curve_editor:mouse_up()
  self.dragging = nil
  self.drag_start_y = nil
  self.drag_start_offset = nil
  self.drag_slope_sign = nil
  self._pending = nil
  self.glmetro_pending = true
  self:tick_update()
end

function curve_editor:in_1_bang()
  self:output_curve()
end

function curve_editor:in_1_snap(atoms)
  self.snap_enabled = (tonumber(atoms[1]) or 0) ~= 0
end

function curve_editor:in_1_grid(atoms)
  self.grid_enabled = (tonumber(atoms[1]) or 0) ~= 0
  self:repaint()
end

function curve_editor:in_1_bipolar(atoms)
  local enabled = (finite_number(atoms[1]) or 0) ~= 0
  if self.full_range and not enabled then
    self.points, self.curvatureOffsets = mirror_positive(self.points, self.curvatureOffsets)
  end
  self.bipolar = enabled
  if self.full_range then
    self:interpolate_values()
    self:output_curve()
    self:output_state()
  end
  self:repaint()
end

function curve_editor:in_1_fullrange(atoms)
  local enabled = (finite_number(atoms[1]) or 0) ~= 0
  if enabled == self.full_range then return end

  if enabled then
    self.points, self.curvatureOffsets = legacy_to_full(self.points, self.curvatureOffsets)
    self.base_points, self.base_curvatureOffsets = legacy_to_full(self.base_points, self.base_curvatureOffsets)
    self.full_range = true
    self.bipolar = false
  else
    self.points, self.curvatureOffsets = full_to_legacy(self.points, self.curvatureOffsets)
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
-- The only paint values a waveshaper-br0 recopy needs to touch. Match every
-- color to the host patch palette (Almost White 254,254,254 on navy).
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
  if self.has_base or not self.full_range then
    stroke_values(g, rvals, 1, N, N, dw, dh, COLORS.results, 3)
  end

  local vals = self.current_values
  if self.full_range and not self.bipolar then
    local center = (N + 1) // 2
    stroke_values(g, vals, 1, center, N, dw, dh, COLORS.ghost, 2, 1 - (vals[center] or 0.5))
    stroke_values(g, vals, center, N, N, dw, dh, COLORS.curve, 4)
  else
    stroke_values(g, vals, 1, N, N, dw, dh, COLORS.curve, 4)
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
