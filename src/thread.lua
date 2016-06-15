
local alien = require "alien"
local coroutine = require "taggedcoro"

local thread = { TAG = "thread" }

local libevent = alien.load("event")

libevent.event_init:types("pointer")
libevent.event_set:types("void", "pointer", "int", "int", "callback", "string")
libevent.event_add:types("int", "pointer", "pointer")
libevent.event_dispatch:types("int")
libevent.event_once:types("int", "int", "int", "callback", "pointer", "string")
libevent.event_loop:types("int", "int")

libevent.event_init()

local evcodes = require("event_constants")

local events = {
  read = evcodes.EV_READ,
  write = evcodes.EV_WRITE,
}

local live_threads = setmetatable({}, { __mode = "v" })

local waiting_threads = {
  [evcodes.EV_READ] = {},
  [evcodes.EV_WRITE] = {},
  idle = {}
}

local cvs = setmetatable({}, { __mode = "v" })

local event_cache = {}

local events_in_use = {}

local function get_event(thread_id)
  local ev = table.remove(event_cache)
  if not ev then
    ev = alien.buffer(evcodes.EV_SIZE)
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
  if ev_code == evcodes.EV_TIMEOUT then
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

local handle_event_cb = alien.callback(handle_event, "void", "int", "int", "string")

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

function thread.yield(...)
   if coroutine.isyieldable(thread.TAG) then
      coroutine.yield(thread.TAG, ...)
   else
      thread.handle_yield("main", ...)
      return thread.event_loop()
   end
end

function thread.sleep(ms)
  thread.yield("timer", ms)
end

function thread.handle_yield(thr, ev, fd, timeout)
  if type(ev) == "number" then
    ev, fd = "timer", ev
  end
  if ev == "read" or ev == "write" then
    local ev_code = events[ev]
    local time
    if timeout then
      time = alien.pack("ll", math.floor(timeout / 1000), (timeout % 1000) * 1000)
      queue_timer(thr)
    end
    local thread_id = tostring(thr)
    local evobj = get_event(thread_id)
    libevent.event_set(evobj, fd, ev_code, handle_event_cb, thread_id)
    libevent.event_add(evobj, time)
    queue_event(thr, ev_code, fd)
  elseif ev == "timer" then
    fd, timeout = -1, fd
    local time = alien.pack("ll", math.floor(timeout / 1000), (timeout % 1000) * 1000)
    local thread_id = queue_timer(thr)
    libevent.event_once(fd, evcodes.EV_TIMEOUT, handle_event_cb, thread_id, time)
  elseif ev == "cv" then
    local cv = fd
    cv[thr] = true
  elseif ev == "cvs" then
    local cvs = fd
    for _, cv in ipairs(cvs) do
      cv[thr] = true
    end
  else
    queue_event(thr, "idle", fd)
  end
end

function thread.signal(cv)
  local awake = {}
  for thr, _ in pairs(cv) do
    awake[#awake+1] = thr
    queue_event(thr, "idle")
  end
  for _, thr in ipairs(awake) do
    for _, cv in ipairs(cvs) do
      cv[thr] = nil
    end
  end
  thread.yield("idle")
end

function thread.cv()
  local cv = {}
  cvs[#cvs+1] = cv
  return cv
end

function thread.new(func, ...)
  local args = { ... }
  local t = coroutine.wrap(function () return "dead", func(table.unpack(args)) end, thread.TAG)
  live_threads[t] = true
  queue_event(t, "idle")
  thread.yield("idle")
end

function thread.join()
  thread.yield()
end

local function get_next()
  local next = table.remove(next_thread)
  if not next then
    next = table.remove(waiting_threads.idle)
  end
  return next
end

function thread.event_loop()
   local block = evcodes.EVLOOP_NONBLOCK
   while true do
      libevent.event_loop(block)
      block = evcodes.EVLOOP_NONBLOCK
      local next = get_next()
      if not next then
     	  block = evcodes.EVLOOP_ONCE
      elseif next == "main" then
	      return
      else
	      local ev, obj, time = next()
        if ev ~= "dead" then
          thread.handle_yield(next, ev, obj, time)
        else
          live_threads[next] = nil
        end
	    end
   end
end

function thread.join()
  if coroutine.isyieldable(thread.TAG) then
    return error("cannot join outside main thread")
  end
  repeat
    thread.yield()
  until not next(live_threads)
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


function thread.wrap_socket(skt)
  local wrapped = { socket = skt, fd = skt:getfd() }
  skt:settimeout(0)
  setmetatable(wrapped, socket_mt)
  return wrapped
end

return thread
