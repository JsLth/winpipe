// An R connection backed by a Windows named pipe.

#include <cpp11.hpp>
#include <windows.h>
#include <sddl.h>
#include <algorithm>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <cwchar>

#define class class_
#define private private_
#include <R_ext/Connections.h>
#undef class
#undef private

#if R_CONNECTIONS_VERSION != 1
#error "Unsupported R connections API version"
#endif

// windows.h defines TRUE/FALSE as ints, which do not convert to Rboolean
static const Rboolean RB_TRUE = static_cast<Rboolean>(1);
static const Rboolean RB_FALSE = static_cast<Rboolean>(0);

namespace {

constexpr DWORD kPollMs = 100;  // how often waits check for R interrupts

struct PipeState {
    HANDLE h = INVALID_HANDLE_VALUE;
    HANDLE ev = NULL;
    std::wstring name;
    std::wstring sddl;
    bool server = true;
    double max_instances = INFINITY;
    DWORD timeout_ms = 60000;
    unsigned char buf[4096];
    size_t pos = 0, len = 0;
};

PipeState* state_of(Rconnection con) {
    return static_cast<PipeState*>(con->private_);
}

DWORD seconds_to_ms(double s) {
    if (R_IsNA(s) || std::isnan(s) || s < 0) {
        cpp11::stop("Timeout must be non-negative.");
    }

    if (!std::isfinite(s) || s < 0) return INFINITE;
    double ms = s * 1000.0;
    return ms >= 4294967294.0 ? INFINITE : static_cast<DWORD>(ms);
}

std::string GetErrorMessage(DWORD err) {
    LPWSTR buf = nullptr;

    DWORD size = FormatMessageW(
        FORMAT_MESSAGE_ALLOCATE_BUFFER |
        FORMAT_MESSAGE_FROM_SYSTEM |
        FORMAT_MESSAGE_IGNORE_INSERTS,
        nullptr,
        err,
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        (LPWSTR)&buf,
        0,
        nullptr
    );

    if (size == 0 || !buf) return "Unknown error";

    int req = WideCharToMultiByte(CP_UTF8, 0, buf, -1, nullptr, 0, nullptr, nullptr);
    std::string msg(req - 1, '\0');
    WideCharToMultiByte(CP_UTF8, 0, buf, -1, msg.data(), req, nullptr, nullptr);
    LocalFree(buf);
    while (!msg.empty() && (msg.back() == '\n' || msg.back() == '\r')) {
        msg.pop_back();
    }
    return msg;
}

[[noreturn]] void r_errorf(const char* fmt, ...) {
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    Rf_error("%s", buf);
}

[[noreturn]] void win_error(DWORD err = GetLastError(), const char* what = nullptr) {
    char buf[512];
    {
        std::string m = GetErrorMessage(err);
        if (what != nullptr) {
            snprintf(buf, sizeof(buf), "%.31s: %s", what, m.c_str());
        } else {
            snprintf(buf, sizeof(buf), "%s", m.c_str());
        }
    }
    Rf_error("%s", buf);
}

static std::wstring utf8_to_wstring(const std::string& input) {
    if (input.empty()) {
        return std::wstring();
    }

    int required = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        input.data(),
        static_cast<int>(input.size()),
        nullptr,
        0
    );

    if (required <= 0) {
        cpp11::stop(GetErrorMessage(GetLastError()).c_str());
    }

    std::wstring output(required, L'\0');

    MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        input.data(),
        static_cast<int>(input.size()),
        output.data(),
        required
    );

    return output;
}

std::string wstring_to_utf8(const std::wstring& input) {
    if (input.empty())
        return {};

    int n = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        input.data(),
        static_cast<int>(input.size()),
        nullptr,
        0,
        nullptr,
        nullptr
    );

    if (n <= 0) Rf_error(GetErrorMessage(GetLastError()).c_str());

    std::string result(n, '\0');

    if (WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        input.data(),
        static_cast<int>(input.size()),
        result.data(),
        n,
        nullptr,
        nullptr) <= 0
    ) {
        Rf_error(GetErrorMessage(GetLastError()).c_str());
    }

    return result;
}

// ---- Overlapped I/O with timeout ---------------------

// non-blocking read with nothing available yet.
enum class IoStatus { Ok, Eof, Timeout, Interrupted, Error, Empty };

struct IoResult {
    IoStatus status;
    DWORD bytes;
    DWORD err;
};

void check_interrupt_fn(void*) { R_CheckUserInterrupt(); }

