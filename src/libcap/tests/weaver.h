#ifndef WEAVER_H
#define WEAVER_H

pthread_t weaver_thread(void);
void weaver_setup(void);
int weaver_waitforit(int n);
void weaver_terminate(void);

#endif /* WEAVER_H */
