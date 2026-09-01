local curve_editor = pd.Class:new():register("curve-editor")

local INSET = 12
local NUM_SAMPLES = 256
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

local function skew_m(m)
  if m <= 0 then return 0 end
  if m >= 1 then return 1 end
  return (exp(SKEW_K * m) - 1) / (exp(SKEW_K) - 1)
end

function curve_editor:initialize()
  self.inlets = 1
  self.outlets = 2
  self.width, self.height = 300, 300
  self:set_size(self.width, self.height)
  self.points = {
    { x = 0, y = 0, fixed = true },
    { x = 1, y = 1, fixed = true },
  }
  self.curvatureOffsets = { 0.5 }
  self.current_values = {}
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
  self.bipolar = false
  self:interpolate_values()
  return true
end

function curve_editor:interpolate_values()
  local pts = self.points
  local curvs = self.curvatureOffsets
  local vals = self.current_values
  local N = NUM_SAMPLES
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

function curve_editor:tick_update()
  if self.glmetro_pending == false then return end
  self.globalmetro:delay(8)
  self.glmetro_pending = false

  local p = self._pending
  if p then
    if p.type == "point" then
      local pt = self.points[p.index]
      if pt then pt.x, pt.y = p.x, p.y end
    elseif p.type == "segment" then
      if self.curvatureOffsets[p.index] ~= nil then
        self.curvatureOffsets[p.index] = p.offset
      end
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
  for i = 1, NUM_SAMPLES do
    list[i] = self.current_values[i]
  end
  list[NUM_SAMPLES + 1] = list[NUM_SAMPLES]
  self:outlet(1, "list", list)
end

function curve_editor:output_state()
  local list = {}
  local n = 0
  for i, pt in ipairs(self.points) do
    n = n + 1; list[n] = pt.x
    n = n + 1; list[n] = pt.y
    if i < #self.points then
      n = n + 1; list[n] = self.curvatureOffsets[i] or 0.5
    end
  end
  n = n + 1; list[n] = self.bipolar and 1 or 0
  self:outlet(2, "list", list)
end

-- State format: x1 y1 b1 x2 y2 b2 ... xN yN, so N points means 3N-1 atoms.
-- Newer saves carry one extra trailing atom, the bipolar display flag, so a
-- list of 3N atoms is shape plus flag and a list of 3N-1 is an older save
-- with the flag off. A loader that silently truncates or misreads a save is
-- a trap, so every load is sanitized: the atom count must fit one of the two
-- formats, every atom must be a number, x and y are clamped into 0-1, and
-- parsing fills scratch tables so a rejected load leaves the current curve
-- standing.
function curve_editor:load_state(atoms)
  if not atoms or #atoms == 0 then return end
  local n = #atoms
  local bipolar = false
  if n % 3 == 0 then
    local flag = tonumber(atoms[n])
    if not flag then
      pd.post("curve-editor: load rejected: atom " .. n .. " is not a number (bipolar flag)")
      return
    end
    bipolar = flag ~= 0
    n = n - 1
  end
  if (n + 1) % 3 ~= 0 then
    pd.post("curve-editor: load rejected: " .. #atoms .. " atoms don't fit the x y bend triple format")
    return
  end
  local n_points = (n + 1) // 3
  local pts, curvs = {}, {}
  local clamped = 0
  for k = 1, n_points do
    local ai = 3 * k - 2
    local x = tonumber(atoms[ai])
    local y = tonumber(atoms[ai + 1])
    if not x or not y then
      local bad = (not x) and ai or (ai + 1)
      pd.post("curve-editor: load rejected: atom " .. bad .. " is not a number")
      return
    end
    local cx, cy = clamp(x, 0, 1), clamp(y, 0, 1)
    if cx ~= x then clamped = clamped + 1 end
    if cy ~= y then clamped = clamped + 1 end
    binsert_points(pts, { x = cx, y = cy })
    if k < n_points then
      local b = tonumber(atoms[ai + 2])
      if not b then
        pd.post("curve-editor: load rejected: atom " .. (ai + 2) .. " is not a number")
        return
      end
      curvs[k] = b
    end
  end
  if clamped > 0 then
    pd.post("curve-editor: clamped " .. clamped .. " out-of-range values on load")
  end
  pts[1].fixed = true
  pts[#pts].fixed = true
  self.bipolar = bipolar
  self.points, self.curvatureOffsets = pts, curvs
  self:interpolate_values()
  self:output_curve()
  self:output_state()
  self:repaint()
end

function curve_editor:hit_test_point(nx, ny)
  local best_i, best_d, second_d = nil, 1e9, 1e9
  local R = sqrt(CLICK_RADIUS_SQ)
  for i, pt in ipairs(self.points) do
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
    if nx >= a.x and nx <= b.x then return { type = "segment", index = i } end
  end
  return nil
end

function curve_editor:mouse_down(x, y)
  local nx, ny = to_norm(self, x, y)
  nx = clamp(nx, 0, 1)
  ny = clamp(ny, 0, 1)
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
        self.dragging = { type = "point", index = newi }
      else
        self.dragging = nil
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
    ny = clamp(ny, 0, 1)
    if self.snap_enabled then
      local step = 1 / self.gridsub
      nx = snap(nx, step)
      ny = snap(ny, step)
    end
    local i = self.dragging.index
    local pt = self.points[i]
    if pt.fixed then
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
  self.bipolar = (tonumber(atoms[1]) or 0) ~= 0
  self:repaint()
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
  point     = { 214, 217, 222 },
}

local function use_color(g, c, alpha)
  g:set_color(c[1], c[2], c[3], alpha or c[4] or 1)
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
    if self.bipolar then
      use_color(g, COLORS.crosshair)
      local vline = Path(INSET + dw / 2, INSET)
      vline:line_to(INSET + dw / 2, INSET + dh)
      g:stroke_path(vline, 2)
      local hline = Path(INSET, INSET + dh / 2)
      hline:line_to(INSET + dw, INSET + dh / 2)
      g:stroke_path(hline, 2)
    end
  end

  local vals = self.current_values
  local N = NUM_SAMPLES
  local inv = 1 / (N - 1)

  local p = Path(INSET, INSET + (1 - (vals[1] or 0)) * dh)
  for i = 2, N do
    p:line_to(INSET + (i - 1) * inv * dw, INSET + (1 - (vals[i] or 0)) * dh)
  end
  use_color(g, COLORS.curve)
  g:stroke_path(p, 4)

  use_color(g, COLORS.point)
  for _, pt in ipairs(self.points) do
    local x = INSET + pt.x * dw
    local y = INSET + (1 - pt.y) * dh
    g:fill_ellipse(x - 7.5, y - 7.5, 15, 15)
  end
end
