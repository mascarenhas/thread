
require "thread"

function waiter(time, msg)
  while true do
    thread.yield(time)
    print(msg)
  end
end

thread.new(waiter, 1000, "hi")
thread.new(waiter, 4000, "hello")

while true do
  thread.yield(300)
  print("world")
end