// R_CheckUserInterrupt() longjmps on interrupt; run it in a toplevel context so
// control returns here and the pending I/O can be cancelled first.
bool interrupted() { return !R_ToplevelExec(check_interrupt_fn, NULL); }

IoStatus classify(DWORD e) {
    if (e == ERROR_BROKEN_PIPE ||
        e == ERROR_HANDLE_EOF ||
        e == ERROR_PIPE_NOT_CONNECTED ||
        e == ERROR_NO_DATA)
        return IoStatus::Eof;
    return IoStatus::Error;
}

// Completes an operation; `issued` is the return value of the Win32 call, which
// must have been given `ov`. Leaves no I/O pending on return.
IoResult finish_io(HANDLE h, OVERLAPPED* ov, BOOL issued, DWORD timeout_ms) {
    IoResult r{IoStatus::Ok, 0, 0};

    if (!issued) {
        DWORD e = GetLastError();
        if (e != ERROR_IO_PENDING) {
            r.status = classify(e);
            r.err = e;
            return r;
        }

        ULONGLONG start = GetTickCount64();
        IoStatus reason = IoStatus::Ok;
        for (;;) {
            DWORD slice = kPollMs;
            if (timeout_ms != INFINITE) {
                ULONGLONG elapsed = GetTickCount64() - start;
                if (elapsed >= timeout_ms) {
                    reason = IoStatus::Timeout;
                    break; 
                }
                slice = static_cast<DWORD>(std::min<ULONGLONG>(kPollMs, timeout_ms - elapsed));
            }
            DWORD w = WaitForSingleObject(ov->hEvent, slice);
            if (w == WAIT_OBJECT_0) break;
            if (w != WAIT_TIMEOUT) {
                reason = IoStatus::Error;
                r.err = GetLastError();
                break; 
            }
            if (interrupted()) {
                reason = IoStatus::Interrupted;
                break; 
            }
        }

        if (reason != IoStatus::Ok) {
            CancelIoEx(h, ov);
            
            // Wait for the cancel to land; bytes moved before it are kept.
            if (GetOverlappedResult(h, ov, &r.bytes, TRUE)) {
                r.status = IoStatus::Ok;  // finished before the cancel took effect
            } else {
                DWORD e2 = GetLastError();
                r.err = e2;
                r.status = (e2 == ERROR_OPERATION_ABORTED) ? reason : classify(e2);
            }
            return r;
        }
    }

    if (!GetOverlappedResult(h, ov, &r.bytes, FALSE)) {
        r.err = GetLastError();
        r.status = classify(r.err);
    }
    return r;
}

IoResult io_read(PipeState* s, void* dst, DWORD n) {
    ResetEvent(s->ev);
    OVERLAPPED ov;
    std::memset(&ov, 0, sizeof(ov));
    ov.hEvent = s->ev;
    BOOL ok = ReadFile(s->h, dst, n, NULL, &ov);
    return finish_io(s->h, &ov, ok, s->timeout_ms);
}

IoResult io_write(PipeState* s, const void* src, DWORD n) {
    ResetEvent(s->ev);
    OVERLAPPED ov;
    std::memset(&ov, 0, sizeof(ov));
    ov.hEvent = s->ev;
    BOOL ok = WriteFile(s->h, src, n, NULL, &ov);
    return finish_io(s->h, &ov, ok, s->timeout_ms);
}

IoResult io_connect(PipeState* s) {
    ResetEvent(s->ev);
    OVERLAPPED ov;
    std::memset(&ov, 0, sizeof(ov));
    ov.hEvent = s->ev;
    s->pos = s->len = 0;
    if (ConnectNamedPipe(s->h, &ov)) {
        return IoResult{IoStatus::Ok, 0, 0};
    }
    DWORD e = GetLastError();
    if (e == ERROR_PIPE_CONNECTED) return IoResult{IoStatus::Ok, 0, 0};
    SetLastError(e);
    return finish_io(s->h, &ov, FALSE, s->timeout_ms);
}

// Raises an R error for a failed accept. No C++ objects with destructors alive.
[[noreturn]] void accept_failed(const PipeState* s, const IoResult& r) {
    if (r.status == IoStatus::Timeout)
        r_errorf("Timed out after %.1f s waiting for a client", s->timeout_ms / 1000.0);
    if (r.status == IoStatus::Interrupted)
        r_errorf("Interrupted while waiting for a client");
    win_error(r.err);
}

