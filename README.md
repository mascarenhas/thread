# Green Threads (Fibers) using LibEvent

This is a simple green threads (fibers) library
that uses libevent (through [alien](https://github.com/mascarenhas/alien))
for its event loop. Threads can wait on reads and writes
of file descriptions (the `aio` module implements non-blocking
IO on files, and the `thread` module has a function that wraps
LuaSocket sockets to be non-blocking), on sleep events, or
on signals from one or more condition variables.
