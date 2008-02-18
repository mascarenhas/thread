
require "alien"
require "alien.struct"

module(..., package.seeall)

local event = alien.event

event.event_init:types("pointer")
event.event_set:types("void", "pointer", "int", "int", "callback", "pointer")
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

local timer_threads = {}

local next_thread

local function handle_event(fd, ev_code, thread_id)
  if ev_code == EV_TIMEOUT then
    next_thread = timer_threads[thread_id]
    timer_threads[thread_id] = nil
  else
    if thread_id then timer_threads[thread_id] = nil end
    local queue = waiting_threads[ev_code][fd]
    if queue then
      next_thread = queue[#queue]
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
    local time, thread_id
    if timeout then
      time = alien.struct.pack("ll", math.floor(timeout / 1000),
			       (timeout % 1000) * 1000)
      thread_id = queue_timer(current_thread)
    end
    event.event_once(fd, ev_code, handle_event_cb, thread_id, time)
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
  local next = next_thread
  next_thread = nil
  if not next then
    next = table.remove(waiting_threads.idle)
  end
  return next
end

function event_loop()
  local block = EVLOOP_NONBLOCK
  while true do
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