// ---- Handle creation (non-throwing; callers raise the R error) -------------

HANDLE create_server_handle(const std::wstring& name, const std::wstring& sddl,
                            const double max_instances, DWORD* err, const char** stage) {
    SECURITY_ATTRIBUTES sa, *psa = NULL;
    PSECURITY_DESCRIPTOR sd = NULL;

    if (!sddl.empty()) {
        if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
                sddl.c_str(), SDDL_REVISION_1, &sd, NULL)) {
            *err = GetLastError();
            *stage = "SDDL invalid";
            return INVALID_HANDLE_VALUE;
        }
        sa.nLength = sizeof(sa);
        sa.lpSecurityDescriptor = sd;
        sa.bInheritHandle = FALSE;
        psa = &sa;
    }

    DWORD mi = PIPE_UNLIMITED_INSTANCES;
    if (std::isfinite(max_instances) && max_instances >= 1 && max_instances <= 254) {
        mi = static_cast<DWORD>(max_instances);
    };

    HANDLE h = CreateNamedPipeW(
        name.c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
        mi, 1 << 20, 1 << 20, 0, psa);

    if (h == INVALID_HANDLE_VALUE) {
        *err = GetLastError();
        *stage = "CreateNamedPipe failed";
    }
    if (sd) LocalFree(sd);
    return h;
}

// When every instance is busy, wait for one to free up in short slices so that
// R interrupts are honoured and the overall timeout is respected.
HANDLE open_client_handle(const std::wstring& name, DWORD timeout_ms, DWORD* err,
                          bool* was_interrupted) {
    *was_interrupted = false;
    const ULONGLONG start = GetTickCount64();
    for (;;) {
        HANDLE h = CreateFileW(name.c_str(), GENERIC_READ | GENERIC_WRITE, 0, NULL,
                               OPEN_EXISTING,
                               FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT |
                                   SECURITY_IDENTIFICATION,
                               NULL);
        if (h != INVALID_HANDLE_VALUE) return h;
        *err = GetLastError();
        if (*err != ERROR_PIPE_BUSY || timeout_ms == 0) return INVALID_HANDLE_VALUE;

        DWORD slice = kPollMs;
        if (timeout_ms != INFINITE) {
            ULONGLONG elapsed = GetTickCount64() - start;
            if (elapsed >= timeout_ms) {
                *err = ERROR_SEM_TIMEOUT;
                return INVALID_HANDLE_VALUE;
            }
            slice = static_cast<DWORD>(std::min<ULONGLONG>(kPollMs, timeout_ms - elapsed));
        }

        // Returns FALSE on slice timeout; the loop then retries CreateFile
        WaitNamedPipeW(name.c_str(), slice);

        if (interrupted()) {
            *was_interrupted = true;
            return INVALID_HANDLE_VALUE;
        }
    }
}

void release_handles(PipeState* s) {
    if (s->h != INVALID_HANDLE_VALUE) {
        CloseHandle(s->h);
        s->h = INVALID_HANDLE_VALUE;
    }
    if (s->ev) {
        CloseHandle(s->ev);
        s->ev = NULL;
    }
    s->pos = s->len = 0;
}

// ---- Connection callbacks --------------------------------------------------

Rboolean np_con_open(Rconnection con) {
    PipeState* s = state_of(con);
    DWORD err = 0;
    const char* stage = NULL;

    if (s->h != INVALID_HANDLE_VALUE) r_errorf("Pipe is already open.");

    s->ev = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!s->ev) win_error();

    if (s->server) {
        s->h = create_server_handle(s->name, s->sddl, s->max_instances, &err, &stage);
        if (s->h == INVALID_HANDLE_VALUE) {
            release_handles(s);
            win_error(err, stage);
        }
        // Non-blocking opens return immediately
        if (con->blocking) {
            IoResult r = io_connect(s);
            if (r.status != IoStatus::Ok) {
                release_handles(s);
                accept_failed(s, r);
            }
        }
    } else {
        bool was_interrupted = false;
        // A non-blocking open must not wait for a free instance
        DWORD wait_ms = con->blocking ? s->timeout_ms : 0;
        s->h = open_client_handle(s->name, wait_ms, &err, &was_interrupted);
        if (s->h == INVALID_HANDLE_VALUE) {
            release_handles(s);
            if (was_interrupted) r_errorf("Interrupted while waiting for a free pipe instance");
            if (err == ERROR_SEM_TIMEOUT)
                r_errorf("Timed out after %.1f s waiting for a free pipe instance",
                         s->timeout_ms / 1000.0);
            win_error(err);
        }
    }

    const char* m = con->mode;
    bool plus = std::strchr(m, '+') != NULL;
    con->canread  = (m[0] == 'r' || plus) ? RB_TRUE : RB_FALSE;
    con->canwrite = (m[0] == 'w' || m[0] == 'a' || plus) ? RB_TRUE : RB_FALSE;
    con->text = std::strchr(m, 'b') ? RB_FALSE : RB_TRUE;
    con->isopen = RB_TRUE;
    con->incomplete = RB_FALSE;
    return RB_TRUE;
}

