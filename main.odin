package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

//
// Tokenizer
//

TokenKind :: enum {
	LParen = '(',
	RParen = ')',
	Star   = '*',
	Slash  = '/',
	Plus   = '+',
	Minus  = '-',
	Num    = 48, // ascii number 0
	Eof    = 0, // NUL '\0'
}
Token :: struct {
	kind: TokenKind,
	next: ^Token,
	val : int, // If kind is TK_NUM, its value
	loc : int, // Token location
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
// Ensure that the current token kind is `kind`.
skip :: proc(tok: ^Token, kind: TokenKind) -> (next: ^Token) {
	if tok.kind != kind {
		error_at(tok.loc, "expected %q", rune(kind))
	}
	return tok.next
}

tokenize :: proc(str := current_input) -> ^Token {
	head := Token{}
	cur := &head
	i := 0
	for i < len(str) {
		ch := utf8.rune_at_pos(str, i)
		switch {
		case unicode.is_space(ch): i += 1
		case unicode.is_digit(ch):
			val, len := parse_number(str[i:])
			cur.next = new_token(.Num, i)
			cur = cur.next
			cur.val = val
			i += len
		case: switch ch {
				case '+', '-', '*', '/', '(', ')':
					cur.next = new_token(TokenKind(ch), i)
					cur = cur.next
					i += 1
				case: error_at(i, "invalid token")
				}}
	}
	cur.next = new_token(.Eof, i)
	cur = cur.next
	return head.next
}

//
// Parser
//

NodeKind :: enum {
	Add = '+',
	Sub = '-',
	Mul = '*',
	Div = '/',
	Num = 48, // ascii number 0
}

// AST node type
Node :: struct {
	kind: NodeKind,
	lhs : ^Node,
	rhs : ^Node,
	val : int, // If kind is ND_NUM, its value
}
new_node :: proc(kind: NodeKind) -> ^Node {
	node, _ := new(Node)
	node.kind = kind
	return node
}
new_binary :: proc(kind: NodeKind, lhs, rhs: ^Node) -> ^Node {
	node := new_node(kind)
	node.lhs = lhs
	node.rhs = rhs
	return node
}
new_num :: proc(val: int) -> ^Node {
	node := new_node(NodeKind.Num)
	node.val = val
	return node
}

// primary = "(" expr ")" | num
primary :: proc(tok: ^Token) -> (node: ^Node, rest: ^Token) {
	#partial switch tok.kind {
	case .Num:
		node = new_num(tok.val)
		rest = tok.next
	case .LParen:
		node, rest = expr(tok.next)
		rest = skip(rest, .RParen)
	case: error_at(tok.loc, "expected an expression")
	}
	return
}

// mul = primary ("*" primary | "/" primary)*
mul :: proc(tok: ^Token) -> (node: ^Node, rest: ^Token) {
	node, rest = primary(tok)
	for {
		#partial switch rest.kind {
		case .Star:
			rhs, new_rest := primary(rest.next)
			node = new_binary(.Mul, node, rhs)
			rest = new_rest
		case .Slash:
			rhs, new_rest := primary(rest.next)
			node = new_binary(.Div, node, rhs)
			rest = new_rest
		case: return
		}}
}

// expr = mul ("+" mul | "-" mul)*
expr :: proc(tok: ^Token) -> (node: ^Node, rest: ^Token) {
	node, rest = mul(tok)
	for {
		#partial switch rest.kind {
		case .Plus:
			rhs, new_rest := mul(rest.next)
			node = new_binary(.Add, node, rhs)
			rest = new_rest
		case .Minus:
			rhs, new_rest := mul(rest.next)
			node = new_binary(.Sub, node, rhs)
			rest = new_rest
		case: return
		}}
}

//
// Code generator
//

depth: int

// push reg to stack-top
gen_push :: proc(sb: ^strings.Builder) {
	fmt.sbprintfln(sb, "  push %%rax")
	depth += 1
}
// pop stack-top to arg
gen_pop :: proc(sb: ^strings.Builder, arg: string) {
	fmt.sbprintfln(sb, "  pop %s", arg)
	depth -= 1
}
gen_expr :: proc(sb: ^strings.Builder, node: ^Node) {
	if node.kind == .Num {
		fmt.sbprintfln(sb, "  mov $%v, %%rax", node.val)
		return
	}
	gen_expr(sb, node.rhs)
	gen_push(sb)
	gen_expr(sb, node.lhs)
	gen_pop(sb, "%rdi")
	#partial switch node.kind {
	case .Add: fmt.sbprintfln(sb, "  add %%rdi, %%rax")
	case .Sub: fmt.sbprintfln(sb, "  sub %%rdi, %%rax")
	case .Mul: fmt.sbprintfln(sb, "  imul %%rdi, %%rax")
	case .Div:
		fmt.sbprintfln(sb, "  cqo")
		fmt.sbprintfln(sb, "  idiv %%rdi")
	case: error("invalid expression")
	}
}

print_ast :: proc(node: ^Node) {
	print_ast_inner(node, 0)
}
print_ast_inner :: proc(node: ^Node, indent: int) {
	pad := strings.repeat("  ", indent)
	switch node.kind {
	case .Num: fmt.printfln("%s%v", pad, node.val)
	case .Add, .Sub, .Mul, .Div:
		fmt.printfln("%s%v", pad, rune(node.kind))
		print_ast_inner(node.lhs, indent + 1)
		print_ast_inner(node.rhs, indent + 1)
	}
}

main :: proc() {
	args := os.args
	if len(args) < 2 {
		error("%v: too few arguments", args[0])
	}

	// Tokenize and parse.
	current_input = args[1]
	tok := tokenize()
	sb := strings.builder_make()
	node, rest := expr(tok)
	if rest.kind != .Eof {
		error_at(rest.loc, "extra token")
	}

	if len(args) > 2 && args[2] == "-ast" {
		print_ast(node)
		return
	}

	fmt.sbprintfln(&sb, "  .globl main")
	fmt.sbprintfln(&sb, "main:")

	// Traverse the AST to emit assembly.
	gen_expr(&sb, node)
	fmt.sbprintfln(&sb, "  ret")
	assert(depth == 0)

	fmt.print(strings.to_string(sb))
}
