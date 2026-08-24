package main

import "core:fmt"
import "core:os"
import "core:strings"

main :: proc() {
	args := os.args
	if len(args) < 2 {
		fmt.eprintfln("%v: too few arguments", args[0])
		os.exit(1)
	}
	sb := strings.builder_make()
	fmt.sbprintfln(&sb, "  .globl main")
	fmt.sbprintfln(&sb, "main:")
	fmt.sbprintfln(&sb, "  mov $%v, %%rax",args[1])
	fmt.sbprintfln(&sb, "  ret")

	fmt.print(strings.to_string(sb))
}
