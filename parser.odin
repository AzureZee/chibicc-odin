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
	Var      = 999, // Variable
	ND_IF    = __KEYWORD,
	Return   = 9999,
}

// AST node type
Node :: struct {
	kind           : NodeKind,
	next, lhs, rhs : ^Node,
	cond, then, els: ^Node, // "if" statement
	body           : ^Node, // Block
	var            : ^Obj, // Used if kind == ND_VAR
	val            : int, // Used if kind == ND_NUM
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
//      | "if" "(" expr ")" stmt ("else" stmt)?
//      | "{" compound-stmt
//      | expr-stmt
stmt :: proc(rest: ^^Token, tok: ^Token) -> ^Node {
	tok := tok
	#partial switch tok.kind {
	case .K_return:
		node := new_unary(.Return, expr(&tok, tok.next))
		rest^ = skip(tok, .Semi)
		return node
	case .K_if:
		node := new_node(.ND_IF)
		tok = skip(tok.next, .LParen)

		node.cond = expr(&tok, tok)
		tok = skip(tok, .RParen)

		node.then = stmt(&tok, tok)
		if tok.kind == .K_else {
			node.els = stmt(&tok, tok.next)
		}
		rest^ = tok
		return node
	case .LCurly: return compound_stmt(rest, tok.next)
	}
	return expr_stmt(rest, tok)
}

// compound-stmt = stmt* "}"
compound_stmt :: proc(rest: ^^Token, tok: ^Token) -> ^Node {
	head := Node{}
	cur := &head
	tok := tok
	for tok.kind != .RCurly {
		node := stmt(&tok, tok)
		cur.next = node
		cur = cur.next
	}
	node := new_node(.Block)
	node.body = head.next
	rest^ = tok.next
	return node
}

// expr-stmt = expr? ";"
expr_stmt :: proc(rest: ^^Token, tok: ^Token) -> ^Node {
	tok := tok
	if tok.kind == .Semi {
		rest^ = tok.next
		return new_node(.Block)
	}

	node := new_unary(.ExprStmt, expr(&tok, tok))
	rest^ = skip(tok, .Semi)
	return node
}

// expr = assign
expr :: proc(rest: ^^Token, tok: ^Token) -> ^Node {
	return assign(rest, tok)
}

// assign = equality ("=" assign)?
assign :: proc(rest: ^^Token, tok: ^Token) -> ^Node {
	tok := tok
	node := equality(&tok, tok)
	if tok.kind == .Equal {
		node = new_binary(.Assign, node, assign(&tok, tok.next))
	}
	rest^ = tok
	return node
}

// equality = relational ("==" relational | "!=" relational)*
equality :: proc(rest: ^^Token, tok: ^Token) -> ^Node {
	tok := tok
	node := relational(&tok, tok)
	for {
		#partial switch tok.kind {
		case .EqEq, .NotEq: node = new_binary(NodeKind(tok.kind), node, relational(&tok, tok.next))
		case:
			rest^ = tok
			return node
		}
	}
}

// relational = add ("<" add | "<=" add | ">" add | ">=" add)*
relational :: proc(rest: ^^Token, tok: ^Token) -> ^Node {
	tok := tok
	node := add(&tok, tok)
	for {
		#partial switch tok.kind {
		case .LAngle, .LtEq:
			kind := NodeKind(tok.kind)
			node = new_binary(kind, node, add(&tok, tok.next))
		case .RAngle: node = new_binary(.Lt, add(&tok, tok.next), node)
		case .GtEq: node = new_binary(.Le, add(&tok, tok.next), node)
		case:
			rest^ = tok
			return node
		}
	}
}

// add = mul ("+" mul | "-" mul)*
add :: proc(rest: ^^Token, tok: ^Token) -> ^Node {
	tok := tok
	node := mul(&tok, tok)
	for {
		#partial switch tok.kind {
		case .Plus, .Minus: node = new_binary(NodeKind(tok.kind), node, mul(&tok, tok.next))
		case:
			rest^ = tok
			return node
		}
	}
}
// mul = unary ("*" unary | "/" unary)*
mul :: proc(rest: ^^Token, tok: ^Token) -> ^Node {
	tok := tok
	node := unary(&tok, tok)
	for {
		#partial switch tok.kind {
		case .Star, .Slash: node = new_binary(NodeKind(tok.kind), node, unary(&tok, tok.next))
		case:
			rest^ = tok
			return node
		}
	}
}

// unary = ("+" | "-") unary
//       | primary
unary :: proc(rest: ^^Token, tok: ^Token) -> ^Node {
	#partial switch tok.kind {
	case .Plus: return unary(rest, tok.next)
	case .Minus: return new_unary(.Neg, unary(rest, tok.next))
	case: return primary(rest, tok)
	}
}

// primary = "(" expr ")" | ident | num
primary :: proc(rest: ^^Token, tok: ^Token) -> ^Node {
	#partial switch tok.kind {
	case .LParen:
		tok := tok
		node := expr(&tok, tok.next)
		rest^ = skip(tok, .RParen)
		return node
	case .Ident:
		var := find_var(tok)
		if var == nil {
			var = new_local_var(tok_str(tok))
		}
		rest^ = tok.next
		return new_var_node(var)
	case .Num:
		node := new_num(tok.val)
		rest^ = tok.next
		return node
	case: error_at(tok.loc, "expected an expression")
	}
}

// program = stmt*
parse :: proc(tok: ^Token) -> ^Function {
	tok := skip(tok, .LCurly)
	node := compound_stmt(&tok, tok)
	assert(tok.kind == .Eof)

	prog, _ := new(Function)
	prog^ = {
		body   = node,
		locals = locals,
	}
	return prog
}
