package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

main :: proc() {
	args := os.args
	if len(args) < 2 {
		fmt.eprintfln("%v: too few arguments", args[0])
		os.exit(1)
	}
	sb := strings.builder_make()
	arg := strings.trim_left_space(args[1])

	fmt.sbprintfln(&sb, "  .globl main")
	fmt.sbprintfln(&sb, "main:")
	cur: int
	num, _ := strconv.parse_i64_of_base(arg, 10, &cur)
	fmt.sbprintfln(&sb, "  mov $%v, %%rax", num)

	for cur < len(arg) {
		char := utf8.rune_at_pos(arg, cur)
		if char == '+' {
			cur += 1
			num := parse_arg_number(arg, &cur)
			fmt.sbprintfln(&sb, "  add $%v, %%rax", num)
			continue
		}
		if char == '-' {
			cur += 1
			num := parse_arg_number(arg, &cur)
			fmt.sbprintfln(&sb, "  sub $%v, %%rax", num)
			continue
		}
		fmt.eprintfln("unexpected character: '%v'", char)
		os.exit(1)
	}
	fmt.sbprintfln(&sb, "  ret")

	fmt.print(strings.to_string(sb))
}
parse_arg_number :: proc(arg: string, cur: ^int) -> i64 {
	i := cur^
	parsed: int
	num, _ := strconv.parse_i64_of_base(arg[i:], 10, &parsed)
	i += parsed
	cur^ = i
	return num
}
