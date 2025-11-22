#include <condition_variable>
#include <iostream>
#include <mutex>
#include <thread>

#include <unistd.h>
#include <sys/prctl.h>
#include <sys/psx_syscall.h>
#include <sys/syscall.h>

std::mutex mu;
std::condition_variable cv;
bool ready = false;

long int in_before = 0, out_before = 0;
long int in_after = 0, out_after = 0;

int main()
{
    std::thread t{[]() {
	std::unique_lock lk(mu);

	in_before = syscall(__NR_prctl, PR_GET_NO_NEW_PRIVS, 0, 0, 0, 0, 0);
	ready = true;
	cv.notify_one();
	cv.wait(lk, []{ return !ready; });

	in_after = syscall(__NR_prctl, PR_GET_NO_NEW_PRIVS, 0, 0, 0, 0, 0);
	lk.unlock();
    }};

    out_before = syscall(__NR_prctl, PR_GET_NO_NEW_PRIVS, 0, 0, 0, 0, 0);

    std::unique_lock lk(mu);
    cv.wait(lk, []{ return ready; });

    psx_syscall6(__NR_prctl, PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0, 0);
    ready = false;
    cv.notify_one();
    lk.unlock();

    out_after = syscall(__NR_prctl, PR_GET_NO_NEW_PRIVS, 0, 0, 0, 0, 0);
    t.join();

    std::cout << "before got in:" << in_before <<
	" out:" << out_before << std::endl;
    std::cout << "after got in:" << in_after <<
	" out:" << out_after << std::endl;

    if ((in_after & out_after) & !(in_before | out_before)) {
	std::cout << "PASSED\n";
	return 0;
    } else {
	std::cout << "FAILED\n";
	return 1;
    }
}
