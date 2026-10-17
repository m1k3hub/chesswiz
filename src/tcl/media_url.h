// URL schemes follow RFC 3986. Drive letters remain paths.
#ifndef SCIDB_MEDIA_URL_H
#define SCIDB_MEDIA_URL_H
inline bool mediaHasUrlScheme(char const* s)
{
    if (!s || !((*s >= 'A' && *s <= 'Z') || (*s >= 'a' && *s <= 'z')))
        return false;
    char const* p = s + 1;
    while ((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z')
        || (*p >= '0' && *p <= '9') || *p == '+' || *p == '-' || *p == '.') ++p;
    return *p == ':' && p != s + 1;
}
#endif
