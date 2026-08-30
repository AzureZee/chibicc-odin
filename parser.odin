package chibicc

// All local variable instances created during parsing are
// accumulated to this list.
locals: ^Obj

// Local variable
Obj :: struct {
	name  : string,
	next  : ^Obj,
	offset: int, // Offset from RBP
}

find_var :: proc(tok: ^Token) -> ^Obj {
	for var := locals; var != nil; var = var.next {
		if tok_str(tok) == var.name {
			return var
		}
	}
	return nil
}

Function :: struct {
	body      : ^Node,
	locals    : ^Obj,
	stack_size: int, // Offset from RBP
}

NodeKind :: enum {
	Block    = '{', // { ... }
	Add      = '+',
	Sub      = '-',
	Mul      = '*',
	Div      = '/',
	Neg      = -'-',
	Lt       = '<', // < and >
	Le       = -'<', // <= and >=
	Ne       = -'!', // !=
	Eq       = -'=', // ==
	Assign   = '=',
	ExprStmt = ';', // Expression statement
	Num      = '0', // ascii number 0
	Var      = 1000, // Variable
	Return   = 9999,
}

// AST node type
Node :: struct {
	kind          : NodeKind,
	next, lhs, rhs: ^Node,
	body          : ^Node, // Block
	var           : ^Obj, // Used if kind == ND_VAR
	val           : int, // Used if kind == ND_NUM
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

new_var_node :: proc(var: ^Obj) -> ^Node {
	node := new_node(NodeKind.Var)
	node.var = var
	return node
}
new_local_var :: proc(name: string) -> ^Obj {
	var, _ := new(Obj)
	var^ = {
		name = name,
		next = locals,
	}
	locals = var
	return var
}

// stmt = "return" expr ";"
//      | "{" compound-stmt
//      | expr-stmt
stmt :: proc(tok: ^Token) -> (node: ^Node, rest: ^Token) {
	#partial switch tok.kind {
	case .K_Return:
		lhs, expr_rest := expr(tok.next)
		node = new_unary(.Return, lhs)
		rest = skip(expr_rest, .Semi)
		return
	case .LCurly: return compound_stmt(tok.next)
	}
	return expr_stmt(tok)
}

// compound-stmt = stmt* "}"
compound_stmt :: proc(tok: ^Token) -> (^Node, ^Token) {
	head := Node{}
	cur := &head
	node, rest := stmt(tok)
	cur.next = node
	cur = cur.next
	for rest.kind != .RCurly {
		next, stmt_rest := stmt(rest)
		rest = stmt_rest
		cur.next = next
		cur = cur.next
	}
	node = new_node(.Block)
	node.body = head.next
	return node, rest.next
}

// expr-stmt = expr ";"
expr_stmt :: proc(tok: ^Token) -> (node: ^Node, rest: ^Token) {
	lhs, expr_rest := expr(tok)
	node = new_unary(.ExprStmt, lhs)
	rest = skip(expr_rest, .Semi)
	return
}

// expr = assign
expr :: proc(tok: ^Token) -> (node: ^Node, rest: ^Token) {
	return assign(tok)
}

// assign = equality ("=" assign)?
assign :: proc(tok: ^Token) -> (node: ^Node, rest: ^Token) {
	lhs, eq_rest := equality(tok)
	if eq_rest.kind == .Equal {
		rhs, assign_rest := assign(eq_rest.next)
		node = new_binary(.Assign, lhs, rhs)
		rest = assign_rest
	} else {
		node = lhs
		rest = eq_rest
	}
	return
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

// primary = "(" expr ")" | ident | num
primary :: proc(tok: ^Token) -> (node: ^Node, rest: ^Token) {
	#partial switch tok.kind {
	case .Ident:
		var := find_var(tok)
		if var == nil {
			var = new_local_var(tok_str(tok))
		}
		node = new_var_node(var)
		rest = tok.next
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

// program = stmt*
parse :: proc(tok: ^Token) -> ^Function {
	tok := skip(tok, .LCurly)
	node, rest := compound_stmt(tok)
	assert(rest.kind == .Eof)

	prog, _ := new(Function)
	prog^ = {
		body   = node,
		locals = locals,
	}
	return prog
}