void np_con_close(Rconnection con) {
    release_handles(state_of(con));
    con->isopen = RB_FALSE;
}

void np_con_destroy(Rconnection con) {
    PipeState* s = state_of(con);
    release_handles(s);
    delete s;
    con->private_ = NULL;
}

// Bytes readable without waiting. Ok with *avail == 0 means "nothing yet".
// A listening server pipe (no client yet) reports BAD_PIPE/PIPE_LISTENING,
// which is not an error for a non-blocking read.
IoResult peek_available(PipeState* s, DWORD* avail) {
    *avail = 0;
    if (PeekNamedPipe(s->h, NULL, 0, NULL, avail, NULL))
        return IoResult{IoStatus::Ok, *avail, 0};
    DWORD e = GetLastError();
    *avail = 0;
    if (e == ERROR_BAD_PIPE || e == ERROR_PIPE_LISTENING)
        return IoResult{IoStatus::Ok, 0, 0};
    return IoResult{classify(e), 0, e};
}

// Serves buffered bytes first, else one overlapped read. When not blocking,
// reads only what is already available and reports Empty if there is none.
size_t read_some(PipeState* s, void* dst, size_t n, bool blocking, IoResult* r) {
    if (s->pos < s->len) {
        size_t k = std::min(n, s->len - s->pos);
        std::memcpy(dst, s->buf + s->pos, k);
        s->pos += k;
        *r = IoResult{IoStatus::Ok, static_cast<DWORD>(k), 0};
        return k;
    }
    DWORD chunk = static_cast<DWORD>(std::min<size_t>(n, 1u << 30));
    if (!blocking) {
        DWORD avail;
        *r = peek_available(s, &avail);
        if (r->status != IoStatus::Ok) return 0;
        if (avail == 0) {
            r->status = IoStatus::Empty;
            return 0;
        }
        chunk = std::min(chunk, avail);
    }
    *r = io_read(s, dst, chunk);
    if (r->status == IoStatus::Ok && r->bytes == 0) r->status = IoStatus::Eof;
    return r->status == IoStatus::Ok ? r->bytes : 0;
}

size_t np_con_read(void* ptr, size_t size, size_t nitems, Rconnection con) {
    PipeState* s = state_of(con);

    if (nitems != 0 && size > SIZE_MAX / nitems) {
        r_errorf("Requested transfer size is too large.");
    }

    size_t total = size * nitems, done = 0;
    char* dst = static_cast<char*>(ptr);

    while (done < total) {
        IoResult r;
        size_t got = read_some(s, dst + done, total - done, con->blocking, &r);
        if (r.status == IoStatus::Ok) {
            done += got;
            continue;
        }
        if (r.status == IoStatus::Eof) break;
        if (r.status == IoStatus::Empty) {
            con->incomplete = RB_TRUE;
            break;
        }
        if (r.status == IoStatus::Interrupted)
            r_errorf(
                "Pipe read interrupted. (%lu of %lu bytes read)",
                (unsigned long) done,
                (unsigned long) total
            );
        if (r.status == IoStatus::Timeout) {
            if (done == 0)
                r_errorf("Pipe read timed out after %.1f s.", s->timeout_ms / 1000.0);
            r_errorf(
                "Pipe read timed out after %.1f s (%lu of %lu bytes read)",
                s->timeout_ms / 1000.0,
                (unsigned long) done,
                (unsigned long) total
            );
        }
        win_error(r.err);
    }
    return size ? done / size : 0;
}

