package chibicc

NodeKind :: enum {
	Add      = '+',
	Sub      = '-',
	Mul      = '*',
	Div      = '/',
	Neg      = -'-',
	Eq       = '=' * 2,
	Ne       = '!' + '=',
	Lt       = '<',
	Le       = '<' + '=',
	Assign   = '=',
	ExprStmt = ';', // Expression statement
	Var      = 'a' + '_', // Variable
	Num      = 48, // ascii number 0
}

// AST node type
Node :: struct {
	next, lhs, rhs: ^Node,
	name          : string, // Used if kind == ND_VAR
	kind          : NodeKind,
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

new_var_node :: proc(name: string) -> ^Node {
	node := new_node(NodeKind.Var)
	node.name = name
	return node
}

// stmt = expr-stmt
stmt :: proc(tok: ^Token) -> (node: ^Node, rest: ^Token) {
	return expr_stmt(tok)
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
		i := tok.loc
		node = new_var_node(current_input[i:i + 1])
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
parse :: proc(tok: ^Token) -> ^Node {
	head := Node{}
	cur := &head
	node, rest := stmt(tok)
	cur.next = node
	cur = cur.next
	for rest.kind != .Eof {
		next, stmt_rest := stmt(rest)
		rest = stmt_rest
		cur.next = next
		cur = cur.next
	}
	return head.next
}
