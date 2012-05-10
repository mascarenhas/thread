
require "alien"

local struct = require "alien.struct"
local table = table

module("thread", package.seeall)

local libevent = alien.event

libevent.event_init:types("pointer")
libevent.event_set:types("void", "pointer", "int", "int", "callback", "string")
libevent.event_add:types("int", "pointer", "pointer")
libevent.event_dispatch:types("int")
libevent.event_once:types("int", "int", "int", "callback", "pointer", "string")
libevent.event_loop:types("int", "int")

libevent.event_init()

require("event_constants")

local events = {
  read = EV_READ,
  write = EV_WRITE,
}

local waiting_threads = {
  [EV_READ] = {},
  [EV_WRITE] = {},
  idle = {}
}

local event_cache = {}

local events_in_use = {}

local function get_event(thread_id)
  local ev = table.remove(event_cache)
  if not ev then
    ev = alien.buffer(EV_SIZE)
  end
  events_in_use[thread_id] = ev
  return ev
end

local function dispose_event(thread_id)
  local ev = events_in_use[thread_id]
  if ev then
    events_in_use[thread_id] = nil
    table.insert(event_cache, ev)
  end
end

local timer_threads = {}

local next_thread = {}

local function handle_event(fd, ev_code, thread_id)
  if ev_code == EV_TIMEOUT then
    table.insert(next_thread, 1, timer_threads[thread_id])
    timer_threads[thread_id] = nil
  else
    if thread_id then
      dispose_event(thread_id)
      timer_threads[thread_id] = nil
    end
    local queue = waiting_threads[ev_code][fd]
    if queue then
      table.insert(next_thread, 1, queue[#queue])
      queue[#queue] = nil
    else
      error("no thread waiting for event " .. ev_code .. " on fd " .. fd)
    end
  end
  return 0
end

local handle_event_cb = alien.callback(handle_event, "void", "int", "int",
				       "string")

local function queue_event(thr, ev_code, fd)
  local queue
  if fd then
    queue = waiting_threads[ev_code][fd]
  else
    queue = waiting_threads[ev_code]
  end
  if not queue then 
    queue = {}
    waiting_threads[ev_code][fd] = queue
  end
  table.insert(queue, 1, thr)
end

local function queue_timer(thr)
  local thread_id = tostring(thr)
  timer_threads[thread_id] = thr
  return thread_id
end

function yield(...)
   if coroutine.running() then
      coroutine.yield(...)
   else
      handle_yield("main", ...)
      return event_loop()
   end
end

function handle_yield(thr, ev, fd, timeout)
  if type(ev) == "number" then
    ev, fd = "timer", ev
  end
  if ev == "read" or ev == "write" then
    local ev_code = events[ev]
    local time
    if timeout then
      time = struct.pack("ll", math.floor(timeout / 1000),
			 (timeout % 1000) * 1000)
      queue_timer(thr)
    end
    local thread_id = tostring(thr)
    local evobj = get_event(thread_id)
    libevent.event_set(evobj, fd, ev_code, handle_event_cb, thread_id)
    libevent.event_add(evobj, time)
    queue_event(thr, ev_code, fd)
  elseif ev == "timer" then
    fd, timeout = -1, fd
    local time = struct.pack("ll", math.floor(timeout / 1000),
			     (timeout % 1000) * 1000)
    local thread_id = queue_timer(thr)
    libevent.event_once(fd, EV_TIMEOUT, handle_event_cb, thread_id, time)
  elseif ev == "cv" then
    local cv = fd
    table.insert(cv, thr) 
  else
    queue_event(thr, "idle", fd)
  end
end

function signal(cv)
  for _, thr in ipairs(cv) do
    queue_event(thr, "idle")
  end
  if coroutine.running() then 
     yield()
  else
     queue_event("main", "idle")
     return event_loop()
  end
end

function cv()
   return {}
end

function new(func, ...)
  local args = { ... }
  local t = coroutine.create(function () return func(unpack(args)) end)
  queue_event(t, "idle")
  if coroutine.running() then 
     yield()
  else
     queue_event("main", "idle")
     return event_loop()
  end
end

local function get_next()
  local next = table.remove(next_thread)
  if not next then
    next = table.remove(waiting_threads.idle)
  end
  return next
end

function event_loop()
   local block = EVLOOP_NONBLOCK
   while true do
      libevent.event_loop(block)
      block = EVLOOP_NONBLOCK
      local next = get_next()
      if not next then
	 block = EVLOOP_ONCE
      elseif next == "main" then
	 return
      else
	 local status, ev, obj, time = coroutine.resume(next)
	 if status then
	    if coroutine.status(next) == "suspended" then
	       handle_yield(next, ev, obj, time)
	    end
	 else
	    error(ev)
	 end
      end
   end
end

local function socket_send(self, data, from, to)
  local client = self.socket
  local s, err,sent
  from = from or 1
  local lastIndex = from - 1
  repeat
    s, err, lastIndex = client:send(data, lastIndex + 1, to)
    if s or err ~= "timeout" then
      return s, err, lastIndex
    end
    thread.yield("write", self.fd)
  until false
end

local function socket_receive(self, pattern)
  local client = self.socket
  local s, err, part
  pattern = pattern or "*l"
  repeat
    s, err, part = client:receive(pattern, part)
    if s or err ~= "timeout" then
      return s, err, part
    end
    thread.yield("read", self.fd)
  until false
end

local function socket_flush(self)
end

local function socket_settimeout(self)
end

local function socket_accept(self)
  local skt = self.socket
  repeat
    local ret, err = skt:accept()
    if ret or err ~= "timeout" then
      return ret, err
    end
    thread.yield("read", self.fd)
  until false
end

local function socket_connect(self, host, port)
  local skt = self.socket
  repeat
    local ret, err = skt:connect(host, port)
    if ret or err ~= "timeout" then
      return ret, err
    end
    thread.yield("write", self.fd)
  until false
end

local socket_wrapped = { receive = socket_receive, send = socket_send,
			 flush = socket_flush, settimeout = socket_settimeout,
			 accept = socket_accept, connect = socket_connect }

local socket_mt = { __index = function (skt, name)
				return socket_wrapped[name] or 
				  function (wrpd_skt, ...)
				    return rawget(skt, "socket")[name](wrpd_skt.socket, ...)
				  end
			      end }


function wrap_socket(skt)
  local wrapped = { socket = skt, fd = skt:getfd() }
  skt:settimeout(0)
  setmetatable(wrapped, socket_mt)
  return wrapped
end
