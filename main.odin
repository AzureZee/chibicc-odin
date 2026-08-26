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
	LAngle = '<',
	RAngle = '>',
	LtEq   = '<' + '=',
	GtEq   = '>' + '=',
	Bang   = '!',
	NotEq  = '!' + '=',
	EqEq   = '=' * 2,
	Equal  = '=',
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
	str_len := len(str)
	for i < str_len {
		ch := utf8.rune_at_pos(str, i)
		switch {
		case unicode.is_space(ch): i += 1
		case unicode.is_digit(ch):
			val, len := parse_number(str[i:])
			cur.next = new_token(.Num, i)
			cur = cur.next
			cur.val = val
			i += len
		case:
			tok_len := 1
			tok_kind := TokenKind(ch)
			switch ch {
			case '(', ')':
			case '+', '-', '*', '/':
			case '=', '!', '<', '>':
				inc_i := i + 1
				if (inc_i < str_len) && utf8.rune_at_pos(str, inc_i) == '=' {
					tok_len = 2
					tok_kind = TokenKind(ch + '=')
				}
			case: error_at(i, "invalid token")
			}
			cur.next = new_token(tok_kind, i)
			cur = cur.next
			i += tok_len
		}
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
	Neg = -'-',
	Eq  = '=' * 2,
	Ne  = '!' + '=',
	Lt  = '<',
	Le  = '<' + '=',
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
new_unary :: proc(kind: NodeKind, lhs: ^Node) -> ^Node {
	node := new_node(kind)
	node.lhs = lhs
	return node
}
new_num :: proc(val: int) -> ^Node {
	node := new_node(NodeKind.Num)
	node.val = val
	return node
}

// expr = equality
expr :: proc(tok: ^Token) -> (node: ^Node, rest: ^Token) {
	return equality(tok)
}

// equality = relational ("==" relational | "!=" relational)*
equality :: proc(tok: ^Token) -> (node: ^Node, rest: ^Token) {
	node, rest = relational(tok)
	for {
		kind: NodeKind
		#partial switch rest.kind {
		case .EqEq, .NotEq: kind = NodeKind(rest.kind)
		case: return
		}
		rhs, new_rest := relational(rest.next)
		node = new_binary(kind, node, rhs)
		rest = new_rest
	}
}

// relational = add ("<" add | "<=" add | ">" add | ">=" add)*
relational :: proc(tok: ^Token) -> (node: ^Node, rest: ^Token) {
	node, rest = add(tok)
	for {
		kind: NodeKind
		lhs, rhs: ^Node
		new_rest: ^Token
		#partial switch rest.kind {
		case .LAngle, .LtEq:
			kind = NodeKind(rest.kind); lhs = node; rhs, new_rest = add(rest.next)
		case .RAngle:
			kind = .Lt; lhs, new_rest = add(rest.next); rhs = node
		case .GtEq:
			kind = .Le; lhs, new_rest = add(rest.next); rhs = node
		case: return
		}
		node = new_binary(kind, lhs, rhs)
		rest = new_rest
	}
}

// add = mul ("+" mul | "-" mul)*
add :: proc(tok: ^Token) -> (node: ^Node, rest: ^Token) {
	node, rest = mul(tok)
	for {
		kind: NodeKind
		#partial switch rest.kind {
		case .Plus, .Minus: kind = NodeKind(rest.kind)
		case: return
		}
		rhs, new_rest := mul(rest.next)
		node = new_binary(kind, node, rhs)
		rest = new_rest
	}
}
// mul = unary ("*" unary | "/" unary)*
mul :: proc(tok: ^Token) -> (node: ^Node, rest: ^Token) {
	node, rest = unary(tok)
	for {
		kind: NodeKind
		#partial switch rest.kind {
		case .Star: kind = .Mul
		case .Slash: kind = .Div
		case: return
		}
		rhs, new_rest := unary(rest.next)
		node = new_binary(kind, node, rhs)
		rest = new_rest
	}
}

// unary = ("+" | "-") unary
//       | primary
unary :: proc(tok: ^Token) -> (node: ^Node, rest: ^Token) {
	#partial switch tok.kind {
	case .Plus: return unary(tok.next)
	case .Minus:
		lhs, new_rest := unary(tok.next)
		node = new_unary(.Neg, lhs)
		rest = new_rest
		return
	case: return primary(tok)
	}
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
	#partial switch node.kind {
	case .Num:
		fmt.sbprintfln(sb, "  mov $%v, %%rax", node.val)
		return
	case .Neg:
		gen_expr(sb, node.lhs)
		fmt.sbprintfln(sb, "  neg %%rax")
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
	case .Eq, .Ne, .Lt, .Le:
		fmt.sbprintfln(sb, "  cmp %%rdi, %%rax")
		#partial switch node.kind {
		case .Eq: fmt.sbprintfln(sb, "  sete %%al")
		case .Ne: fmt.sbprintfln(sb, "  setne %%al")
		case .Lt: fmt.sbprintfln(sb, "  setl %%al")
		case .Le: fmt.sbprintfln(sb, "  setle %%al")
		}
		fmt.sbprintfln(sb, "  movzb %%al, %%rax")
	case: error("invalid expression")
	}
}

//
// test-print
//

print_tok :: proc(tok: ^Token) {
	if tok.kind == .Eof {
		return
	}
	fmt.printfln("Kind=%v, loc=%v, val=%v", tok.kind, tok.loc, tok.val)
	print_tok(tok.next)
}
print_ast :: proc(node: ^Node) {
	print_ast_inner(node, 0)
}
print_ast_inner :: proc(node: ^Node, indent: int) {
	pad := strings.repeat("  ", indent)
	switch node.kind {
	case .Num: fmt.printfln("%s%v", pad, node.val)
	case .Neg:
		fmt.printfln("%s%v", pad, '-')
		print_ast_inner(node.lhs, indent + 1)
	case .Add, .Sub, .Mul, .Div, .Lt:
		fmt.printfln("%s%v", pad, rune(node.kind))
		print_ast_inner(node.lhs, indent + 1)
		print_ast_inner(node.rhs, indent + 1)

	case .Eq, .Ne, .Le:
		fmt.printfln("%s%v%v", pad, rune(int(node.kind) - '='), '=')
		print_ast_inner(node.lhs, indent + 1)
		print_ast_inner(node.rhs, indent + 1)
	}
}

main :: proc() {
	args := os.args
	if len(args) < 2 {
		error("%v: too few arguments", args[0])
	}
	state := 0
	if len(args) > 2 {
		if args[2] == "-tok" {
			state = 1
		} else if args[2] == "-ast" {
			state = 2
		}
	}

	// Tokenize and parse.
	current_input = args[1]
	tok := tokenize()

	if state == 1 {
		print_tok(tok)
		return
	}

	sb := strings.builder_make()
	node, rest := expr(tok)

	if state == 2 {
		print_ast(node)
		return
	}

	if rest.kind != .Eof {
		error_at(rest.loc, "extra token")
	}

	fmt.sbprintfln(&sb, "  .globl main")
	fmt.sbprintfln(&sb, "main:")

	// Traverse the AST to emit assembly.
	gen_expr(&sb, node)
	fmt.sbprintfln(&sb, "  ret")
	assert(depth == 0)

	fmt.print(strings.to_string(sb))
}
