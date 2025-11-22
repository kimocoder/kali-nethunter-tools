/* Stub implementations of libintl functions for Android */
/* These are needed because glib2 references them even with NLS disabled */

#include <stddef.h>

/* Stub implementations that just return the input strings */
char *g_libintl_gettext(const char *msgid) {
    return (char *)msgid;
}

char *g_libintl_dgettext(const char *domainname, const char *msgid) {
    return (char *)msgid;
}

char *g_libintl_dcgettext(const char *domainname, const char *msgid, int category) {
    return (char *)msgid;
}

char *g_libintl_ngettext(const char *msgid1, const char *msgid2, unsigned long int n) {
    return (char *)((n == 1) ? msgid1 : msgid2);
}

char *g_libintl_dngettext(const char *domainname, const char *msgid1, const char *msgid2, unsigned long int n) {
    return (char *)((n == 1) ? msgid1 : msgid2);
}

char *g_libintl_dcngettext(const char *domainname, const char *msgid1, const char *msgid2, unsigned long int n, int category) {
    return (char *)((n == 1) ? msgid1 : msgid2);
}

char *g_libintl_textdomain(const char *domainname) {
    return (char *)domainname;
}

char *g_libintl_bindtextdomain(const char *domainname, const char *dirname) {
    return (char *)dirname;
}

char *g_libintl_bind_textdomain_codeset(const char *domainname, const char *codeset) {
    return (char *)codeset;
}
