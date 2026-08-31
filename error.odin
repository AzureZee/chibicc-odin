package chibicc

import "core:fmt"
import "core:os"

@(private = "file")
error_loc :: proc(loc := #caller_location) {
	cwd, _ := os.getwd(context.allocator)
	file_path, _ := os.get_relative_path(cwd, loc.file_path, context.allocator)
	fmt.eprintf("%v:%d:%d: ", file_path, loc.line, loc.column)
}

// Reports an error and exit.
error :: proc(fmt_str: string, args: ..any, loc := #caller_location) -> !  {
	error_loc(loc)
	fmt.eprintfln(fmt_str, ..args)
	os.exit(1)
}

// Reports an error location and exit.
error_at :: proc(
	pos: int,
	fmt_str: string,
	args: ..any,
	src := current_input,
	loc := #caller_location,
) -> ! {
	error_loc(loc)
	fmt.eprintfln(fmt_str, ..args)
	fmt.eprintfln("%s\n%*s^ ", src, pos, "")
	os.exit(1)
}