int np_con_fgetc(Rconnection con) {
    PipeState* s = state_of(con);
    if (s->pos >= s->len) {
        s->pos = s->len = 0;
        DWORD want = sizeof(s->buf);
        if (!con->blocking) {
            DWORD avail;
            IoResult p = peek_available(s, &avail);
            if (p.status == IoStatus::Error) win_error(p.err, "PeekNamedPipe");
            if (p.status != IoStatus::Ok) {
                con->incomplete = RB_FALSE;  // peer gone: real EOF
                return -1;
            }
            if (avail == 0) {
                con->incomplete = RB_TRUE;  // more may arrive later
                return -1;
            }
            want = std::min<DWORD>(want, avail);
        }
        con->incomplete = RB_FALSE;
        IoResult r = io_read(s, s->buf, want);
        if (r.status == IoStatus::Timeout)
            r_errorf("Pipe read timed out after %.1f s", s->timeout_ms / 1000.0);
        if (r.status == IoStatus::Interrupted)
            r_errorf("Pipe read interrupted");
        if (r.status == IoStatus::Error)
            win_error(r.err);
        if (r.status != IoStatus::Ok || r.bytes == 0) return -1;
        s->len = r.bytes;
    }
    return s->buf[s->pos++];
}

size_t np_con_write(const void* ptr, size_t size, size_t nitems, Rconnection con) {
    PipeState* s = state_of(con);

    if (nitems != 0 && size > SIZE_MAX / nitems) {
        r_errorf("Requested transfer size is too large.");
    }

    size_t total = size * nitems, done = 0;
    const char* src = static_cast<const char*>(ptr);

    while (done < total) {
        DWORD chunk = static_cast<DWORD>(std::min<size_t>(total - done, 1u << 30));
        IoResult r = io_write(s, src + done, chunk);
        done += r.bytes;  // bytes moved before a cancel still count
        if (r.status == IoStatus::Ok) continue;
        if (r.status == IoStatus::Timeout)
            r_errorf(
                "Pipe write timed out after %.1f s (%lu of %lu bytes written); is the peer reading?",
                s->timeout_ms / 1000.0,
                (unsigned long) done,
                (unsigned long) total
            );
        if (r.status == IoStatus::Interrupted)
            r_errorf(
                "Pipe write interrupted (%lu of %lu bytes written)",
                (unsigned long) done,
                (unsigned long) total
            );
        win_error(r.err);
    }
    return size ? done / size : 0;
}

// Pipe writes go straight to the kernel buffer; FlushFileBuffers would block
// until the peer has read everything, so it is not done here.
int np_con_flush(Rconnection con) { return 0; }

PipeState* checked_state(SEXP sxp) {
    Rconnection con = R_GetConnection(sxp);
    if (std::strcmp(con->class_, "winpipe") != 0)
        cpp11::stop("Not a named pipe connection.");
    if (!con->isopen) cpp11::stop("Connection is not open.");
    return state_of(con);
}

}

[[cpp11::register]]
SEXP cpp_np_connection(const std::string& name, const std::string& sddl,
                       bool server, bool blocking, double max_instances, double timeout) {
    std::wstring wname = utf8_to_wstring(name);
    std::wstring wsddl = utf8_to_wstring(sddl);

    Rconnection con = NULL;
    SEXP rc = PROTECT(R_new_custom_connection(name.c_str(), "r+", "winpipe", &con));

    PipeState* s = new PipeState();
    s->name = wname;
    s->sddl = wsddl;
    s->server = server;
    s->max_instances = max_instances;
    s->timeout_ms = seconds_to_ms(timeout);

    con->private_ = s;
    con->open = np_con_open;
    con->close = np_con_close;
    con->destroy = np_con_destroy;
    con->fgetc_internal = np_con_fgetc;
    con->read = np_con_read;
    con->write = np_con_write;
    con->fflush = np_con_flush;
    con->canseek = RB_FALSE;
    con->blocking = blocking ? RB_TRUE : RB_FALSE;

    UNPROTECT(1);
    return rc;
}

// Server only: wait for a client or a disconnect.
[[cpp11::register]]
void cpp_np_conn_accept(SEXP con) {
    PipeState* s = checked_state(con);
    if (!s->server) cpp11::stop("Only a server pipe can accept clients.");
    IoResult r = io_connect(s);
    if (r.status != IoStatus::Ok) accept_failed(s, r);
}

// Server only: drop the current client.
[[cpp11::register]]
void cpp_np_conn_disconnect(SEXP con) {
    PipeState* s = checked_state(con);
    if (!s->server) cpp11::stop("Only a server pipe can disconnect clients.");
    s->pos = s->len = 0;
    DisconnectNamedPipe(s->h);
}

