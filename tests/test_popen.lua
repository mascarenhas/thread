require "luarocks.require"
require "aio"
require "thread"

local function tail(file)
  local f = aio.popen("tail -f " .. file, "r")
  local lines = f:lines()
  local line = lines()
  while line do
    aio.write(line, "\n")
    line = lines()
    thread.yield()
  end
end

thread.new(tail, "foo.txt")
thread.new(tail, "bar.txt")

while true do
  thread.yield(2000)
  print("yeah!")
end
