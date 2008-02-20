
local thread = require "thread"
local table = table

module("thread.channel", package.seeall)

local methods = {}

function new()
   local channel = { cv = thread.cv(), msgbox = {} }
   setmetatable(channel, { __index = methods })
   return channel
end

function methods:send(msg)
   if msg then
      table.insert(self.msgbox, 1, msg)
      thread.signal(self.cv)
   else
      error("trying to send a nil message")
   end
end

function methods:receive()
   repeat
      local msg = table.remove(self.msgbox)
      if msg then return msg end
      thread.yield(self.cv)
   until false
end

function methods:peek()
   if #self.msgbox > 0 then
      return table.remove(self.msgbox)
   end
end
