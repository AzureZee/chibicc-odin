package chibicc

import "core:strconv"
import "core:unicode"
import "core:unicode/utf8"

TokenKind :: enum {
	Ident  = 'a' + '_', // Identifiers
	LParen = '(',
	RParen = ')',
	Star   = '*',
	Slash  = '/',
	Plus   = '+',
	Minus  = '-',
	LAngle = '<',
	RAngle = '>',
	LtEq   = '<' + '=',
	GtEq   = '>' + '=',
	Bang   = '!',
	NotEq  = '!' + '=',
	EqEq   = '=' * 2,
	Equal  = '=',
	Semi   = ';',
	Num    = 48, // ascii number 0
	Eof    = 0, // NUL '\0'
}
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
tokenize :: proc(str: string) -> ^Token {
	current_input = str
	head := Token{}
	cur := &head
	i := 0
	str_len := len(str)
	for i < str_len {
		ch := utf8.rune_at_pos(str, i)
		switch {
		case unicode.is_space(ch): i += 1
		case unicode.is_digit(ch):
			val, len := parse_number(str[i:])
			cur.next = new_token(.Num, i)
			cur = cur.next
			cur.val = val
			i += len
		case:
			tok_len := 1
			tok_kind := TokenKind(ch)
			switch ch {
			case 'a' ..= 'z', 'A' ..= 'Z', '_':
				start := i
				i += 1
				for is_ident(utf8.rune_at_pos(str, i)) {i += 1}
				cur.next = new_token(.Ident, start, i - start)
				cur = cur.next
				continue
			case ';':
			case '(', ')':
			case '+', '-', '*', '/':
			case '=', '!', '<', '>':
				inc_i := i + 1
				if (inc_i < str_len) && utf8.rune_at_pos(str, inc_i) == '=' {
					tok_len = 2
					tok_kind = TokenKind(ch + '=')
				}
			case: error_at(i, "invalid token")
			}
			cur.next = new_token(tok_kind, i, tok_len)
			cur = cur.next
			i += tok_len
		}
	}
	cur.next = new_token(.Eof, i)
	cur = cur.next
	return head.next
}
