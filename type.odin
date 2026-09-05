package chibicc

TypeKind :: enum {
	TY_INT,
	TY_PTR,
}

Type :: struct {
	kind: TypeKind,
	base: ^Type,
}

ty_int: ^Type = &Type{kind = .TY_INT}

is_integer :: proc(ty: ^Type) -> bool {
	return ty.kind == .TY_INT
}

pointer_to :: proc(base: ^Type) -> ^Type {
	ty, _ := new(Type)
	ty^ = {
		kind = .TY_PTR,
		base = base,
	}
	return ty
}
mark_type :: proc(node: ^Node) {
	if node == nil || node.ty != nil {return}

	mark_type(node.lhs)
	mark_type(node.rhs)
	mark_type(node.cond)
	mark_type(node.then)
	mark_type(node.els)
	mark_type(node.init)
	mark_type(node.inc)

	for nd := node.body; nd != nil; nd = nd.next {
		mark_type(nd)
	}

	#partial switch node.kind {
	case .Add, .Sub, .Mul, .Div, .Neg, .Assign: node.ty = node.lhs.ty
	case .Eq, .Ne, .Lt, .Le, .Var, .Num: node.ty = ty_int
	case .Ref: node.ty = pointer_to(node.lhs.ty)
	case .Deref: if node.lhs.ty.kind == .TY_PTR {
				node.ty = node.lhs.ty.base
			} else {
				node.ty = ty_int
			}
	}
}
