
local loaded = package.loaded
local _G = _G

module("thread.slave", package.seeall)

loaded["thread"] = _M
_G["thread"] = _M

function yield(ev, obj)
   if current_thread = "main" then
      coroutine.yield("yield", ev, obj)
end

function new(thr, err, ...)
end
