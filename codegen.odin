package chibicc

import "core:fmt"
import "core:strings"

codegen :: proc(node: ^Node) {
	sb := strings.builder_make()
	fmt.sbprintfln(&sb, "  .globl main")
	fmt.sbprintfln(&sb, "main:")

	// Traverse the AST to emit assembly.
	gen_expr(&sb, node)
	fmt.sbprintfln(&sb, "  ret")
	assert(depth == 0)

	fmt.print(strings.to_string(sb))
}

depth: int

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
