
local thread = require "thread"

local function waiter(time, msg)
  while true do
    thread.sleep(time)
    print(msg)
  end
end

thread.new(waiter, 1000, "hi")
thread.new(waiter, 4000, "hello")

while true do
  thread.sleep(300)
  print("world")
end
