const std = @import("std");
const oni = @import("oniguruma");

/// Default URL/path regex. This is used to detect URLs and file paths in terminal output.
///
/// This is here in the config package because one day the matchers will be configurable and this will be a default.
///
/// For scheme URLs, this regex is deliberately liberal in what it accepts after the scheme, including brackets and sentence-ending punctuation that are legal URL characters but that also commonly follow a URL in ordinary text (a Markdown link's closing paren, an end-of-sentence period). Rather than encode the exclusions into the regex itself, callers are expected to run a raw match through `isSchemeUrl` + `trimTrailingNoise` below, which trims trailing noise using a general bracket-balance and punctuation-trim algorithm instead of a fixed set of regex lookbehinds. This correctly handles both of the following cases with one mechanism:
///
///   "https://en.wikipedia.org/wiki/Rust_(video_game)" (keep the parens, since the trailing `)` closes an earlier unmatched `(`)
///   "(https://example.com)." (strip both the trailing `)` and `.`, since the `(` isn't part of the match at all)
///
/// The path branches below (Branch 2 and Branch 3) are unaffected by this: they decide their own trailing characters directly in their own regex (e.g. `no_trailing_colon`), since a file path's trailing-character rules are different from a URL's (a file literally named `spaces-end.` should keep its trailing period).
const url_schemes =
    \\https?://|mailto:|ftp://|file:|ssh:|git://|ssh://|tel:|magnet:|ipfs://|ipns://|gemini://|gopher://|news:
;

// Literal scheme prefixes, kept in sync with the alternatives in `url_schemes` above (with `https?://` expanded to its two literal forms). Used to decide whether a raw regex match came from the scheme URL branch, which is the only branch whose trailing noise should be trimmed by `trimTrailingNoise`; the path branches already decide their own trailing characters correctly (e.g. a file named `spaces-end.` legitimately keeps its trailing period).
const scheme_prefixes = [_][]const u8{
    "https://",  "http://", "mailto:", "ftp://",  "file:",   "ssh:",
    "git://",    "tel:",    "magnet:", "ipfs://", "ipns://", "gemini://",
    "gopher://", "news:",
};

pub fn isSchemeUrl(text: []const u8) bool {
    for (scheme_prefixes) |prefix| {
        if (std.mem.startsWith(u8, text, prefix)) return true;
    }
    return false;
}

const ipv6_url_pattern =
    \\(?:\[[:0-9a-fA-F]+(?:[:0-9a-fA-F]*)+\](?::[0-9]+)?)
;

