#+private file

package chibicc

import "core:fmt"
import "core:strings"

depth: int

sb: ^strings.Builder

sbprintfln :: proc(fmt_s: string, args: ..any) {
	fmt.sbprintfln(sb, fmt_s, ..args)
}

@(private)
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

	gen_stmt(prog.body)
	assert(depth == 0)

	sbprintfln(".L.return:")
	// Epilogue
	sbprintfln("  mov %%rbp, %%rsp")
	sbprintfln("  pop %%rbp")

	sbprintfln("  ret")
	fmt.print(strings.to_string(buf))
}

gen_stmt :: proc(node: ^Node) {
	#partial switch node.kind {
	case .ND_IF:
		c := count()
		gen_expr(node.cond)
		sbprintfln("  cmp $0, %%rax")
		sbprintfln("  je  .L.else.%d", c)
		gen_stmt(node.then)
		sbprintfln("  jmp .L.end.%d", c)
		sbprintfln(".L.else.%d:", c)
		if node.els != nil {
			gen_stmt(node.els)
		}
		sbprintfln(".L.end.%d:", c)
	case .ND_FOR:
		c := count()
		if node.init != nil {
			gen_stmt(node.init)
		}
		sbprintfln(".L.begin.%d:", c)

		if node.cond != nil {
			gen_expr(node.cond)
			sbprintfln("  cmp $0, %%rax")
			sbprintfln("  je  .L.end.%d", c)
		}
		gen_stmt(node.then)

		if node.inc != nil {
			gen_expr(node.inc)
		}
		sbprintfln("  jmp .L.begin.%d", c)
		sbprintfln(".L.end.%d:", c)
	case .Block: for nd := node.body; nd != nil; nd = nd.next {
				gen_stmt(nd)
			}
	case .ND_RETURN:
		gen_expr(node.lhs)
		sbprintfln("  jmp .L.return")
	case .ExprStmt: gen_expr(node.lhs)
	case: error_tok(node.tok, "invalid statement")
	}
}

// Compute the absolute address of a given node.
// It's an error if a given node does not reside in memory.
gen_addr :: proc(node: ^Node) {
	#partial switch node.kind {
	case .Var: sbprintfln("  lea %d(%%rbp), %%rax", node.var.offset)
	case .Deref: gen_expr(node.lhs)
	case: error_tok(node.tok, "not an left-value")
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
	case .Deref:
		gen_expr(node.lhs)
		sbprintfln("  mov (%%rax), %%rax")
		return
	case .Ref:
		gen_addr(node.lhs)
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
	case: error_tok(node.tok, "invalid expression")
	}
}

count :: proc() -> int {
	@(static) i := 1
	defer i += 1
	return i
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
