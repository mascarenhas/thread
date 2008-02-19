
require "alien"
require "alien.struct"

module(..., package.seeall)

local kernel = alien.kernel32

kernel.WaitForMultipleObjects:types{ abi = "stdcall", 
				     "int", "pointer", "int", "int"}
kernel.CreateWaitableTimer:types{ abi = "stdcall",
				  "pointer", "int", "string"}
kernel.SetWaitableTimer:types{ abi = "stdcall",
			       "int", "pointer", "int", 
			       "pointer", "pointer", "int" }
kernel.CloseHandle:types{ abi = "stdcall", "int" }

event.event_init()

local WAIT_TIMEOUT = 0x0102

local current_thread = "main"

local wait_handles = {}
local waiting_threads = {}
local idle_threads = {}
local timers = {}
local next_thread = {}

local function handle_event(pos)
  local handle = wait_handles[pos]
  local thr = waiting_threads[handle]
  table.insert(next_thread, 1, thr)
  waiting_threads[handle] = nil
  table.remove(wait_handles, pos)
  local timer = timers[thr]
  if timer then
    local t_pos, t_handle = unpack(timer)
    kernel.CloseHandle(t_handle)
    if t_pos ~= pos then
      table.remove(wait_handles, t_pos)
      waiting_threads[t_handle] = nil
    end
  end
end

local function queue_event(thr, handle)
  waiting_threads[handle] = thr
  table.insert(wait_handles, handle)
end

local function queue_timer(thr, timeout)
  timeout = timeout * 10000
  local t = alien.struct.pack("I64", timeout)
  local handle = kernel.CreateWaitableTimer(nil, 1, nil)
  local res = kernel.SetWaitableTimer(handle, t, 0, nil, nil, 0) 
  if res ~= 0 then
    local pos = table.insert(wait_handles, handle)
    timers[thr] = { pos, handle }
    waiting_threads[handle] = thr
  else
    error("could not create timer")
  end
end

local function queue_idle(thr)
  table.insert(idle_threads, 1, thr)
end

function yield(ev, handle, timeout)
  if type(ev) == "number" then
    ev, handle = "timer", ev
  end
  if ev == "read" or ev == "write" then
    queue_event(current_thread, handle)
    if timeout then
      queue_timer(current_thread, timeout)
    end
  elseif ev == "timer" then
    queue_timer(current_thread, handle)
  else
    queue_idle(current_thread)
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
  queue_idle(t)
  queue_idle(current_thread)
  if current_thread == "main" then
    event_loop()
  else
    coroutine.yield()
  end
end

local function get_next()
  local next = table.remove(next_thread)
  if not next then
    next = table.remove(idle_threads)
  end
  return next
end

local function run_loop(block)
  local handles = alien.array("int", wait_handles)
  local timeout
  if block then timeout = 0 else timeout = 1 end
  local res = kernel.WaitForMultipleObjects(#wait_handles, handles, 
					    0, timeout)
  if res ~= WAIT_TIMEOUT then
    handle_event(res + 1)
  end
end

function event_loop()
  local block = false
  while true do
    run_loop(block)
    block = false
    local next = get_next()
    current_thread = next
    if not next then
      block = true
    elseif next == "main" then
      return 
    else 
      next()
    end
  end
end
