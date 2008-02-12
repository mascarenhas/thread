
all: src/aio_constants.lua src/event_constants.lua

src/aio_constants.lua: src/aio_constants
	cd src && ./aio_constants

src/aio_constants: src/aio_constants.c
	$(CC) -o src/aio_constants src/aio_constants.c

src/aio_constants.c: src/aio_constants.def
	constants src/aio_constants.def src/aio_constants.c aio_constants.lua

src/event_constants.lua: src/event_constants
	cd src && ./event_constants

src/event_constants: src/event_constants.c
	$(CC) -o src/event_constants -I$(LIBEVENT_INCDIR) src/event_constants.c

src/event_constants.c: src/event_constants.def
	constants src/event_constants.def src/event_constants.c event_constants.lua

install:
	cp src/*.lua $(LUA_DIR)
	cp -r tests $(PREFIX)/
	cp -r doc $(PREFIX)/

clean:
	rm -f src/event_constants src/event_constants.lua src/aio_constants src/aio_constants.lua src/event_constants.c src/aio_constants.c

upload:
	darcs dist -d aio-current
	ncftpput -u mascarenhas ftp.luaforge.net alien/htdocs aio-current.tar.gz
