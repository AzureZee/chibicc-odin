package chibicc

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

parse :: proc(tok: ^Token) -> ^Node {
	node, rest := expr(tok)
	if rest.kind != .Eof {
		error_at(rest.loc, "extra token")
	}
	return node
}
