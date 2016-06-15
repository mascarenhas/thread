
all: src/aio_constants.lua src/event_constants.lua

src/aio_constants.lua: src/aio_constants
	cd src && ./aio_constants

src/aio_constants: src/aio_constants.c
	$(CC) -o src/aio_constants src/aio_constants.c

src/aio_constants.c: src/aio_constants.def
	./constants src/aio_constants.def src/aio_constants.c aio_constants.lua

src/event_constants.lua: src/event_constants
	cd src && ./event_constants

src/event_constants: src/event_constants.c
	$(CC) -o src/event_constants -I$(LIBEVENT_INCDIR) src/event_constants.c

src/event_constants.c: src/event_constants.def
	./constants src/event_constants.def src/event_constants.c event_constants.lua

install:
	cp src/*.lua $(LUA_DIR)
	mkdir -p $(LUA_DIR)/thread
	cp src/thread/*.lua $(LUA_DIR)/thread
	cp -r tests $(PREFIX)/

clean:
	rm -f src/event_constants src/event_constants.lua src/aio_constants src/aio_constants.lua src/event_constants.c src/aio_constants.c

upload:
	darcs dist -d aio-current
	scp aio-current.tar.gz mascarenhas@www.lua.inf.puc-rio.br:public_html/
