package chibicc

import "core:fmt"
import "core:strings"

@(private = "file")
depth: int

@(private = "file")
sb: ^strings.Builder

@(private = "file")
sbprintfln :: proc(fmt_s: string, args: ..any) {
	fmt.sbprintfln(sb, fmt_s, ..args)
}

codegen :: proc(node: ^Node) {
	buf := strings.builder_make()
	sb = &buf
	sbprintfln("  .globl main")
	sbprintfln("main:")

	// Prologue
	sbprintfln("  push %%rbp")
	sbprintfln("  mov %%rsp, %%rbp")
	sbprintfln("  sub $208, %%rsp") // 26 * 8 = 208

	for nd := node; nd != nil; nd = nd.next {
		gen_stmt(nd)
		assert(depth == 0)
	}

	// Epilogue
	sbprintfln("  mov %%rbp, %%rsp")
	sbprintfln("  pop %%rbp")

	sbprintfln("  ret")
	fmt.print(strings.to_string(buf))
}

gen_stmt :: proc(node: ^Node) {
	if node.kind == .ExprStmt {
		gen_expr(node.lhs)
	} else {
		error("invalid statement")
	}
}

// Compute the absolute address of a given node.
// It's an error if a given node does not reside in memory.
gen_addr :: proc(node: ^Node) {
	if node.kind == .Var {
		offset := (node.name[0] - 'a' + 1) * 8
		sbprintfln("  lea %d(%%rbp), %%rax", -offset)
	} else {
		error("not an left-value")
	}
}

gen_expr :: proc(node: ^Node) {
	#partial switch node.kind {
	case .Num:
		sbprintfln("  mov $%v, %%rax", node.val)
		return
	case .Neg:
		gen_expr(node.lhs)
		sbprintfln("  neg %%rax")
		return
	case .Var:
		gen_addr(node)
		sbprintfln("  mov (%%rax), %%rax")
		return
	case .Assign:
		gen_addr(node.lhs)
		push()
		gen_expr(node.rhs)
		pop("%rdi")
		sbprintfln("  mov %%rax, (%%rdi)")
		return
	}
	gen_expr(node.rhs)
	push()
	gen_expr(node.lhs)
	pop("%rdi")

	#partial switch node.kind {
	case .Add: sbprintfln("  add %%rdi, %%rax")
	case .Sub: sbprintfln("  sub %%rdi, %%rax")
	case .Mul: sbprintfln("  imul %%rdi, %%rax")
	case .Div:
		sbprintfln("  cqo")
		sbprintfln("  idiv %%rdi")
	case .Eq, .Ne, .Lt, .Le:
		sbprintfln("  cmp %%rdi, %%rax")
		#partial switch node.kind {
		case .Eq: sbprintfln("  sete %%al")
		case .Ne: sbprintfln("  setne %%al")
		case .Lt: sbprintfln("  setl %%al")
		case .Le: sbprintfln("  setle %%al")
		}
		sbprintfln("  movzb %%al, %%rax")
	case: error("invalid expression")
	}
}

// push reg to stack-top
push :: proc() {
	sbprintfln("  push %%rax")
	depth += 1
}

// pop stack-top to arg
pop :: proc(arg: string) {
	sbprintfln("  pop %s", arg)
	depth -= 1
}
