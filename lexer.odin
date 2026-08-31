package chibicc

import "core:strconv"
import "core:unicode/utf8"

TokenKind :: enum {
	LParen = '(',
	RParen = ')',
	LCurly = '{',
	RCurly = '}',
	Star   = '*',
	Slash  = '/',
	Plus   = '+',
	Minus  = '-',
	LAngle = '<',
	RAngle = '>',
	Bang   = '!',
	Equal  = '=',
	LtEq   = -'<', // <=
	GtEq   = -'>', // >=
	NotEq  = -'!', // !=
	EqEq   = -'=', // ==
	Semi   = ';',
	Num    = '0', // ascii number 0
	Eof    = 0, // NUL '\0'
	Ident  = 999, // Identifiers or Keywords
	K_if   = __KEYWORD,
	K_else,
	K_for,
	K_return,
}
__KEYWORD :: 1000

Token :: struct {
	next: ^Token,
	kind: TokenKind,
	val : int, // If kind is TK_NUM, its value
	loc : int, // Token location
	len : int, // Token length
}
new_token :: proc(kind: TokenKind, loc: int, len := 1) -> ^Token {
	tok, _ := new(Token)
	tok^ = {
		kind = kind,
		loc  = loc,
		len  = len,
	}
	return tok
}

// Input string
current_input: string
tok_str :: proc(tok: ^Token) -> string {
	return current_input[tok.loc:tok.loc + tok.len]
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
is_ident :: proc(ch: rune) -> bool {
	switch ch {
	case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '_': return true
	case: return false
	}
}

ident2keyword :: proc(ident: string) -> TokenKind {
	keywords :: [?]string{"if", "else", "for", "return"}

	for kw, i in keywords {
		if ident == kw {
			return TokenKind(i + __KEYWORD)
		}
	}
	return .Ident
}

tokenize :: proc(str: string) -> ^Token {
	current_input = str
	head := Token{}
	cur := &head
	i := 0
	str_len := len(str)
	for i < str_len {
		ch := utf8.rune_at_pos(str, i)
		tok_len := 1
		tok_kind := TokenKind(ch)
		tok_val: int
		switch ch {
		case '\t', '\n', '\v', '\f', '\r', ' ':
			i += 1
			continue
		case '0' ..= '9':
			tok_val, tok_len = parse_number(str[i:])
			tok_kind = .Num
		case 'a' ..= 'z', 'A' ..= 'Z', '_':
			start := i
			end := i + 1
			for is_ident(utf8.rune_at_pos(str, end)) do end += 1
			tok_len = end - start
			tok_kind = ident2keyword(str[start:end])
		case ';':
		case '(', ')', '{', '}':
		case '+', '-', '*', '/':
		case '=', '!', '<', '>':
			inc_i := i + 1
			// <=, >=, !=, ==
			if (inc_i < str_len) && utf8.rune_at_pos(str, inc_i) == '=' {
				tok_len = 2
				tok_kind = TokenKind(-ch)
			}
		case: error_at(i, "invalid token")
		}
		cur.next = new_token(tok_kind, i, tok_len)
		cur = cur.next
		cur.val = tok_val
		i += tok_len
	}
	cur.next = new_token(.Eof, i)
	cur = cur.next
	return head.next
}
