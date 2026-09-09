local registered

pd = { Class = {}, Clock = {} }
Path = function(x, y)
  return {
    points = { { x = x, y = y } },
    line_to = function(self, px, py)
      self.points[#self.points + 1] = { x = px, y = py }
    end,
  }
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
  self._output_count = (self._output_count or 0) + 1
  self._out = self._out or {}
  self._out[n] = { selector = selector, atoms = atoms }
end
function pd.Class:repaint() end
function pd.Clock:new() return setmetatable({}, { __index = self }) end
function pd.Clock:register() return self end
function pd.Clock:delay() end
function pd.post(message) pd.last_post = message end

assert(loadfile(arg and arg.editor_source or "src/curve-editor.pd_lua"))()

local function new_editor(atoms)
  local obj = setmetatable({}, { __index = registered })
  assert(obj:initialize(nil, atoms))
  return obj
end

return new_editor
