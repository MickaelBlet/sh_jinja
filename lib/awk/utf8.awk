# utf8.awk - code point aware string helpers (awk runs with LC_ALL=C, so
# builtin length/substr work on bytes).

function u8_init(    i) {
	for (i = 1; i < 256; i++) {
		if (i < 128) U8W[CHR[i]] = 1
		else if (i < 192) U8W[CHR[i]] = 0
		else if (i < 224) U8W[CHR[i]] = 2
		else if (i < 240) U8W[CHR[i]] = 3
		else U8W[CHR[i]] = 4
	}
	u8_caseinit()
}

# case mapping tables for common non-ASCII scripts (Latin-1, Latin
# Extended-A, Greek, Cyrillic); U8UP / U8LO map a UTF-8 char to its pair
function u8_casepair(up, lo) {
	U8UP[u8_enc(lo)] = u8_enc(up)
	U8LO[u8_enc(up)] = u8_enc(lo)
}

function u8_caseinit(    i) {
	for (i = 192; i <= 222; i++) if (i != 215) u8_casepair(i, i + 32)
	for (i = 256; i < 312; i += 2) if (i != 304) u8_casepair(i, i + 1)
	for (i = 313; i < 329; i += 2) u8_casepair(i, i + 1)
	for (i = 330; i < 376; i += 2) u8_casepair(i, i + 1)
	for (i = 377; i < 383; i += 2) u8_casepair(i, i + 1)
	u8_casepair(376, 255)
	U8UP[u8_enc(223)] = "SS"
	U8UP[u8_enc(305)] = "I"
	U8LO[u8_enc(304)] = "i" u8_enc(775)
	U8UP[u8_enc(383)] = "S"
	U8UP[u8_enc(181)] = u8_enc(924)
	for (i = 913; i <= 937; i++) if (i != 930) u8_casepair(i, i + 32)
	U8UP[u8_enc(962)] = u8_enc(931)
	u8_casepair(902, 940)
	for (i = 904; i <= 906; i++) u8_casepair(i, i + 37)
	u8_casepair(908, 972)
	u8_casepair(910, 973)
	u8_casepair(911, 974)
	for (i = 1040; i <= 1071; i++) u8_casepair(i, i + 32)
	for (i = 1024; i <= 1039; i++) u8_casepair(i, i + 80)
	for (i = 1120; i < 1154; i += 2) u8_casepair(i, i + 1)
	for (i = 1162; i < 1216; i += 2) u8_casepair(i, i + 1)
}

function u8_upper(s,    n, arr, i, out, c) {
	if (u8_isascii(s)) return toupper(s)
	n = u8_chars(s, arr)
	out = ""
	for (i = 1; i <= n; i++) {
		c = arr[i]
		out = out "" ((c in U8UP) ? U8UP[c] : toupper(c))
	}
	return out
}

function u8_lower(s,    n, arr, i, out, c) {
	if (u8_isascii(s)) return tolower(s)
	n = u8_chars(s, arr)
	out = ""
	for (i = 1; i <= n; i++) {
		c = arr[i]
		out = out "" ((c in U8LO) ? U8LO[c] : tolower(c))
	}
	return out
}

function u8_iscased(c) { return c ~ /^[A-Za-z]$/ || (c in U8LO) || (c in U8UP) }

function u8_isascii(s) { return s !~ /[\200-\377]/ }

function u8_len(s,    t, n) {
	if (u8_isascii(s)) return length(s)
	t = s
	n = gsub(/[\200-\277]/, "", t)
	return length(s) - n
}

# split s into code points: arr[1..n]; returns n
function u8_chars(s, arr,    n, i, l, w) {
	n = 0
	l = length(s)
	if (u8_isascii(s)) {
		for (i = 1; i <= l; i++) arr[++n] = substr(s, i, 1)
		return n
	}
	i = 1
	while (i <= l) {
		w = U8W[substr(s, i, 1)]
		if (w < 1) w = 1
		arr[++n] = substr(s, i, w)
		i += w
	}
	return n
}

# substring by code points, 1-based start, len chars (len < 0: to end)
function u8_sub(s, start, len,    arr, n, i, r, e) {
	if (u8_isascii(s)) return len < 0 ? substr(s, start) : substr(s, start, len)
	n = u8_chars(s, arr)
	e = len < 0 ? n : start + len - 1
	if (e > n) e = n
	r = ""
	for (i = start < 1 ? 1 : start; i <= e; i++) r = r arr[i]
	return r
}

# encode a code point as UTF-8
function u8_enc(cp) {
	if (cp < 128) return CHR[cp]
	if (cp < 2048) return CHR[192 + int(cp / 64)] CHR[128 + cp % 64]
	if (cp < 65536) return CHR[224 + int(cp / 4096)] CHR[128 + int(cp / 64) % 64] CHR[128 + cp % 64]
	return CHR[240 + int(cp / 262144)] CHR[128 + int(cp / 4096) % 64] CHR[128 + int(cp / 64) % 64] CHR[128 + cp % 64]
}

# decode the first code point of a UTF-8 char
function u8_ord(c,    w, cp, i) {
	w = U8W[substr(c, 1, 1)]
	if (w <= 1) return ORD[substr(c, 1, 1)]
	cp = ORD[substr(c, 1, 1)] % (w == 2 ? 32 : (w == 3 ? 16 : 8))
	for (i = 2; i <= w; i++) cp = cp * 64 + ORD[substr(c, i, 1)] % 64
	return cp
}

function u8_hexval(h,    i, n, c) {
	n = 0
	h = tolower(h)
	for (i = 1; i <= length(h); i++) {
		c = index(HEXD, substr(h, i, 1))
		if (!c) return -1
		n = n * 16 + c - 1
	}
	return n
}