// Get/set the I/O timeout in seconds.
[[cpp11::register]]
double cpp_np_conn_timeout(SEXP con, double timeout, bool set) {
    Rconnection c = R_GetConnection(con);
    if (std::strcmp(c->class_, "winpipe") != 0)
        cpp11::stop("Not a named pipe connection.");
    PipeState* s = state_of(c);
    double old = s->timeout_ms == INFINITE ? R_PosInf : s->timeout_ms / 1000.0;
    if (set) s->timeout_ms = seconds_to_ms(timeout);
    return old;
}



// Low-level info about the pipe (role, type, buffers)
[[cpp11::register]]
cpp11::list cpp_np_conn_info(SEXP con) {
    HANDLE h = checked_state(con)->h;

    DWORD flags = 0;
    DWORD out_buffer_size = 0;
    DWORD in_buffer_size = 0;
    DWORD max_instances = 0;

    if (!GetNamedPipeInfo(h, &flags, &out_buffer_size, &in_buffer_size, &max_instances)) {
        cpp11::stop("[GetNamedPipeInfo] %s", GetErrorMessage(GetLastError()).c_str());
    }

    using namespace cpp11::literals;

    // PIPE_CLIENT_END and PIPE_TYPE_BYTE are 0x0, so a client is the absence of
    // PIPE_SERVER_END and byte type is the absence of PIPE_TYPE_MESSAGE
    return cpp11::writable::list({
        "is_server"_nm = (flags & PIPE_SERVER_END) != 0,
        "is_client"_nm = (flags & PIPE_SERVER_END) == 0,
        "is_message_type"_nm = (flags & PIPE_TYPE_MESSAGE) != 0,
        "is_byte_type"_nm = (flags & PIPE_TYPE_MESSAGE) == 0,
        "out_buffer_size"_nm = static_cast<double>(out_buffer_size),
        "in_buffer_size"_nm = static_cast<double>(in_buffer_size),
        "max_instances"_nm = static_cast<double>(max_instances)
    });
}


// Low-level info about the handle state.
//
// GetNamedPipeHandleState is strict about which outputs are valid:
// - the collection count/timeout fail with ERROR_INVALID_PARAMETER on local
//   pipes, so they are not requested;
// - the client user name is only available on a server handle with a connected
//   client, so it is requested separately and is NA otherwise.
[[cpp11::register]]
cpp11::list cpp_np_conn_state(SEXP con) {
    HANDLE h = checked_state(con)->h;

    DWORD state = 0;
    DWORD current_instances = 0;

    if (!GetNamedPipeHandleStateW(h, &state, &current_instances, NULL, NULL, NULL, 0)) {
        cpp11::stop(GetErrorMessage(GetLastError()).c_str());
    }

    DWORD flags = 0;
    bool is_server = GetNamedPipeInfo(h, &flags, NULL, NULL, NULL) && (flags & PIPE_SERVER_END) != 0;

    cpp11::writable::strings user(1);
    user[0] = cpp11::r_string(NA_STRING);

    wchar_t username[256];
    if (is_server &&
        GetNamedPipeHandleStateW(h, NULL, NULL, NULL, NULL, username,
                                 static_cast<DWORD>(std::size(username)))) {
        int ulen = static_cast<int>(wcsnlen(username, std::size(username)));
        int blen = WideCharToMultiByte(CP_UTF8, 0, username, ulen, NULL, 0, NULL, NULL);
        std::string user_utf8(blen > 0 ? blen : 0, '\0');
        if (blen > 0) {
            WideCharToMultiByte(CP_UTF8, 0, username, ulen, &user_utf8[0], blen, NULL, NULL);
        }
        user[0] = user_utf8;
    }

    using namespace cpp11::literals;

    return cpp11::writable::list({
        "state"_nm = static_cast<double>(state),
        "current_instances"_nm = static_cast<double>(current_instances),
        "username"_nm = user
    });
}

