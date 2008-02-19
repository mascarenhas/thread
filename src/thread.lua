
require "alien"
require "alien.struct"

module("thread", package.seeall)

local event = alien.event

event.event_init:types("pointer")
event.event_set:types("void", "pointer", "int", "int", "callback", "string")
event.event_add:types("int", "pointer", "pointer")
event.event_dispatch:types("int")
event.event_once:types("int", "int", "int", "callback", "pointer", "string")
event.event_loop:types("int", "int")

event.event_init()

require("event_constants")

local events = {
  read = EV_READ,
  write = EV_WRITE,
}

local current_thread = "main"

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

function yield(ev, fd, timeout)
  if type(ev) == "number" then
    ev, fd = "timer", ev
  end
  if ev == "read" or ev == "write" then
    local ev_code = events[ev]
    local time
    if timeout then
      time = alien.struct.pack("ll", math.floor(timeout / 1000),
			       (timeout % 1000) * 1000)
      queue_timer(current_thread)
    end
    local thread_id = tostring(current_thread)
    local evobj = get_event(thread_id)
    event.event_set(evobj, fd, ev_code, handle_event_cb, thread_id)
    event.event_add(evobj, nil)
    queue_event(current_thread, ev_code, fd)
  elseif ev == "timer" then
    fd, timeout = -1, fd
    local time = alien.struct.pack("ll", math.floor(timeout / 1000),
				   (timeout % 1000) * 1000)
    local thread_id = queue_timer(current_thread)
    event.event_once(fd, EV_TIMEOUT, handle_event_cb, thread_id, time)
  else
    queue_event(current_thread, "idle", fd)
  end
  if current_thread == "main" then
    event_loop()
  else
    coroutine.yield()
  end
end

function new(func, ...)
  local args = { ... }
  local t = coroutine.wrap(function () return func(unpack(args)) end)
  queue_event(t, "idle")
  queue_event(current_thread, "idle")
  if current_thread == "main" then
    event_loop()
  else
    coroutine.yield()
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
    if block == EVLOOP_ONCE then print("block") end
    event.event_loop(block)
    block = EVLOOP_NONBLOCK
    local next = get_next()
    current_thread = next
    if not next then
      block = EVLOOP_ONCE
    elseif next == "main" then
      return 
    else 
      next()
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
    -- adds extra corrotine swap
    -- garantees that high throuput dont take other threads to starvation
    if (math.random(100) > 90) then
      thread.yield()
    end
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