const scheme_url_chars =
    \\[\w\-.~:/?#@!$&*+,;=%()\[\]]
;

const path_chars =
    \\[\w\-.~:\/?#@!$&*+;=%]
;

const no_trailing_colon =
    \\(?<!:)
;

const dotted_path_lookahead =
    \\(?=[\w\-.~:\/?#@!$&*+;=%]*\.)
;

const non_dotted_path_lookahead =
    \\(?![\w\-.~:\/?#@!$&*+;=%]*\.)
;

const dotted_path_space_segments =
    \\(?:(?<!:) (?!\w+:\/\/)(?!\.{0,2}\/)(?!~\/)[\w\-.~:\/?#@!$&*+;=%]*[\/.])*
;

const any_path_space_segments =
    \\(?:(?<!:) (?!\w+:\/\/)(?!\.{0,2}\/)(?!~\/)[\w\-.~:\/?#@!$&*+;=%]+)*
;

// Branch 1: URLs with explicit schemes (http, mailto, ftp, etc.).
const scheme_url_branch =
    "(?:" ++ url_schemes ++ ")" ++
    "(?:" ++ ipv6_url_pattern ++ "|" ++ scheme_url_chars ++ "+)+";

const rooted_or_relative_path_prefix =
    \\(?:\.\.\/|\.\/|(?<!\w)~\/|(?:[\w][\w\-.]*\/)*(?<!\w)\$[A-Za-z_]\w*\/|\.[\w][\w\-.]*\/|(?<![\w~\/])\/(?!\/))
;

// Branch 2: Absolute paths and dot-relative paths (/, ./, ../).
// A dotted segment is treated as file-like, while the undotted case stays
// broad to capture directory-like paths with spaces.
const rooted_or_relative_path_branch =
    rooted_or_relative_path_prefix ++
    "(?:" ++
    dotted_path_lookahead ++
    path_chars ++ "+" ++
    dotted_path_space_segments ++
    no_trailing_colon ++
    "|" ++
    non_dotted_path_lookahead ++
    path_chars ++ "+" ++
    any_path_space_segments ++
    no_trailing_colon ++
    ")";

// Branch 3: Bare relative paths such as src/config/url.zig.
const bare_relative_path_prefix =
    \\(?<!\$\d*)(?<!\w)[\w][\w\-.]*\/
;

const bare_relative_path_branch =
    dotted_path_lookahead ++
    bare_relative_path_prefix ++
    path_chars ++ "+" ++
    no_trailing_colon;

pub const regex =
    scheme_url_branch ++
    "|" ++
    rooted_or_relative_path_branch ++
    "|" ++
    bare_relative_path_branch;

const trailing_noise_chars = ",.!?;:";
const closing_brackets = ")]}";
const opening_brackets = "([{";

/// Given a raw matched span (as returned by `regex`), trims trailing characters that are noise rather than part of the URL: sentence-ending punctuation, and closing brackets that don't have a matching unclosed opening bracket earlier in the match.
pub fn trimTrailingNoise(match: []const u8) []const u8 {
    var end = match.len;
    while (end > 0) {
        const c = match[end - 1];
        if (std.mem.indexOfScalar(u8, trailing_noise_chars, c) != null) {
            end -= 1;
            continue;
        }
        if (std.mem.indexOfScalar(u8, closing_brackets, c)) |i| {
            const opener = opening_brackets[i];
            const closer = closing_brackets[i];
            var depth: i32 = 0;
            for (match[0 .. end - 1]) |ch| {
                if (ch == opener) depth += 1;
                if (ch == closer) depth -= 1;
            }
            // A positive depth means there's an earlier unclosed opener that this bracket legitimately closes, so it's part of the URL and we stop trimming here.
            if (depth > 0) break;
            end -= 1;
            continue;
        }
        break;
    }
    return match[0..end];
}

test "url regex" {
    const testing = std.testing;

    try oni.testing.ensureInit();
    var re = try oni.Regex.init(
        regex,
        .{},
        oni.Encoding.utf8,
        oni.Syntax.default,
        null,
    );
    defer re.deinit();

    // The URL cases to test what our regex matches. Feel free to add to this
    // as we find bugs or just want more coverage.
    const cases = [_]struct {
        input: []const u8,
        expect: []const u8,
        num_matches: usize = 1,
    }{
        .{
            .input = "hello https://example.com world",
            .expect = "https://example.com",
        },
        .{
            .input = "https://example.com/foo(bar) more",
            .expect = "https://example.com/foo(bar)",
        },
        .{
            .input = "https://example.com/foo(bar)baz more",
            .expect = "https://example.com/foo(bar)baz",
        },
        .{
            .input = "Link inside (https://example.com) parens",
            .expect = "https://example.com",
        },
        .{
            .input = "Some text before it (see the docs here: https://example.com) and some text after",
            .expect = "https://example.com",
        },
        .{
            .input = "(https://example.com).",
            .expect = "https://example.com",
        },
        .{
            .input = "(https://example.com)!",
            .expect = "https://example.com",
        },
        .{
            .input = "(https://example.com);",
            .expect = "https://example.com",
        },
        .{
            .input = "(https://example.com):",
            .expect = "https://example.com",
        },
        .{
            .input = "[docs](https://example.com)!",
            .expect = "https://example.com",
        },
        .{
            .input = "[docs](https://example.com);",
            .expect = "https://example.com",
        },
        .{
            .input = "[docs](https://example.com):",
            .expect = "https://example.com",
        },
        .{
            .input = "(https://example.com)!.",
            .expect = "https://example.com",
        },
        .{
            .input = "TEXT: [issue filed](https://example.com/issues/123).",
            .expect = "https://example.com/issues/123",
        },
        .{
            .input = "did you see [this](https://example.com/issues/123)?",
            .expect = "https://example.com/issues/123",
        },
        // Genuinely nested parens, correctly kept in full via bracket-depth counting.
        .{
            .input = "https://example.com/Rust_(foo(bar))",
            .expect = "https://example.com/Rust_(foo(bar))",
        },
        // A mismatched closing bracket with no opener of its own type is correctly stripped, rather than kept as if it were a valid pair.
        .{
            .input = "https://example.com/foo(bar] more",
            .expect = "https://example.com/foo(bar",
        },
        .{
            .input = "Link period https://example.com. More text.",
            .expect = "https://example.com",
        },
        .{
            .input = "Link trailing comma https://example.com, more text.",
            .expect = "https://example.com",
        },
        .{
            .input = "Check this out https://example.com! Great, right?",
            .expect = "https://example.com",
        },
        .{
            .input = "Have you seen https://example.com? It's great.",
            .expect = "https://example.com",
        },
        .{
            .input = "See https://example.com; it covers this well.",
            .expect = "https://example.com",
        },
        .{
            .input = "Full docs at https://example.com: read them",
            .expect = "https://example.com",
        },
        .{
            .input = "https://example.com!.",
            .expect = "https://example.com",
        },
        .{
            .input = "https://example.com?!",
            .expect = "https://example.com",
        },
        .{
            .input = "Link in double quotes \"https://example.com\" and more",
            .expect = "https://example.com",
        },
        .{
            .input = "Link in single quotes 'https://example.com' and more",
            .expect = "https://example.com",
        },
        .{
            .input = "some file with https://google.com https://duckduckgo.com links.",
            .expect = "https://google.com",
        },
        .{
            .input = "and links in it. links https://yahoo.com mailto:test@example.com ssh://1.2.3.4",
            .expect = "https://yahoo.com",
        },
        .{
            .input = "also match http://example.com non-secure links",
            .expect = "http://example.com",
        },
        .{
            .input = "match tel://+12123456789 phone numbers",
            .expect = "tel://+12123456789",
        },
        .{
            .input = "match with query url https://example.com?query=1&other=2 and more text.",
            .expect = "https://example.com?query=1&other=2",
        },
        .{
            .input = "url with dashes [mode 2027](https://github.com/contour-terminal/terminal-unicode-core) for better unicode support",
            .expect = "https://github.com/contour-terminal/terminal-unicode-core",
        },
        .{
            .input = "dot.http://example.com",
            .expect = "http://example.com",
        },
        // weird characters in URL
        .{
            .input = "weird characters https://example.com/~user/?query=1&other=2#hash and more",
            .expect = "https://example.com/~user/?query=1&other=2#hash",
        },
        // square brackets in URL
        .{
            .input = "square brackets https://example.com/[foo] and more",
            .expect = "https://example.com/[foo]",
        },
        // square bracket following url
        .{
            .input = "[13]:TooManyStatements: TempFile#assign_temp_file_to_entity has approx 7 statements [https://example.com/docs/Too-Many-Statements.md]",
            .expect = "https://example.com/docs/Too-Many-Statements.md",
        },
        // remaining URL schemes tests
        .{
            .input = "match ftp://example.com ftp links",
            .expect = "ftp://example.com",
        },
        .{
            .input = "match file://example.com file links",
            .expect = "file://example.com",
        },
        .{
            .input = "match ssh://example.com ssh links",
            .expect = "ssh://example.com",
        },
        .{
            .input = "match git://example.com git links",
            .expect = "git://example.com",
        },
        .{
            .input = "/tmp/test.txt http://www.google.com",
            .expect = "/tmp/test.txt",
        },
        .{
            .input = "match tel:+18005551234 tel links",
            .expect = "tel:+18005551234",
        },
        .{
            .input = "match magnet:?xt=urn:btih:1234567890 magnet links",
            .expect = "magnet:?xt=urn:btih:1234567890",
        },
        .{
            .input = "match ipfs://QmSomeHashValue ipfs links",
            .expect = "ipfs://QmSomeHashValue",
        },
        .{
            .input = "match ipns://QmSomeHashValue ipns links",
            .expect = "ipns://QmSomeHashValue",
        },
        .{
            .input = "match gemini://example.com gemini links",
            .expect = "gemini://example.com",
        },
        .{
            .input = "match gopher://example.com gopher links",
            .expect = "gopher://example.com",
        },
        .{
            .input = "match news:comp.infosystems.www.servers.unix news links",
            .expect = "news:comp.infosystems.www.servers.unix",
        },
        .{
            .input = "/Users/ghostty.user/code/example.py",
            .expect = "/Users/ghostty.user/code/example.py",
        },
        .{
            .input = "/Users/ghostty.user/code/../example.py",
            .expect = "/Users/ghostty.user/code/../example.py",
        },
        .{
            .input = "/Users/ghostty.user/code/../example.py hello world",
            .expect = "/Users/ghostty.user/code/../example.py",
        },
        .{
            .input = "../example.py",
            .expect = "../example.py",
        },
        .{
            .input = "../example.py ",
            .expect = "../example.py",
        },
        .{
            .input = "first time ../example.py contributor ",
            .expect = "../example.py",
        },
        .{
            .input = "[link](/home/user/ghostty.user/example)",
            .expect = "/home/user/ghostty.user/example",
        },
        // IPv6 URL tests - Basic tests
        .{
            .input = "Serving HTTP on :: port 8000 (http://[::]:8000/)",
            .expect = "http://[::]:8000/",
        },
        .{
            .input = "IPv6 address https://[2001:db8::1]:8080/path",
            .expect = "https://[2001:db8::1]:8080/path",
        },
        .{
            .input = "IPv6 localhost http://[::1]:3000",
            .expect = "http://[::1]:3000",
        },
        .{
            .input = "Complex IPv6 https://[2001:db8:85a3:8d3:1319:8a2e:370:7348]:443/",
            .expect = "https://[2001:db8:85a3:8d3:1319:8a2e:370:7348]:443/",
        },
        // IPv6 URL tests - URLs with paths and query parameters
        .{
            .input = "IPv6 with path https://[2001:db8::1]/path/to/resource",
            .expect = "https://[2001:db8::1]/path/to/resource",
        },
        .{
            .input = "IPv6 with query https://[2001:db8::1]:8080/api?param=value&other=123",
            .expect = "https://[2001:db8::1]:8080/api?param=value&other=123",
        },
        // IPv6 URL tests - Compressed forms
        .{
            .input = "IPv6 compressed http://[2001:db8::]:80/",
            .expect = "http://[2001:db8::]:80/",
        },
        .{
            .input = "IPv6 multiple zeros http://[2001:0:0:0:0:0:0:1]",
            .expect = "http://[2001:0:0:0:0:0:0:1]",
        },
        // IPv6 URL tests - Special cases
        .{
            .input = "IPv6 link-local https://[fe80::1234:5678:9abc]",
            .expect = "https://[fe80::1234:5678:9abc]",
        },
        .{
            .input = "IPv6 multicast http://[ff02::1]/stream",
            .expect = "http://[ff02::1]/stream",
        },
        // IPv6 URL tests - Mixed scenarios
        .{
            .input = "IPv6 in markdown [link](http://[2001:db8::1]/docs)",
            .expect = "http://[2001:db8::1]/docs",
        },
        // Trailing whitespace isn't part of a detected file path.
        .{
            .input = "./spaces-end.   ",
            .expect = "./spaces-end.",
        },
        // File paths with internal spaces
        .{
            .input = "./space middle",
            .expect = "./space middle",
        },
        .{
            .input = "../test folder/file.txt",
            .expect = "../test folder/file.txt",
        },
        .{
            .input = "/tmp/test folder/file.txt",
            .expect = "/tmp/test folder/file.txt",
        },
        .{
            .input = "/tmp/test  folder/file.txt",
            .expect = "/tmp/test",
        },
        // unified diff lines
        .{
            .input = "diff --git a/src/font/shaper/harfbuzz.zig b/src/font/shaper/harfbuzz.zig",
            .expect = "a/src/font/shaper/harfbuzz.zig",
        },
        // Two space-separated absolute paths should match only the first
        .{
            .input = "/tmp/foo /tmp/bar",
            .expect = "/tmp/foo",
        },
        .{
            .input = "/tmp/foo.txt /tmp/bar.txt",
            .expect = "/tmp/foo.txt",
        },
        // Bare relative file paths (no ./ or ../ prefix)
        .{
            .input = "src/config/url.zig",
            .expect = "src/config/url.zig",
        },
        .{
            .input = "app/folder/file.rb:1",
            .expect = "app/folder/file.rb:1",
        },
        .{
            .input = "modified:   src/config/url.zig",
            .expect = "src/config/url.zig",
        },
        .{
            .input = "lib/ghostty/terminal.zig:42:10",
            .expect = "lib/ghostty/terminal.zig:42:10",
        },
        .{
            .input = "some-pkg/src/file.txt more text",
            .expect = "some-pkg/src/file.txt",
        },
        // comma should match substrings
        .{
            .input = "src/foo.c,baz.txt",
            .expect = "src/foo.c",
        },
        .{
            .input = "~/foo/bar.txt",
            .expect = "~/foo/bar.txt",
        },
        .{
            .input = "open ~/Documents/notes.md please",
            .expect = "~/Documents/notes.md",
        },
        .{
            .input = "~/.config/ghostty/config",
            .expect = "~/.config/ghostty/config",
        },
        .{
            .input = "directory: ~/src/ghostty-org/ghostty",
            .expect = "~/src/ghostty-org/ghostty",
        },
        .{
            .input = "$HOME/src/config/url.zig",
            .expect = "$HOME/src/config/url.zig",
        },
        .{
            .input = "project dir: $PWD/src/ghostty/main.zig",
            .expect = "$PWD/src/ghostty/main.zig",
        },
        // $VAR mid-path should match fully, not partially from the $
        .{
            .input = "foo/$BAR/baz",
            .expect = "foo/$BAR/baz",
        },
        .{
            .input = ".foo/bar/$VAR",
            .expect = ".foo/bar/$VAR",
        },
        .{
            .input = ".config/ghostty/config",
            .expect = ".config/ghostty/config",
        },
        .{
            .input = "loaded from .local/share/ghostty/state.db now",
            .expect = ".local/share/ghostty/state.db",
        },
        .{
            .input = "../some/where",
            .expect = "../some/where",
        },
        // comma-separated file paths
        .{
            .input = "  - shared/src/foo/SomeItem.m:12, shared/src/",
            .expect = "shared/src/foo/SomeItem.m:12",
        },
        // mid-string dot should not partially match but fully
        .{
            .input = "foo.local/share",
            .expect = "foo.local/share",
        },
        // numeric directory should match fully
        .{
            .input = "2024/report.txt",
            .expect = "2024/report.txt",
        },
        // comma should stop matching in spaced path segments
        .{
            .input = "./foo bar,baz",
            .expect = "./foo bar",
        },
        .{
            .input = "/tmp/foo bar,baz",
            .expect = "/tmp/foo bar",
        },
        // trailing colon should not be part of the path
        .{
            .input = "./.config/ghostty: Needs upstream (main)",
            .expect = "./.config/ghostty",
        },
        .{
            .input = "./Downloads: Operation not permitted",
            .expect = "./Downloads",
        },
    };

    for (cases) |case| {
        //std.debug.print("input: {s}\n", .{case.input});
        //std.debug.print("match: {s}\n", .{case.expect});
        var reg = try re.search(case.input, .{});
        //std.debug.print("count: {d}\n", .{@as(usize, reg.count())});
        //std.debug.print("starts: {d}\n", .{reg.starts()});
        //std.debug.print("ends: {d}\n", .{reg.ends()});
        defer reg.deinit();
        try testing.expectEqual(@as(usize, case.num_matches), reg.count());
        const raw_match = case.input[@intCast(reg.starts()[0])..@intCast(reg.ends()[0])];
        const match = if (isSchemeUrl(raw_match)) trimTrailingNoise(raw_match) else raw_match;
        try testing.expectEqualStrings(case.expect, match);
    }

    const no_match_cases = [_][]const u8{
        // bare relative paths without any dot should not match as file paths
        "input/output",
        "foo/bar",
        // $-numeric character should not match
        "$10/bar",
        "$10/$20",
        "$10/bar.txt",
        // comma should not let dot detection look past it
        "foo/bar,baz.txt",
        // $VAR should not match mid-word
        "foo$BAR/baz.txt",
        // ~ should not match mid-word
        "foo~/bar.txt",
        // double-slash comments are not paths
        "// foo bar",
        "//foo",
    };
    for (no_match_cases) |input| {
        var result = re.search(input, .{});
        if (result) |*reg| {
            reg.deinit();
            return error.TestUnexpectedResult;
        } else |_| {}
    }
}

test "isSchemeUrl recognizes a scheme URL" {
    const testing = std.testing;
    try testing.expect(isSchemeUrl("https://example.com"));
}

test "isSchemeUrl rejects a file path" {
    const testing = std.testing;
    try testing.expect(!isSchemeUrl("./spaces-end."));
}

test "trimTrailingNoise strips a trailing period" {
    const testing = std.testing;
    try testing.expectEqualStrings(
        "https://example.com",
        trimTrailingNoise("https://example.com."),
    );
}

test "trimTrailingNoise strips a trailing comma" {
    const testing = std.testing;
    try testing.expectEqualStrings(
        "https://example.com",
        trimTrailingNoise("https://example.com,"),
    );
}

test "trimTrailingNoise keeps a trailing paren that closes an earlier open" {
    const testing = std.testing;
    try testing.expectEqualStrings(
        "https://en.wikipedia.org/wiki/Rust_(video_game)",
        trimTrailingNoise("https://en.wikipedia.org/wiki/Rust_(video_game)"),
    );
}

test "trimTrailingNoise strips a trailing paren with no matching open" {
    const testing = std.testing;
    try testing.expectEqualStrings(
        "https://example.com",
        trimTrailingNoise("https://example.com)"),
    );
}

test "trimTrailingNoise strips a stacked unmatched paren then period" {
    const testing = std.testing;
    try testing.expectEqualStrings(
        "https://example.com/issues/123",
        trimTrailingNoise("https://example.com/issues/123)."),
    );
}

test "trimTrailingNoise keeps a matched paren but strips a trailing period after it" {
    const testing = std.testing;
    try testing.expectEqualStrings(
        "https://example.com/foo(bar)",
        trimTrailingNoise("https://example.com/foo(bar)."),
    );
}

test "trimTrailingNoise keeps a matched square bracket" {
    const testing = std.testing;
    try testing.expectEqualStrings(
        "https://example.com/[foo]",
        trimTrailingNoise("https://example.com/[foo]"),
    );
}

test "trimTrailingNoise strips an unmatched square bracket" {
    const testing = std.testing;
    try testing.expectEqualStrings(
        "https://example.com",
        trimTrailingNoise("https://example.com]"),
    );
}
