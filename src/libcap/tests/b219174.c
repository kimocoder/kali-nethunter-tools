/*
 * This is a test case for:
 *
 *   https://bugzilla.kernel.org/show_bug.cgi?id=219174
 */

#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <sys/psx_syscall.h>
#include <sys/syscall.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    void *handle = dlopen("./weaver.so", RTLD_NOW);
    if (handle == NULL) {
        perror("no weaver.so loaded");
        exit(1);
    }

    pthread_t (*weaver_thread)(void) = dlsym(handle, "weaver_thread");
    void (*weaver_setup)(void) = dlsym(handle, "weaver_setup");
    int (*weaver_waitforit)(int n) = dlsym(handle, "weaver_waitforit");
    void (*weaver_terminate)(void) = dlsym(handle, "weaver_terminate");

    weaver_setup();

#define N_THREADS 37
    long int i;
    pthread_t th[N_THREADS];
    for (i = 0; i < N_THREADS; i++) {
	if (psx_syscall6(SYS_prctl, PR_SET_KEEPCAPS, i&1, 0, 0, 0, 0) != 0) {
	    perror((i&1) ? "failed to set keep-caps" :
		   "failed to reset keep-caps");
	    exit(1);
	}
	th[i] = weaver_thread();
	int got = weaver_waitforit(i+1);
	int want = (i&1) ? (3*(i+1)) : (2*(i+1));
	printf("for %ld weaver.so launched threads, total=%d, wanted=%d\n",
	       i+1, got, want);
	if (got != want) {
	    printf("FAILED\n");
	    exit(1);
	}
    }
    weaver_terminate();
    for (i = 0; i < N_THREADS; i++) {
	pthread_join(th[i], NULL);
    }
    printf("PASSED\n");
    exit(0);
}
