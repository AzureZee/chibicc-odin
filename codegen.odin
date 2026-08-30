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

codegen :: proc(prog: ^Function) {
	assign_local_var_offsets(prog)

	buf := strings.builder_make()
	sb = &buf

	sbprintfln("  .globl main")
	sbprintfln("main:")

	// Prologue
	sbprintfln("  push %%rbp")
	sbprintfln("  mov %%rsp, %%rbp")
	sbprintfln("  sub $%d, %%rsp", prog.stack_size)

	for nd := prog.body; nd != nil; nd = nd.next {
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
		sbprintfln("  lea %d(%%rbp), %%rax", node.var.offset)
	} else {
		error("not an local value")
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

// Round up `n` to the nearest multiple of `align`. For instance,
// align_to(5, 8) returns 8 and align_to(11, 8) returns 16.
align_to :: proc(n, align: int) -> int {
	return (n + align - 1) / align * align
}

// Assign offsets to local variables.
assign_local_var_offsets :: proc(prog: ^Function) {
	offset := 0
	for var := prog.locals; var != nil; var = var.next {
		offset += 8
		var.offset = -offset
	}
	prog.stack_size = align_to(offset, 16)
}
