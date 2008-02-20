
require "luarocks.require"

require "alien"

lua = alien.default

new = lua.luaL_newstate
new:types("pointer")
L = new()
load = lua.luaL_loadstring
load:types("int", "pointer", "string")

resume = lua.lua_resume
resume:types("int", "pointer", "int")

ton = lua.lua_tonumber
ton:types("double", "pointer", "int")

newt = lua.lua_newthread
newt:types("pointer", "pointer")

print(load(L, [[
		 print("foo")
		 coroutine.yield(2, 3)
		 print("bar")
		 coroutine.yield(4)
		 print("baz")
		 return 5
	   ]]))

tos = lua.lua_tolstring
tos:types("string", "pointer", "int", "ref int")

top = lua.lua_gettop
top:types("int", "pointer")

libs = lua.luaL_openlibs
libs:types("int", "pointer")

print(libs(L))

print("res: " .. resume(L, 0))
print("top: " .. top(L))
print(ton(L, -2))
print(ton(L, -1))
print("res: " .. resume(L, 0))
print("top: " .. top(L))
print(ton(L, -1))
print("res: " .. resume(L, 0))
print("top: " .. top(L))
print(ton(L, -1))

