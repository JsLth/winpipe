// Security descriptor helpers: query the default DACL, parse an SDDL string
// (owner, group, DACL, SACL) into an R list, and build an SDDL string back
// from such a list.

#include <cpp11.hpp>
#include <windows.h>
#include <sddl.h>
#include <string>
#include <vector>

namespace {

std::string error_message(DWORD err) {
    char* buf = NULL;
    DWORD n = FormatMessageA(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
            FORMAT_MESSAGE_IGNORE_INSERTS,
        NULL, err, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        reinterpret_cast<LPSTR>(&buf), 0, NULL);
    std::string msg = n ? std::string(buf, n) : "Windows error " + std::to_string(err);
    if (buf) LocalFree(buf);
    while (!msg.empty() && (msg.back() == '\n' || msg.back() == '\r' || msg.back() == ' '))
        msg.pop_back();
    return msg;
}

std::wstring to_wide(const std::string& s) {
    if (s.empty()) return std::wstring();
    int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, NULL, 0);
    if (n <= 0) cpp11::stop("Invalid UTF-8 input.");
    std::wstring w(n - 1, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, &w[0], n);
    return w;
}

std::string to_utf8(const wchar_t* w) {
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    std::string s(n > 0 ? n - 1 : 0, '\0');
    if (n > 1) WideCharToMultiByte(CP_UTF8, 0, w, -1, &s[0], n, NULL, NULL);
    return s;
}

// Ask Windows whether the string is a valid security descriptor.
void validate_sddl(const std::string& sddl) {
    PSECURITY_DESCRIPTOR sd = NULL;
    std::wstring w = to_wide(sddl);
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
            w.c_str(), SDDL_REVISION_1, &sd, NULL)) {
        cpp11::stop("Invalid SDDL string: %s", error_message(GetLastError()).c_str());
    }
    LocalFree(sd);
}

bool starts_with(const std::string& s, size_t pos, const char* prefix) {
    return s.compare(pos, std::char_traits<char>::length(prefix), prefix) == 0;
}

// Split into two-letter tokens ("CIOI" -> "CI", "OI"). A numeric mask such
// as "0x1200a9" is kept whole.
cpp11::writable::strings tokenize_pairs(const std::string& s, const char* what) {
    cpp11::writable::strings out;
    if (s.empty()) return out;
    if (s[0] >= '0' && s[0] <= '9') {
        out.push_back(s);
        return out;
    }
    if (s.size() % 2 != 0)
        cpp11::stop("Cannot parse ACE %s '%s'.", what, s.c_str());
    for (size_t i = 0; i < s.size(); i += 2) out.push_back(s.substr(i, 2));
    return out;
}

std::string join(const cpp11::strings& x) {
    std::string out;
    for (R_xlen_t i = 0; i < x.size(); ++i) out += std::string(x[i]);
    return out;
}

// Element of a list by name; R_NilValue if missing.
SEXP get_elt(SEXP x, const char* name) {
    SEXP nm = Rf_getAttrib(x, R_NamesSymbol);
    if (TYPEOF(nm) != STRSXP) return R_NilValue;
    for (R_xlen_t i = 0; i < Rf_xlength(x); ++i)
        if (std::string(CHAR(STRING_ELT(nm, i))) == name) return VECTOR_ELT(x, i);
    return R_NilValue;
}

cpp11::strings get_strings(SEXP x, const char* name) {
    SEXP el = get_elt(x, name);
    if (el == R_NilValue) return cpp11::strings(Rf_allocVector(STRSXP, 0));
    if (TYPEOF(el) != STRSXP)
        cpp11::stop("Element `%s` must be a character vector.", name);
    return cpp11::strings(el);
}

std::string get_string(SEXP x, const char* name) {
    cpp11::strings s = get_strings(x, name);
    if (s.size() == 0) return std::string();
    if (s.size() != 1)
        cpp11::stop("Element `%s` must be a single string.", name);
    return std::string(s[0]);
}

// ---- ACL (DACL or SACL) text <-> list --------------------------------------

