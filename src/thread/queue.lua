
local table = table
local alien = require "alien"

module("thread.queue", package.seeall)

local methods= {}

function new(start_size)
   start_size = start_size or 2
   local buf = alien.table(start_size, 0)
   local q = { buf = buf, first = 1, last = 1, size = start_size, n = 0 }
   setmetatable(q, { __index = methods })
   return q
end

local function resize(queue, new_size)
   local new_t = alien.table(new_size, 0)
   local last = queue.last
   local old_t = queue.buf
   local size = queue.size
   local n = queue.n
   for i = n, 1, -1 do
      new_t[i] = old_t[last - 1]
      last = last - 1
      if last == 1 then last = size + 1 end
   end
   queue.buf = new_t
   queue.last = n + 1
   queue.first = 1
   queue.size = new_size
end

function methods.insert(queue, obj)
   local n, size = queue.n, queue.size
   if n == size then
      resize(queue, size * 2)
   end
   local n, size, last = queue.n, queue.size, queue.last
   queue.buf[last] = obj
   last = last + 1
   if last > size then last = 1 end
   queue.n, queue.last = n + 1, last
end

function methods.remove(queue)
   local n = queue.n
   if n == 0 then return nil end
   local first, size = queue.first, queue.size
   local obj = queue.buf[first]
   queue.buf[first] = nil
   first = first + 1
   if first > size then first = 1 end
   queue.first, queue.n = first, n - 1
   if n < (size / 2) then resize(queue, size / 2) end
   return obj 
end
