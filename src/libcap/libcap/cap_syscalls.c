#include "libcap.h"

/*
 * psx_load_syscalls() is weakly defined in libcap so we can have it
 * overridden by libpsx if that library is linked. Specifically, when
 * libcap calls psx_load_sycalls() it is prepared to override the
 * default values for the syscalls that libcap uses to change security
 * state.  As can be seen here this present function is mostly a
 * no-op. However, if libpsx is linked, the one present in that
 * library (not being weak) will replace this one and the
 * _libcap_overrode_syscalls value isn't forced to zero.
 */

__attribute__((weak))
void psx_load_syscalls(long int (**syscall_fn)(long int,
					       long int, long int, long int),
		       long int (**syscall6_fn)(long int,
						long int, long int, long int,
						long int, long int, long int))
{
    _libcap_overrode_syscalls = 0;
}