// Parse "<flags>(ace)(ace)..." (the text after "D:" or "S:").
cpp11::writable::list parse_acl(const std::string& s) {
    size_t pos = 0;
    cpp11::writable::strings flags;
    while (pos < s.size() && s[pos] != '(') {
        if (starts_with(s, pos, "NO_ACCESS_CONTROL")) {
            flags.push_back("NO_ACCESS_CONTROL");
            pos += 17;
        } else if (s[pos] == 'P') {
            flags.push_back("P");
            pos += 1;
        } else if (starts_with(s, pos, "AI") || starts_with(s, pos, "AR")) {
            flags.push_back(s.substr(pos, 2));
            pos += 2;
        } else {
            cpp11::stop("Unrecognised ACL flag at '%s'.", s.substr(pos).c_str());
        }
    }

    cpp11::writable::list aces;
    while (pos < s.size()) {
        if (s[pos] != '(')
            cpp11::stop("Unexpected text '%s' in ACL.", s.substr(pos).c_str());

        // Find the matching ')' (conditional ACEs contain nested parentheses).
        size_t start = pos + 1, depth = 1, i = start;
        for (; i < s.size() && depth > 0; ++i) {
            if (s[i] == '(') ++depth;
            else if (s[i] == ')') --depth;
        }
        if (depth != 0) cpp11::stop("Unbalanced parentheses in ACL.");
        std::string body = s.substr(start, i - 1 - start);
        pos = i;

        // Split into at most 7 fields on ';'; the 7th keeps any further ';'.
        std::vector<std::string> f;
        size_t b = 0;
        while (f.size() < 6) {
            size_t semi = body.find(';', b);
            if (semi == std::string::npos) break;
            f.push_back(body.substr(b, semi - b));
            b = semi + 1;
        }
        f.push_back(body.substr(b));
        if (f.size() < 6) cpp11::stop("ACE '(%s)' has fewer than 6 fields.", body.c_str());
        std::string extra = f.size() > 6 ? f[6] : "";

        using namespace cpp11::literals;
        aces.push_back(cpp11::writable::list({
            "type"_nm = f[0],
            "flags"_nm = tokenize_pairs(f[1], "flags"),
            "rights"_nm = tokenize_pairs(f[2], "rights"),
            "object_guid"_nm = f[3],
            "inherit_object_guid"_nm = f[4],
            "account"_nm = f[5],
            "extra"_nm = extra}));
    }

    using namespace cpp11::literals;
    return cpp11::writable::list({"flags"_nm = flags, "aces"_nm = aces});
}

std::string acl_string(SEXP acl, const char* name) {
    if (TYPEOF(acl) != VECSXP)
        cpp11::stop("Element `%s` must be a list with `flags` and `aces`.", name);
    std::string out = join(get_strings(acl, "flags"));

    SEXP aces = get_elt(acl, "aces");
    if (aces == R_NilValue) return out;
    if (TYPEOF(aces) != VECSXP)
        cpp11::stop("`%s$aces` must be a list.", name);

    for (R_xlen_t i = 0; i < Rf_xlength(aces); ++i) {
        SEXP ace = VECTOR_ELT(aces, i);
        if (TYPEOF(ace) != VECSXP) cpp11::stop("Each ACE must be a list.");
        out += "(" + get_string(ace, "type") + ";" +
               join(get_strings(ace, "flags")) + ";" +
               join(get_strings(ace, "rights")) + ";" +
               get_string(ace, "object_guid") + ";" +
               get_string(ace, "inherit_object_guid") + ";" +
               get_string(ace, "account");
        std::string extra = get_string(ace, "extra");
        if (!extra.empty()) out += ";" + extra;
        out += ")";
    }
    return out;
}

}  // namespace