// Low-level info about the connection
[[cpp11::register]]
cpp11::list cpp_np_conn_peek(SEXP con) {
    PipeState* s = checked_state(con);
    HANDLE h = s->h;

    // Bytes already pulled from the kernel but not yet consumed by R
    const double buffered = static_cast<double>(s->len - s->pos);

    DWORD pipe_bytes = 0;
    double available = NA_REAL;
    DWORD error_code = 0;
    bool connected = false;

    if (PeekNamedPipe(h, NULL, 0, NULL, &pipe_bytes, NULL)) {
        connected = true;
        available = static_cast<double>(pipe_bytes) + buffered;
    } else {
        error_code = GetLastError();

        switch (error_code) {
            case ERROR_INVALID_STATE:
            case ERROR_PIPE_LISTENING:
            case ERROR_PIPE_NOT_CONNECTED:
            case ERROR_BROKEN_PIPE:
            case ERROR_NO_DATA:
            case ERROR_HANDLE_EOF:
                // Buffered bytes remain readable after the peer disconnects
                if (buffered > 0) available = buffered;
                break;

            default: {
                DWORD err = error_code;
                cpp11::stop(GetErrorMessage(err).c_str());
            }
        }
    }

    using namespace cpp11::literals;

    return cpp11::writable::list({
        "available"_nm = available,
        "error_code"_nm = (connected || buffered > 0)
            ? cpp11::r_string(NA_STRING)
            : cpp11::r_string(GetErrorMessage(error_code).c_str())
    });
}


[[cpp11::register]]
bool cpp_np_conn_exists(const std::string& name) {
    std::wstring wname = utf8_to_wstring(name);

    if (WaitNamedPipeW(wname.c_str(), 0))
        return true;

    DWORD err = GetLastError();

    return err != ERROR_FILE_NOT_FOUND &&
           err != ERROR_PATH_NOT_FOUND;
}


[[cpp11::register]]
cpp11::strings cpp_np_list() {
    WIN32_FIND_DATAW data{};
    HANDLE find = FindFirstFileW(L"\\\\.\\pipe\\*", &data);

    if (find == INVALID_HANDLE_VALUE) {
        DWORD err = GetLastError();

        if (err == ERROR_FILE_NOT_FOUND) {
            return cpp11::writable::strings();
            cpp11::stop(GetErrorMessage(err).c_str());
        }
    }

    std::vector<std::string> names;

    do {
        const wchar_t* filename = data.cFileName;

        if (std::wcscmp(filename, L".") == 0 || std::wcscmp(filename, L"..") == 0) {
            continue;
        }

        std::wstring full_name = L"\\\\.\\pipe\\";
        full_name += filename;
        names.push_back(wstring_to_utf8(full_name));
    } while (FindNextFileW(find, &data));

    DWORD err = GetLastError();
    FindClose(find);

    if (err != ERROR_NO_MORE_FILES) {
        cpp11::stop(GetErrorMessage(err).c_str());
    }

    cpp11::writable::strings result(names.size());

    for (R_xlen_t i = 0; i < static_cast<R_xlen_t>(names.size()); ++i)
        result[i] = names[i];

    return result;
}


[[cpp11::register]]
void cpp_np_conn_impersonate(SEXP con) {
    HANDLE h = checked_state(con)->h;

    if (!ImpersonateNamedPipeClient(h)) {
        cpp11::stop(GetErrorMessage(GetLastError()).c_str());
    }
}

// --- Token information ------------------------------------------------------

struct HandleGuard {
    HANDLE h = NULL;
    ~HandleGuard() { if (h) CloseHandle(h); }
};

struct ImpersonationGuard {
    bool active = false;
    explicit ImpersonationGuard(HANDLE pipe) {
        if (!ImpersonateNamedPipeClient(pipe)) {
            win_error(GetLastError(), "ImpersonateNamedPipeClient");
        }
        active = true;
    }
    ~ImpersonationGuard() {
        if (active) RevertToSelf();
    }
};

// Variable-length GetTokenInformation() result.
std::vector<BYTE> token_info(HANDLE tok, TOKEN_INFORMATION_CLASS cls) {
    DWORD need = 0;
    GetTokenInformation(tok, cls, nullptr, 0, &need);
    if (need == 0) win_error(GetLastError(), "GetTokenInformation");
    std::vector<BYTE> buf(need);
    if (!GetTokenInformation(tok, cls, buf.data(), need, &need)) {
        win_error(GetLastError(), "GetTokenInformation");
    }
    return buf;
}

std::string sid_to_string(PSID sid) {
    LPWSTR str = nullptr;
    if (!ConvertSidToStringSidW(sid, &str)) {
        win_error(GetLastError(), "ConvertSidToStringSid");
    }
    std::string out = wstring_to_utf8(str);
    LocalFree(str);
    return out;
}

