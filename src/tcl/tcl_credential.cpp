// OS-backed generic passwords. Never fall back to plaintext on supported OSes.
#include <tcl.h>
#include <cstring>
#ifdef _WIN32
#include <windows.h>
#include <wincred.h>
#include <string>
#elif defined(__APPLE__)
#include <Security/Security.h>
#endif

#if defined(_WIN32) || defined(__APPLE__)
static int credentialError(Tcl_Interp* ti, long code)
{
    Tcl_SetObjResult(ti, Tcl_ObjPrintf("credential store error %ld", code));
    Tcl_SetErrorCode(ti, "SCIDB", "CREDENTIAL", "STORE", NULL);
    return TCL_ERROR;
}

#endif

static int credential(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
    static const char* ops[] = {"get", "set", "delete", NULL};
    int op;
    if (objc < 2) { Tcl_WrongNumArgs(ti, 1, objv, "get|set|delete service account ?value?"); return TCL_ERROR; }
    if (Tcl_GetIndexFromObj(ti, objv[1], ops, "operation", TCL_EXACT, &op) != TCL_OK) return TCL_ERROR;
    if (objc != (op == 1 ? 5 : 4)) { Tcl_WrongNumArgs(ti, 2, objv, op == 1 ? "service account value" : "service account"); return TCL_ERROR; }
    int sn, an;
    const char* service = Tcl_GetStringFromObj(objv[2], &sn);
    const char* account = Tcl_GetStringFromObj(objv[3], &an);
    if (!sn || !an || int(std::strlen(service)) != sn || int(std::strlen(account)) != an) {
        Tcl_SetObjResult(ti, Tcl_NewStringObj("service and account must be nonempty and contain no NUL", -1)); return TCL_ERROR;
    }
#if defined(_WIN32)
    // Length prefix makes the (service, account) tuple unambiguous.
    std::string target = std::to_string(sn) + ":" + service + account;
    Tcl_DString wide; Tcl_DStringInit(&wide);
    Tcl_Encoding enc = Tcl_GetEncoding(ti, "unicode");
    Tcl_UtfToExternalDString(enc, target.data(), int(target.size()), &wide);
    Tcl_FreeEncoding(enc);
    LPCWSTR name = reinterpret_cast<LPCWSTR>(Tcl_DStringValue(&wide));
    DWORD err = ERROR_SUCCESS;
    if (op == 0) {
        PCREDENTIALW value = NULL;
        if (CredReadW(name, CRED_TYPE_GENERIC, 0, &value)) {
            Tcl_SetObjResult(ti, Tcl_NewStringObj(reinterpret_cast<char*>(value->CredentialBlob), value->CredentialBlobSize));
            CredFree(value);
        } else { err = GetLastError(); }
    } else if (op == 1) {
        int len; const char* value = Tcl_GetStringFromObj(objv[4], &len);
        CREDENTIALW c = {}; c.Type = CRED_TYPE_GENERIC; c.TargetName = const_cast<LPWSTR>(name);
        c.Persist = CRED_PERSIST_LOCAL_MACHINE; c.CredentialBlobSize = len;
        c.CredentialBlob = reinterpret_cast<LPBYTE>(const_cast<char*>(value));
        if (!CredWriteW(&c, 0)) err = GetLastError();
    } else if (!CredDeleteW(name, CRED_TYPE_GENERIC, 0)) { err = GetLastError(); }
    Tcl_DStringFree(&wide);
    if (err != ERROR_SUCCESS && !(err == ERROR_NOT_FOUND && op != 1)) return credentialError(ti, err);
#elif defined(__APPLE__)
    CFStringRef s = CFStringCreateWithBytes(NULL, reinterpret_cast<const UInt8*>(service), sn, kCFStringEncodingUTF8, false);
    CFStringRef a = CFStringCreateWithBytes(NULL, reinterpret_cast<const UInt8*>(account), an, kCFStringEncodingUTF8, false);
    if (!s || !a) { if (s) CFRelease(s); if (a) CFRelease(a); return credentialError(ti, errSecParam); }
    CFMutableDictionaryRef q = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(q, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(q, kSecAttrService, s); CFDictionarySetValue(q, kSecAttrAccount, a);
    OSStatus status;
    if (op == 0) {
        CFDictionarySetValue(q, kSecReturnData, kCFBooleanTrue);
        CFTypeRef result = NULL; status = SecItemCopyMatching(q, &result);
        if (status == errSecSuccess) {
            CFDataRef data = static_cast<CFDataRef>(result);
            Tcl_SetObjResult(ti, Tcl_NewStringObj(reinterpret_cast<const char*>(CFDataGetBytePtr(data)), CFDataGetLength(data)));
            CFRelease(result);
        }
    } else if (op == 1) {
        int len; const char* value = Tcl_GetStringFromObj(objv[4], &len);
        CFDataRef data = CFDataCreate(NULL, reinterpret_cast<const UInt8*>(value), len);
        CFMutableDictionaryRef attrs = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(attrs, kSecValueData, data);
        status = SecItemUpdate(q, attrs);
        if (status == errSecItemNotFound) { CFDictionarySetValue(q, kSecValueData, data); status = SecItemAdd(q, NULL); }
        CFRelease(attrs); CFRelease(data);
    } else { status = SecItemDelete(q); }
    CFRelease(q); CFRelease(s); CFRelease(a);
    if (status != errSecSuccess && !(status == errSecItemNotFound && op != 1)) return credentialError(ti, status);
#else
    Tcl_SetObjResult(ti, Tcl_NewStringObj("unavailable", -1));
    Tcl_SetErrorCode(ti, "SCIDB", "CREDENTIAL", "UNAVAILABLE", NULL);
    return TCL_ERROR;
#endif
    return TCL_OK;
}

void initCredentials(Tcl_Interp* ti)
{
    Tcl_CreateObjCommand(ti, "::scidb::sys::credential", credential, NULL, NULL);
}
