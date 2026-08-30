package chibicc

import "core:os"

main :: proc() {
	args := os.args
	if len(args) < 2 {
		error("%v: too few arguments", args[0])
	}
	tok := tokenize(args[1])
	prog := parse(tok)
	// Traverse the AST to emit assembly.
	codegen(prog)
}