// Default DACL of the current token (thread token if impersonating, else
// process token), as an SDDL string. This is what CreateNamedPipeW applies
// when no SECURITY_ATTRIBUTES are supplied (sddl = "").
[[cpp11::register]]
std::string cpp_default_dacl() {
    HANDLE tok = NULL;
    if (!OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &tok)) {
        if (GetLastError() != ERROR_NO_TOKEN ||
            !OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) {
            cpp11::stop(error_message(GetLastError()).c_str());
        }
    }

    DWORD len = 0;
    GetTokenInformation(tok, TokenDefaultDacl, NULL, 0, &len);
    std::vector<BYTE> buf(len);
    if (len == 0 ||
        !GetTokenInformation(tok, TokenDefaultDacl, buf.data(), len, &len)) {
        DWORD e = GetLastError();
        CloseHandle(tok);
        cpp11::stop(error_message(e).c_str());
    }
    CloseHandle(tok);

    PACL dacl = reinterpret_cast<TOKEN_DEFAULT_DACL*>(buf.data())->DefaultDacl;

    SECURITY_DESCRIPTOR sd;
    if (!InitializeSecurityDescriptor(&sd, SECURITY_DESCRIPTOR_REVISION) ||
        !SetSecurityDescriptorDacl(&sd, dacl != NULL, dacl, FALSE)) {
        cpp11::stop(error_message(GetLastError()).c_str());
    }

    LPWSTR wstr = NULL;
    if (!ConvertSecurityDescriptorToStringSecurityDescriptorW(
            &sd, SDDL_REVISION_1, DACL_SECURITY_INFORMATION, &wstr, NULL)) {
        cpp11::stop(error_message(GetLastError()).c_str());
    }
    std::string out = to_utf8(wstr);
    LocalFree(wstr);
    return out;
}

// Parse an SDDL string into
//   list(owner = chr|NULL, group = chr|NULL,
//        dacl = list(flags, aces)|NULL, sacl = list(flags, aces)|NULL)
// where each ACE is list(type, flags, rights, object_guid,
// inherit_object_guid, account, extra). Tokens are kept as written (aliases
// such as "SY" are not expanded), so cpp_sd_build() reproduces the input,
// apart from sections being emitted in the canonical order O, G, D, S.
[[cpp11::register]]
cpp11::list cpp_sd_parse(const std::string& sddl) {
    validate_sddl(sddl);

    // A ':' outside parentheses can only be a section marker (the letter
    // before it), since aliases, SIDs and ACL flags never contain one.
    std::vector<size_t> marks;
    int depth = 0;
    for (size_t i = 0; i < sddl.size(); ++i) {
        char c = sddl[i];
        if (c == '(') ++depth;
        else if (c == ')') --depth;
        else if (c == ':' && depth == 0) marks.push_back(i);
    }
    if (!marks.empty() && marks[0] != 1)
        cpp11::stop("Unexpected text before first section in SDDL string.");

    cpp11::sexp parts[4];  // owner, group, dacl, sacl; default is NULL
    bool seen[4] = {false, false, false, false};

    for (size_t k = 0; k < marks.size(); ++k) {
        char tag = sddl[marks[k] - 1];
        size_t from = marks[k] + 1;
        size_t to = (k + 1 < marks.size()) ? marks[k + 1] - 1 : sddl.size();
        std::string text = sddl.substr(from, to - from);

        int idx = tag == 'O' ? 0 : tag == 'G' ? 1 : tag == 'D' ? 2 : tag == 'S' ? 3 : -1;
        if (idx < 0) cpp11::stop("Unknown SDDL section '%c:'.", tag);
        if (seen[idx]) cpp11::stop("Duplicate SDDL section '%c:'.", tag);
        seen[idx] = true;

        if (idx < 2) parts[idx] = cpp11::as_sexp(text);
        else parts[idx] = parse_acl(text);
    }

    cpp11::writable::list out(4);
    for (int i = 0; i < 4; ++i) out[i] = parts[i];
    out.attr("names") = cpp11::writable::strings({"owner", "group", "dacl", "sacl"});
    return out;
}

// Inverse of cpp_sd_parse(). Absent (NULL) sections are omitted. The result
// is validated by Windows; an entirely empty descriptor gives "".
[[cpp11::register]]
std::string cpp_sd_build(cpp11::list sd) {
    std::string out;

    if (get_elt(sd, "owner") != R_NilValue) out += "O:" + get_string(sd, "owner");
    if (get_elt(sd, "group") != R_NilValue) out += "G:" + get_string(sd, "group");

    SEXP dacl = get_elt(sd, "dacl");
    if (dacl != R_NilValue) out += "D:" + acl_string(dacl, "dacl");

    SEXP sacl = get_elt(sd, "sacl");
    if (sacl != R_NilValue) out += "S:" + acl_string(sacl, "sacl");

    if (!out.empty()) validate_sddl(out);
    return out;
}
