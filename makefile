CC=odin

chibicc: main.odin
	$(CC) build main.odin -file -out:chibicc

test: chibicc
	./test.sh

clean:
	rm -f chibicc *.o *~ tmp*

.PHONY: test clean