// "DOMAIN\user" for a SID, falling back to the SID string if unresolvable.
std::string sid_to_name(PSID sid) {
    wchar_t name[256], domain[256];
    DWORD name_len = 256, domain_len = 256;
    SID_NAME_USE use;
    if (LookupAccountSidW(nullptr, sid, name, &name_len, domain, &domain_len, &use)) {
        return wstring_to_utf8(std::wstring(domain) + L"\\" + name);
    }
    return sid_to_string(sid);
}

const char* integrity_level_name(DWORD rid) {
    if (rid >= SECURITY_MANDATORY_SYSTEM_RID) return "system";
    if (rid >= SECURITY_MANDATORY_HIGH_RID) return "high";
    if (rid >= SECURITY_MANDATORY_MEDIUM_RID) return "medium";
    return "low";
}

cpp11::list token_info_list(HANDLE tok) {
    using namespace cpp11::literals;

    auto user_buf = token_info(tok, TokenUser);
    PSID user_sid = reinterpret_cast<TOKEN_USER*>(user_buf.data())->User.Sid;

    auto groups_buf = token_info(tok, TokenGroups);
    auto* groups = reinterpret_cast<TOKEN_GROUPS*>(groups_buf.data());

    cpp11::writable::strings grp_name, grp_sid;
    cpp11::writable::logicals grp_enabled;
    for (DWORD i = 0; i < groups->GroupCount; ++i) {
        PSID sid = groups->Groups[i].Sid;
        grp_name.push_back(sid_to_name(sid));
        grp_sid.push_back(sid_to_string(sid));
        grp_enabled.push_back((groups->Groups[i].Attributes & SE_GROUP_ENABLED) != 0);
    }

    auto elev_buf = token_info(tok, TokenElevation);
    bool elevated = reinterpret_cast<TOKEN_ELEVATION*>(elev_buf.data())->TokenIsElevated != 0;

    auto il_buf = token_info(tok, TokenIntegrityLevel);
    auto* il = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(il_buf.data())->Label.Sid;
    DWORD rid = *GetSidSubAuthority(il, *GetSidSubAuthorityCount(il) - 1);

    TOKEN_TYPE type;
    DWORD ret = 0;
    GetTokenInformation(tok, TokenType, &type, sizeof(type), &ret);

    cpp11::r_string level;
    if (type == TokenImpersonation) {
        SECURITY_IMPERSONATION_LEVEL sil;
        GetTokenInformation(tok, TokenImpersonationLevel, &sil, sizeof(sil), &ret);
        switch (sil) {
            case SecurityAnonymous:      level = "anonymous"; break;
            case SecurityIdentification: level = "identification"; break;
            case SecurityImpersonation:  level = "impersonation"; break;
            case SecurityDelegation:     level = "delegation"; break;
            default:                     level = "unknown"; break;
        }
    } else {
        level = NA_STRING;
    }

    using cpp11::writable::list;
    list groups_df = list{
        "name"_nm = grp_name,
        "sid"_nm = grp_sid,
        "enabled"_nm = grp_enabled
    };
    groups_df.attr("class") = "data.frame";
    groups_df.attr("row.names") = {NA_INTEGER, -static_cast<int>(groups->GroupCount)};

    return list{
        "user"_nm = sid_to_name(user_sid),
        "sid"_nm = sid_to_string(user_sid),
        "groups"_nm = groups_df,
        "elevated"_nm = elevated,
        "integrity"_nm = integrity_level_name(rid),
        "token_type"_nm = type == TokenPrimary ? "primary" : "impersonation",
        "impersonation_level"_nm = level
    };
}

// Token information for a pipe's client (`impersonate = TRUE`) or for the
// calling process itself. Impersonation, token access, and revert happen
// atomically so no impersonation state leaks across R calls.
[[cpp11::register]]
cpp11::list cpp_np_token_info(SEXP con, bool client) {
    HANDLE tok_raw = NULL;

    if (client) {
        PipeState* s = checked_state(con);
        if (!s->server) {
            cpp11::stop("Only the server end of a pipe can query the client token.");
        }
        ImpersonationGuard guard(s->h);
        if (!OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &tok_raw)) {
            win_error(GetLastError(), "OpenThreadToken");
        }
        HandleGuard tok{tok_raw};
        return token_info_list(tok_raw);
    } else {
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok_raw)) {
            win_error(GetLastError(), "OpenProcessToken");
        }
        HandleGuard tok{tok_raw};
        return token_info_list(tok_raw);
    }
}

[[cpp11::register]]
void cpp_np_revert() {
    if (!RevertToSelf()) {
        cpp11::stop(GetErrorMessage(GetLastError()).c_str());
    }
}
