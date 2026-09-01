local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
]]


-- General functions and implementation
-- ====================================


--- Convenience wrapper for debug output using string.format().
--
-- @param string Formating string for string.format.
-- @param any* Formating string parameters.
--
local function _debug(...)
    DebugError(string.format(...))
end


local m = {}


--- Initialises the mod.
--
function m.init()
end


m.init()
