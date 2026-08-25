package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

TokenKind :: enum {
	Plus = '+',
	Minus = '-',
	Num,
	Eof,
}
Token :: struct {
	kind: TokenKind,
	next: ^Token,
	val:  int, // If kind is TK_NUM, its value
	loc:  int, // Token location
}
new_token :: proc(kind: TokenKind, loc: int) -> ^Token {
	tok, _ := new(Token)
	tok.kind = kind
	tok.loc = loc
	return tok
}

// Input string
current_input: string

// Reports an error and exit.
error :: proc(fmt_str: string, args: ..any) {
	fmt.eprintfln(fmt_str, ..args)
	os.exit(1)
}

// Reports an error location and exit.
error_at :: proc(pos: int, fmt_str: string, args: ..any) {
	fmt.eprintfln("%s", current_input)
	fmt.eprintf("%*s^ ", pos, "") // print pos spaces
	fmt.eprintfln(fmt_str, ..args)
	os.exit(1)
}

// Ensure that the current token kind is Num.
get_number :: proc(tok: ^Token) -> int {
	if tok.kind != .Num {
		error_at(tok.loc, "expected a number")
	}
	return tok.val
}
parse_number :: proc(str: string) -> (num: int, parsed_len: int) {
	num_i64, _ := strconv.parse_i64_of_base(str, 10, &parsed_len)
	num = int(num_i64)
	return
}

tokenize :: proc(str := current_input) -> ^Token {
	head := Token{}
	cur := &head
	i := 0
	for i < len(str) {
		ch := utf8.rune_at_pos(str, i)
		switch {
		case unicode.is_space(ch):
			i += 1
		case unicode.is_digit(ch):
			{
				val, len := parse_number(str[i:])
				cur.next = new_token(.Num, i)
				cur = cur.next
				cur.val = val
				i += len
			}
		case:
			{
				switch ch {
				case '+', '-':
					{
						cur.next = new_token(TokenKind(ch), i)
						cur = cur.next
						i += 1
					}
				case:
					error_at(i, "invalid token")
				}}}
	}
	cur.next = new_token(.Eof, i)
	cur = cur.next
	return head.next
}

main :: proc() {
	args := os.args
	if len(args) < 2 {
		error("%v: too few arguments", args[0])
	}

	current_input = args[1]
	tok := tokenize()
	sb := strings.builder_make()

	fmt.sbprintfln(&sb, "  .globl main")
	fmt.sbprintfln(&sb, "main:")

	// The first token must be a number
	fmt.sbprintfln(&sb, "  mov $%v, %%rax", get_number(tok))
	tok = tok.next

	// ... followed by either `+ <number>` or `- <number>`.
	for tok.kind != .Eof {
		#partial switch tok.kind {
		case .Plus:
			fmt.sbprintfln(&sb, "  add $%v, %%rax", get_number(tok.next))
		case .Minus:
			fmt.sbprintfln(&sb, "  sub $%v, %%rax", get_number(tok.next))
		}
		tok = tok.next.next
	}
	fmt.sbprintfln(&sb, "  ret")

	fmt.print(strings.to_string(sb))
}
