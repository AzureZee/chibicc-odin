CC = odin
BIN = chibicc

$(BIN): main.odin
	$(CC) build . -out:$(BIN)

debug: main.odin
	$(CC) build . -out:$(BIN) -debug

release: main.odin
	$(CC) build . -out:$(BIN) -o:speed

test: $(BIN)
	./test.sh

clean:
	rm -f chibicc *.o *~ tmp*

.PHONY: clean
