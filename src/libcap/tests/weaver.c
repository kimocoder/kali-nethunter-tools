#define _GNU_SOURCE

#include <stdio.h>
#include <sys/prctl.h>
#include <pthread.h>
#include <unistd.h>

#include "./weaver.h"
#include "../libcap/execable.h"

static pthread_mutex_t mu;
static pthread_cond_t cond; /* this is only used to wait on 'state' changes */
static int primed = 0;
static int counter = 0;
static int total = 0;
static int trigger = 0;   /* 0=wait, 1=tick, 2=exit */

static void *run_thread(void *ignored)
{
    pthread_mutex_lock(&mu);
    do {
	primed++;
	while (trigger == 0) {
	    pthread_cond_signal(&cond);
	    pthread_cond_wait(&cond, &mu);
	}
	if (trigger == 1) {
	    counter++;
	    total += prctl(PR_GET_KEEPCAPS, 0, 0, 0, 0, 0)+2;
	    primed--;
	    while (trigger == 1) {
		pthread_cond_signal(&cond);
		pthread_cond_wait(&cond, &mu);
	    }
	}
    } while (trigger != 2);
    pthread_cond_signal(&cond);
    pthread_mutex_unlock(&mu);
    return NULL;
}

pthread_t weaver_thread(void)
{
    pthread_t th;
    pthread_create(&th, NULL, run_thread, NULL);
    return th;
}

void weaver_setup(void)
{
    pthread_mutex_init(&mu, NULL);
    pthread_cond_init(&cond, NULL);
}

int weaver_waitforit(int n)
{
    pthread_mutex_lock(&mu);
    counter = 0;
    total = 0;
    pthread_mutex_unlock(&mu);
    /* be sure that the above happens before triggering */
    pthread_mutex_lock(&mu);
    while (primed < n) {
	pthread_cond_signal(&cond);
	pthread_cond_wait(&cond, &mu);
    }
    trigger = 1;
    while (counter < n) {
	pthread_cond_signal(&cond);
	pthread_cond_wait(&cond, &mu);
    }
    trigger = 0;
    pthread_cond_signal(&cond);
    pthread_mutex_unlock(&mu);
    return total;
}

void weaver_terminate(void)
{
    pthread_mutex_lock(&mu);
    trigger = 2;
    pthread_cond_signal(&cond);
    pthread_mutex_unlock(&mu);
}

#define N_THREADS 10

SO_MAIN(int argc, char **argv) {
    int i;
    pthread_t arr[N_THREADS];

    weaver_setup();
    for (i = 0; i < N_THREADS; i++) {
	long int val = !(i & 1);
	prctl(PR_SET_KEEPCAPS, val, 0, 0, 0, 0, 0);
	arr[i] = weaver_thread();
    }
    int n = weaver_waitforit(N_THREADS);
    weaver_terminate();
    for (i = 0; i < N_THREADS; i++) {
	pthread_join(arr[i], NULL);
    }
    if (n != 25) {
	printf("FAILED: got=%d, want=25\n", n);
	exit(1);
    }
    printf("PASSED\n");
}
