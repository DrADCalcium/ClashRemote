#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winhttp.h>
#include <bcrypt.h>
#include <shellapi.h>
#include <stdlib.h>
#include <string.h>
#include "CWindowsPlatform.h"

static wchar_t *wide(const char *s) {
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, NULL, 0);
    if (!n) return NULL;
    wchar_t *w = calloc((size_t)n, sizeof(wchar_t));
    if (w) MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, w, n);
    return w;
}
static char *utf8(const wchar_t *s) {
    int n = WideCharToMultiByte(CP_UTF8, 0, s, -1, NULL, 0, NULL, NULL);
    if (!n) return NULL;
    char *r = calloc((size_t)n, 1);
    if (r) WideCharToMultiByte(CP_UTF8, 0, s, -1, r, n, NULL, NULL);
    return r;
}

CRHTTPResponse cr_http(const char *url, const char *method, const char *headers,
                      const uint8_t *body, size_t count, int timeout_ms) {
    CRHTTPResponse r = {0}; HINTERNET session = NULL, connection = NULL, request = NULL;
    wchar_t *u = wide(url), *m = wide(method), *h = wide(headers), *host = NULL, *path = NULL, *raw = NULL;
    URL_COMPONENTS parts = {0}; parts.dwStructSize = sizeof(parts);
    parts.dwHostNameLength = parts.dwUrlPathLength = parts.dwExtraInfoLength = (DWORD)-1;
    if (!u || !m || !h) { SetLastError(ERROR_INVALID_PARAMETER); goto done; }
    if (!WinHttpCrackUrl(u, 0, 0, &parts)) goto done;
    if (parts.nScheme != INTERNET_SCHEME_HTTP && parts.nScheme != INTERNET_SCHEME_HTTPS) { SetLastError(ERROR_INVALID_PARAMETER); goto done; }
    host = calloc(parts.dwHostNameLength + 1, sizeof(wchar_t));
    path = calloc(parts.dwUrlPathLength + parts.dwExtraInfoLength + 2, sizeof(wchar_t));
    if (!host || !path) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); goto done; }
    memcpy(host, parts.lpszHostName, parts.dwHostNameLength * sizeof(wchar_t));
    memcpy(path, parts.lpszUrlPath, parts.dwUrlPathLength * sizeof(wchar_t));
    if (parts.dwExtraInfoLength) memcpy(path + parts.dwUrlPathLength, parts.lpszExtraInfo, parts.dwExtraInfoLength * sizeof(wchar_t));
    if (!path[0]) { path[0] = L'/'; path[1] = 0; }
    session = WinHttpOpen(L"ClashRemote/SwiftWindows", WINHTTP_ACCESS_TYPE_NO_PROXY, NULL, NULL, 0);
    if (!session || !WinHttpSetTimeouts(session, timeout_ms, timeout_ms, timeout_ms, timeout_ms)) goto done;
    connection = WinHttpConnect(session, host, parts.nPort, 0);
    if (!connection) goto done;
    request = WinHttpOpenRequest(connection, m, path, NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                                 parts.nScheme == INTERNET_SCHEME_HTTPS ? WINHTTP_FLAG_SECURE : 0);
    if (!request) goto done;
    DWORD disabled = WINHTTP_DISABLE_REDIRECTS | WINHTTP_DISABLE_COOKIES;
    if (!WinHttpSetOption(request, WINHTTP_OPTION_DISABLE_FEATURE, &disabled, sizeof(disabled))) goto done;
    if (count > MAXDWORD) { SetLastError(ERROR_INVALID_PARAMETER); goto done; }
    if (!WinHttpSendRequest(request, h, (DWORD)-1, (LPVOID)body, (DWORD)count, (DWORD)count, 0) || !WinHttpReceiveResponse(request, NULL)) goto done;
    DWORD code = 0, size = sizeof(code);
    if (!WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, NULL, &code, &size, NULL)) goto done;
    r.status = (int)code; size = 0;
    WinHttpQueryHeaders(request, WINHTTP_QUERY_RAW_HEADERS_CRLF, NULL, NULL, &size, NULL);
    raw = calloc(size + sizeof(wchar_t), 1);
    if (!raw) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); goto done; }
    if (!WinHttpQueryHeaders(request, WINHTTP_QUERY_RAW_HEADERS_CRLF, NULL, raw, &size, NULL)) goto done;
    r.headers = utf8(raw);
    while (1) {
        DWORD available = 0, read = 0;
        if (!WinHttpQueryDataAvailable(request, &available)) goto done;
        if (!available) break;
        if (r.count + available > 8000000) { SetLastError(ERROR_INSUFFICIENT_BUFFER); goto done; }
        uint8_t *next = realloc(r.data, r.count + available);
        if (!next) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); goto done; }
        r.data = next;
        if (!WinHttpReadData(request, r.data + r.count, available, &read)) goto done;
        r.count += read;
        if (!read) break;
    }
    SetLastError(ERROR_SUCCESS);
done:
    r.error = GetLastError();
    if (request) WinHttpCloseHandle(request);
    if (connection) WinHttpCloseHandle(connection);
    if (session) WinHttpCloseHandle(session);
    free(u); free(m); free(h); free(host); free(path); free(raw);
    return r;
}
void cr_http_free(CRHTTPResponse *r) { free(r->data); free(r->headers); memset(r, 0, sizeof(*r)); }

int cr_digest(const uint8_t *input, size_t count, const uint8_t *key, size_t key_count,
              int kind, uint8_t *output, size_t output_count) {
    BCRYPT_ALG_HANDLE alg = NULL; BCRYPT_HASH_HANDLE hash = NULL;
    unsigned char *object = NULL; DWORD size = 0, received = 0; int ok = 0;
    if (count > MAXDWORD || key_count > MAXDWORD || output_count > MAXDWORD) return 0;
    if (BCryptOpenAlgorithmProvider(&alg, kind == 2 ? BCRYPT_SHA256_ALGORITHM : BCRYPT_MD5_ALGORITHM,
                                   NULL, kind == 3 ? BCRYPT_ALG_HANDLE_HMAC_FLAG : 0) < 0) goto done;
    if (BCryptGetProperty(alg, BCRYPT_OBJECT_LENGTH, (PUCHAR)&size, sizeof(size), &received, 0) < 0) goto done;
    object = calloc(size, 1); if (!object) goto done;
    if (BCryptCreateHash(alg, &hash, object, size, kind == 3 ? (PUCHAR)key : NULL, kind == 3 ? (ULONG)key_count : 0, 0) < 0) goto done;
    if (BCryptHashData(hash, (PUCHAR)input, (ULONG)count, 0) < 0) goto done;
    if (BCryptFinishHash(hash, output, (ULONG)output_count, 0) < 0) goto done;
    ok = 1;
done:
    if (hash) BCryptDestroyHash(hash);
    if (object) { SecureZeroMemory(object, size); free(object); }
    if (alg) BCryptCloseAlgorithmProvider(alg, 0);
    return ok;
}
void cr_open_url(const char *url) { wchar_t *w = wide(url); if (w) { ShellExecuteW(NULL,L"open",w,NULL,NULL,SW_SHOWNORMAL); free(w); } }
void cr_window_topmost(int enabled) {
    HWND w = FindWindowW(NULL,L"Clash Remote");
    if (w) SetWindowPos(w, enabled ? HWND_TOPMOST : HWND_NOTOPMOST,0,0,0,0,SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}
