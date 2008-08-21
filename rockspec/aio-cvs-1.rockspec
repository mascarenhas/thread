package = "AIO"

version = "cvs-1"

description = {
  summary = "Lua Threads with Asynchronous IO",
  detailed = [[
  AIO implements asynchronous I/O primitives on top of
  POSIX's O_NOBLOCK, plus a threading library that integrates
  with the I/O primitives and uses Libevent.
  ]],
  license = "MIT/X11",
  homepage = "http://alien.luaforge.net/aio"
}

dependencies = { "alien", "bitlib" }

external_dependencies = {
 platforms = {
  unix = {
    LIBEVENT = { header = "event.h" }
  }
 }
}

source = {
   url = "http://alien.luaforge.net/aio-current.tar.gz"
}

build = {
   type = "make",
   install_variables = {
      LUA_DIR = "$(LUADIR)",
      PREFIX = "$(PREFIX)"
   },
   build_variables = {
      CFLAGS = "$(CFLAGS)",
      LIBEVENT_INCDIR = "$(LIBEVENT_INCDIR)"
   }
}
