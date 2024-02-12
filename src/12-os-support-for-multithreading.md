# OS Support for Multithreading
---

You can access the slides for this lecture [here](https://olivierpierre.github.io/comp35112/lectures/12-os-support-for-multithreading/).
All the code samples given here can be found online, alongside instructions on how to bring up the proper environment to build and execute them [here](https://github.com/olivierpierre/comp35112-devcontainer).

In this unit we have covered, among other things, **software** and **hardware** support for multithreaded programming.
Here we will focus on the software layer that sits in between the application and the hardware: the operating system.
<div style="text-align:center"><img src="include/12-os-support-for-multithreading/intro.svg" width=260 /></div>

We will have a look at Linux (sometimes also simply referred to as *the kernel* in this document) and will cover mainly two topics:
- **What is the role of the operating system in the management and execution of multithreaded programs?**
- Linux is itself a highly concurrent program, so **how is concurrency managed in the Linux kernel?**

This lecture is medley of interesting information regarding OS support for multithreading and concurrency in the kernel, and by no means an exhaustive coverage of these topics.

## Thread Management

As previously covered, a thread is a unique schedulable entity in the system, and each process has 1 or more threads:

<div style="text-align:center"><img src="include/12-os-support-for-multithreading/tids.svg" width=500 /></div>


Processes are identified in Linux with unique integers named PIDs (process identifiers).
You can get a list of all running processes and see their PIDs with the following command:

```sh
ps -A
```

Each row represent a process, and the first column contains its PID.

Each thread is uniquely identified by another integer, the thread identifier, TID.
Threads sharing the same address space will report the same PID.
Many system calls requiring a PID (e.g. `sched_setscheduler`) actually work on a TID.

To list all threads running in a Linux system, use the following command:

```bash
ps -AT
```

The TIDs are indicated in the `SPID` column.

From within a C program, the PID and TID of a calling process/thread can be obtained with the `getppid` and `gettid` functions, respectively.
Here is an example program making use of these functions:

```c
#define _GNU_SOURCE  // Required for gettid() on Linux
/* includes here */
void *thread_function(void *arg) {
    printf("child thread, pid: %d, tid: %d\n", getpid(), gettid());
    pthread_exit(NULL);
}

int main() {
    pthread_t thread1, thread2;
    printf("parent thread, pid: %d, tid: %d\n", getpid(), gettid());

    pthread_create(&thread1, NULL, threadFunction, NULL);
    pthread_create(&thread2, NULL, threadFunction, NULL);
    pthread_join(thread1, NULL);
    pthread_join(thread2, NULL);
}
```

You can find the code for the full program [here](https://github.com/olivierpierre/comp35112-devcontainer/blob/main/12-os-support-for-multithreading/tid-pid.c).

The parent thread starts by printing its PID and TID, then creates 2 children threads, and both print their PIDs and TIDs.
Here is an example of output:

```bash
parent thread, pid: 12674, tid: 12674
child thread, pid: 12674, tid: 12675
child thread, pid: 12674, tid: 12676
```

As one can observe, threads belonging to the same process all report the PID of that process.
The first thread created in a process (the one executing the `main` function) reports a TID equals to the PID of the process.
Other children threads report different TIDs.

## Thread Creation

**The `clone` System Call.**
Processes and threads are both created with the `clone` system call.
Here is its prototype:

```c
long clone(unsigned long flags, void *stack, int *parent_tid, int *child_tid,
        unsigned long tls);
```
When creating a new **process** through `clone` most of these parameters do not matter and are set to `0`/`NULL`.
In such case the behaviour of `clone` is similar to that of the `fork` UNIX primitive: the parent's resources are duplicated, and a copy is made for the child.
Among other resources, the child gets a copy of the parent's address space.

When creating a new **thread**  with which we want to share the parent's address space, a few parameters are important:
  - `flags` specifies thread creation options;
  - `stack` should point to the memory space that will be used as **stack** for the newly created thread;
  - `tls` points to a memory space that will be used as **thread local storage** for the newly created thread.
  - `parent_tid` and `child_tid` indicate locations in memory where the system call will write the parent and child TIDs.

Each thread needs a [stack](https://en.wikipedia.org/wiki/Call_stack) to store local variables, function arguments, etc.
Each thread also needs a [thread local storage](https://en.wikipedia.org/wiki/Thread-local_storage) (TLS) area to hold a particular type of global variable that hold a per-thread value.
TLS works by prefix the declaration of global variables for which we want to have per-thread values with the `__thread` keyword.
It is used to implement e.g. `errno`, which is a global variable but requires a per-thread value to avoid being accessed concurrently when different threads in the same process call functions from the C standard library concurrently.

**`pthread_create` Under the Hood.**
Let's now study what happens when a program calls `pthread_create`.
The POSIX thread library is implemented as part of the C standard library, which on most Linux distribution is the GNU C standard library, Glibc.
Its code is very convoluted, and we'll rather study the implementation of `pthread_create` in the [Musl](https://www.musl-libc.org/) C standard library.
Its code is much simpler, but it is production-ready: Musl libc is used for example in the [Alpine](https://www.alpinelinux.org/) minimalist Linux distribution.

Musl libc's `pthread_create` is implemented in [`src/thread/pthread_create.c`](https://github.com/bminor/musl/blob/master/src/thread/pthread_create.c).
It does the following (simplified):
  1. Prepare `clone`'s flags with `CLONE_VM | CLONE_THREAD` and more.
     These two flags indicate that we want to create a thread rather than a new process, and that as such there should be no copy of the parent's address space, it will rather be shared with the child.
  2. Allocate space for a stack (pointed by `stack`) and TLS (pointed by `new`) with `mmap`. `mmap` is a system call used to ask for memory from the kernel (functions like `malloc` or `new` in C++ actually use `mmap` under the hood).
  3. Place on that stack a data structure that contains the created thread entry point, as well as the argument to pass to the function the created thread will start to execute.
  4. Call `clone`'s wrapper `__clone`:

```c
ret = __clone(start, stack, flags, args, &new->tid, TP_ADJ(new), &__thread_list_lock);
```

This wrapper will take care of performing the system call to `clone`.
Because that system call is quite architecture specific, it is implemented in assembly.
For x86-64 the implementation is in [`src/thread/x96_64/clone.s`](https://github.com/bminor/musl/blob/master/src/thread/x86_64/clone.s).
It looks like this:


```asm
__clone:
	xor %eax,%eax     // clear eax
	mov $56,%al       // clone's syscall id in eax
	mov %rdi,%r11     // entry point in r11
	mov %rdx,%rdi     // flags in rdi
	mov %r8,%rdx      // parent_tid in rdx
	mov %r9,%r8       // TLS in r8
	mov 8(%rsp),%r10
	mov %r11,%r9      // entry point in r9
	and $-16,%rsi
	sub $8,%rsi       // stack in rsi
	mov %rcx,(%rsi)   // push thread args
	syscall           // actual call to clone
	test %eax,%eax    // check parent/child
	jnz 1f            // parent jump
	xor %ebp,%ebp     // child clears base pointer
	pop %rdi          // thread args in rdi
	call *%r9         // jump to entry point
	mov %eax,%edi     // ain't supposed to return
	xor %eax,%eax     // here, something's wrong
	mov $60,%al
	syscall           // exit (60 is exit's id)
	hlt
1:      ret               // parent returns
```

We have called `__clone` from C code, and we see here that it's actually just an assembly label.
Before starting to study this code, we need to understand the **x86-64 calling convention**.
A calling convention defines how the compiler translates function calls in the source code into machine code.
Indeed, the CPU only understands machine code and there is no notion of functions in assembly, so we need a convention to indicate, upon a function call:
- Which arguments are passed in which registers
- Which register will contain the return value when the function returns.

The calling convention implemented by Linux is called the [System V application binary interface](https://en.wikipedia.org/wiki/X86_calling_conventions#System_V_AMD64_ABI), and it specifies that arguments should be passed in order in the following registers:

| Argument number | x86-64 register |
| ----------------|-----------------|
| 1               | `%rdi`          |
| 2               | `%rsi`          |
| 3               | `%rdx`          |
| 4               | `%rcx`          |
| 5               | `%r8`           |
| 6               | `%r9`           |

For function calls with more than 6 arguments, they are passed on the stack.
The return value after a function call is held in `%rax`.

So when `__clone` is called from C code as presented above, we have the parameter `start` in `%rdi`, `stack`in `%rsi`, `args` in `%rdx`, etc.
Knowing this we can start to explore the assembly code that makes up the implementation of our wrapper `__clone`.
From a high level point of view, this code prepares the parameters for the `clone` system call, and executes it.
Both the parent and the child will return concurrently from this system call: if `clone`returns 0, we are in the child, and if it returns a positive integer we are in the parent.
So there is a check on that return value.
The parent will directly return to the C code that called `__clone`, and the child will jump to its entry point.

More in details, the assembly code does the following:

1. It clears `%eax` and writes `56` in there (`%al` is the lower part of that register).
   `56` is the [system call indentifier]https://filippo.io/linux-syscall-table/ for `clone`.
   When it is invoked, the OS kernel will check that register to know what system call is actually called.
2. The child entry point is placed in `%r11`, and will be moved a few lines later to `%r9`.
3. The pointer for the child's stack `stack` is placed in `%rsi`, and the argument for the function the child will jump to when it starts to run is placed on the top of that stack
4. The kernel is invoked with the `syscall` instruction.
  We will study what happens inside the kernel shortly.
5. When the kernel returns to user space, both the parent and the child are running.
  The system call return value is tested, and if it's different than `0` we are in the parent.
  The parent jumps to the `1:` label and returns to the C code that called `__clone`.
6. The child's stack and CPU context need to be prepared for return to C code.
  The child clears the base pointer, and pop the argument for the function it will jump to from the stack into `%rdi`.
7. Finally, the child jumps to its entry point.
8. The code below that jump is never supposed to be reached, if that happens it's an error so it just calls the `exit` system call to abort.

**`clone`Implementation Inside the Kernel.**
Inside the kernel `clone` is implemented in [`kernel/fork.c`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/kernel/fork.c).

When the user space program invokes the `syscall`instruction, there is a transition to the kernel.
In the kernel the system call handler looks at `%rax`, sees that the user space wants to run the `clone` system call, so the kernel calls `sys_clone`, which itself calls `kernel_clone`.
`kernel_clone` implements the parent's duplication.
It calls various functions checking `clone`'s flags to know what needs to be copied and what needs to be shared between parent/child.
For example, for the address space (simplified):

```c
static int copy_mm(unsigned long clone_flags, struct task_struct *tsk) {
  /* ... */
	if (clone_flags & CLONE_VM) {
		mmget(oldmm);
		mm = oldmm;
	} else
		mm = dup_mm(tsk, current->mm);
  /* ... */
}
```

Here, `mm` is a data structure representing its address space.
It is duplicated if `clone`was called without the `CLONE_VM` flag, i.e. if we are trying to create a new process.
In the case of a thread, it inherits the same `mm` structure as the parent: they will share the address space.

**Jumping to the Child Thread's Function.**
When we go back to user space in the child's context, the jump from the assembly code we have seen above leads to executing the `start` entry point defined by Musl in [`src/thread/pthread_create.c`](https://github.com/bminor/musl/blob/master/src/thread/pthread_create.c):

```c
static int start(void *p) {
  struct start_args *args = p;
  /* ... */
	__pthread_exit(args->start_func(args->start_arg));
}
```

The actual function the thread needs to run is in `args->start_func`, so it is called with the desired parameters, before existing the thread with `pthread_exit`.

## In-Kernel Locks

Let's now study how the kernel implements the locks.
Indeed, under the hood `pthread_mutex_lock` and other sleep-based lock access primitives rely on the kernel.
There is a good reason to **implement such locks in the kernel** rather than user space: the kernel is the entity that can put threads to sleep and wake them up.

<div style="text-align:center"><img src="include/12-os-support-for-multithreading/kernel.svg" width=300 /></div>

Historically each lock operation, including lock take/release, required a system call, as implemented with e.g. System V semaphores.
However, the **user/kernel world switches are expensive** and the resulting overhead is non-negligible.
It can seriously impact performance, especially in scenarios where a lock is not contended:

<div style="text-align:center"><img src="include/12-os-support-for-multithreading/world-switch.svg" width=500 /></div>

## Futex

One may observe that we only need kernel intervention when there is contention, i.e. when a thread needs to sleep.
The **futex** is a low-level synchronisation primitive which name stands for **Fast User space mutEX**.
It can be used to build locks accessed in part in user space with atomic operations when there is no contention.
There is another part in kernel space, used when there is contention and threads need to be put to sleep/awaken.

A futex relies on a 32 bit variable living in user space, accessed concurrently by threads trying to take/release the lock with atomic operations.
When it is equal to zero, the lock is free:

<div style="text-align:center"><img src="include/12-os-support-for-multithreading/futex1.svg" width=400 /></div>

In that state, a thread wishing to take the lock tries to do so with an atomic compare-and-swap on the variable:
if the compare-and-swap succeeds, the thread successfully got the lock without any involvement from the kernel.
The thread can proceed with its critical section:

<div style="text-align:center"><img src="include/12-os-support-for-multithreading/futex3.svg" width=400 /></div>

Another thread trying to take the lock while it is not free will try a compare-and-swap, that will fail.
In that case the thread needs to be put to sleep, and for that the OS kernel is needed, and a system call is made.
That system call is named `futex`.

<div style="text-align:center"><img src="include/12-os-support-for-multithreading/futex6.svg" width=400 /></div>

Before putting the thread to sleep, the kernel makes a last check to see if the lock is still taken with a compare-and-swap, and if so, puts the thread to sleep in a data structure called wait queue:

<div style="text-align:center"><img src="include/12-os-support-for-multithreading/futex7.svg" width=400 /></div>

Other threads trying to take the lock that is still non-free follow the same path:
<div style="text-align:center"><img src="include/12-os-support-for-multithreading/futex8.svg" width=400 /></div>

A thread wanting to release the lock use a compare-and-swap to reset the user space variable to zero, indicating that the lock is free.
It also makes a `futex` system call to ask the OS to wake one of the threads waiting:

<div style="text-align:center"><img src="include/12-os-support-for-multithreading/futex9.svg" width=400 /></div>

The other thread will try to take the lock with a compare-and-swap, and succeed:
<div style="text-align:center"><img src="include/12-os-support-for-multithreading/futex10.svg" width=400 /></div>

Note that with the simple example implementation of lock using futex we present here, when a thread releases the lock, the user space does not know if there are waiters or not, so a system call is made even if there are no waiters:
<div style="text-align:center"><img src="include/12-os-support-for-multithreading/futex13.svg" width=400 /></div>

An optimised implementation would e.g. encode the number of waiters in the 32 bit user land variable.

## Basic Futex Lock Implementation

Below is a simple example of lock implementation on top of `futex`.
It behaves similarly to what is described in the schemas above.

```c
/* check full implementation for includes */

atomic_int my_mutex = ATOMIC_VAR_INIT(0);

int my_mutex_lock() {
    int is_free = 0, taken = 1;

    // cas(value_to_test, expected_value, new_value_to_set)
    while(!atomic_compare_exchange_strong(&my_mutex, &is_free, taken)) {
        // put the thread to sleep waiting for FUTEX_WAKE if my_mutex is still equal to 1
        syscall(SYS_futex, &my_mutex, FUTEX_WAIT, 1, NULL, NULL, 0);
    }
    return 0;
}

int my_mutex_unlock() {
    atomic_store(&my_mutex, 0);

    // wake up 1 thread if needed
    syscall(SYS_futex, &my_mutex, FUTEX_WAKE, 1, NULL, NULL, 0);
    return 0;
}
```

You can download the source code of a full program using that implementation [here](https://github.com/olivierpierre/comp35112-devcontainer/blob/main/12-os-support-for-multithreading/lock-bench/lock-bench-custom-futex.c).

We have our user space variable `my_mutex`.
It is initialised to `0` and manipulated using the C atomic operations API.
Recall that it is not a good idea to assume that standard loads and store are atomic (e.g. a standard load of a 64 bits variable could be represented as two loads on a 32 bit architecture).

The lock taking function, `my_mutex_lock`, performs a compare-and-swap with [`atomic_compare_exchange_strong`](https://en.cppreference.com/w/cpp/atomic/atomic_compare_exchange) checking if the variable representing the lock is `0` (`is_free`), i.e. if the lock is free.
If it is the case, compare-and-swap function returns 1 and `my_mutex_lock`returns: the lock has been taken.
If not, a system call is needed to put the thread to sleep: `futex` is called, taking various parameters, the important one here being the address of the user space variable representing the lock, and the `FUTEX_WAIT` flag indicating that the thread should be put to sleep.
When the thread is later awaken, it will return from `futex` and try another iteration of the loop.

The `mutex_unlock` operations starts by resetting the user space variable to `0` to indicate that the lock is free.
It then calls `futex`, this time with the `FUTEX_WAKE` flag, to indicate the kernel to wake up `1` waiter in the wait queue if needed.

## Investigating Lock Performance

We can write a small benchmark measuring latency introduced by the locking/unlocking operations, by creating a bunch of threads running that function and measuring their execution time:

```c
#define CS_NUM      100000

void *thread_function(void *arg) {
  for(int i=0; i < CS_NUM; i++) {

    lock();
    // instantaneous critical section to maximise the impact of the latency introduced by the
    // lock/unlock operations
    unlock();
  }

  return;
}
```

We can compare the performance of 3 types of locks:
- The simple futex-based lock we just presented;
- Traditional `pthread_mutex_lock` operations, that under the hood used a heavily optimised version of the futex lock;
- System V semaphores, which require a system call for every lock/unlock operation.

You can find the sources of the benchmark [here](https://github.com/olivierpierre/comp35112-devcontainer/tree/main/12-os-support-for-multithreading/lock-bench).

Here is an example of execution on an i7-8700 with 6 cores:

```bash
System V semaphores:
./lock-bench-sysv-semaphores
5 threads ran a total of 500000 crit. sections in 1.262348 seconds, throughput: 0.396087 cs/usec
Pthread_mutex (futex):
./lock-bench-futex
5 threads ran a total of 500000 crit. sections in 0.020067 seconds, throughput: 24 cs/usec
custom futex lock:
./lock-bench-custom-futex
5 threads ran a total of 500000 crit. sections in 0.069710 seconds, throughput: 7 cs/usec
```

As you can see, both versions of the futex-based lock are orders of magnitude faster than using System V semaphores.
The optimised version (i.e. `pthread_mutex` operations implemented by the Glibc) of the futex-based lock is 3x faster than the naive implementation we presented above.

## Pthread Mutex Implementation
The previous custom futex lock implementation is suboptimal (and, technically, not 100% correct, see [here](https://www.akkadia.org/drepper/futex.pdf)).
Let's briefly have a look at Musl (futex-based) implementation of `pthread_mutex_lock` in [`src/thread/pthread_mutex_lock.c`](https://github.com/bminor/musl/blob/master/src/thread/pthread_mutex_lock.c).

```c
int __pthread_mutex_lock(pthread_mutex_t *m) {
	if ((m->_m_type&15) == PTHREAD_MUTEX_NORMAL
	    && !a_cas(&m->_m_lock, 0, EBUSY))        // CAS, futex fast path
		return 0;

	return __pthread_mutex_timedlock(m, 0);    // Didn't get the lock
}
```

We can see the compare-and-swap on the user space variable: if the lock was free we take the fast path and return directly.
If not, `__pthread_mutex_timedlock` is called.

`pthread_mutex_timedlock` (in [`src/thread/pthread_mutex_timedlock.c`](https://github.com/bminor/musl/blob/master/src/thread/pthread_mutex_timedlock.c)) calls a bunch of functions that end up in `FUTEX_WAIT` being called in `__timedwait_cp` (in [`src/thread/__timedwait.c`](https://github.com/bminor/musl/blob/master/src/thread/__timedwait.c)):

```c
int __timedwait_cp(volatile int *addr, int val,
	clockid_t clk, const struct timespec *at, int priv)
{
  /* ... */

	r = -__futex4_cp(addr, FUTEX_WAIT|priv, val, top);

  /* ... */
}

```

Here, `__futex4_cp`is a wrapper around a `futex` system call.

We can also have a brief look Musl's implementation of `pthread_mutex_unlock` in [`src/thread/pthread_mutex_unlock.c`](https://github.com/bminor/musl/blob/master/src/thread/pthread_mutex_unlock.c):

```c
int __pthread_mutex_unlock(pthread_mutex_t *m) {
  int waiters = m->_m_waiters;
  int new = 0;

  /* ... */

  cont = a_swap(&m->_m_lock, new);

  if (waiters || cont<0)
		__wake(&m->_m_lock, 1, priv);
}
```

The user space variable is first reset to `0`with a compare-and-swap to indicate that the lock is free.
Musl's implementation also keeps track of contention, and calls `__wake` if waiters need to be awaken.
`__wake`'s implementation in [`src/internal/pthread_impl.h`](https://github.com/bminor/musl/blob/master/src/internal/pthread_impl.h) will lead to a futex `FUTEX_WAKE` system call.

## Concurrency in the Kernel

Historically there used to be a **big kernel lock** serialising all execution of kernel code.
It was slowly removed over time, and this removal was finalised in v2.6.39 (2011).
Today the **kernel is a highly concurrent, shared memory program**:

<div style="text-align:center"><img src="include/12-os-support-for-multithreading/kernel-concurrency.svg" width=480 /></div>

Concurrent flows of execution include system calls issued by applications running on different cores, exceptions and hardware interrupts that may interrupt the kernel execution flow, kernel threads & other execution flow entities, kernel preemption, etc.
In that context, various locking mechanism are available to protect critical section in kernel code.
We will study a few of these next.

## Locking in the Kernel

Linux offers various types of locks:
- Linux's in-kernel **mutexes** implement sleep-based wait and have a usage count (number of entities that can hold the mutex) of 1.
- The in-kernel **semaphores** also implement wait by sleeping, but their usage count can be more than 1
- Similarly to user space, Linux offers in-kernel **spinlocks**, that implement wait with busy waiting (and their usage count is 1).
  Spinlocks run with preemption and possibly interrupts disabled: contrary to sleep-based locks they are **usable when kernel execution cannot sleep**.
  A typical example here are interrupt handlers.
  These cannot sleep because they are not schedulable entities like processes or threads, so we can only use busy-waiting in that case.
- **Completion variables** are the in-kernel equivalent of the condition variables we saw in user space.
- **Reader-writer spinlocks** and **Sequential locks** are two specific types of locks that differentiate readers from writers.
   We will cover them a bit more in details next.

## Spinlocks in the Kernel

As mentioned spinlocks are used to protect critical sections in contexts where the kernel cannot sleep.
This is an excerpt from the i8042 mouse/keyboard driver in [`drivers/input/serio/i8042.c`](https://elixir.free-electrons.com/linux/latest/source/drivers/input/serio/i8042.c) (simplified):
```c
static irqreturn_t i8042_interrupt(int irq, void *dev_id) {
  unsigned long flags;
  /* ... */

  spin_lock_irqsave(&i8042_lock, flags);
  /* critical section, read data from device */
  spin_unlock_irqrestore(&i8042_lock, flags);
}
```

This code is executed following the reception of an interrupt from the device, i.e. it runs in interrupt context.
In that context the kernel cannot sleep so it needs to use locks that busy wait, such as the spinlock.
Here, `spin_lock_irqsave` takes the lock, saves the interrupt state (i.e. the fact that interrupts are disabled or not) into the `flags` variable, and disables interrupt if they were not already off.
`spin_unlock_irqrestore` releases the lock, restores interrupt state from `flags`, i.e. enable interrupts if they were enabled prior to taking the lock, or leave them disabled if they were not.

## Reader-Writer Spinlocks

In many scenarios, certain critical sections accessing a given shared data are read only.
If there is no writer in a given time window, letting several concurrent entities run these critical sections during that time window is fine.
Reader-writer locks are a special type of spinlocks that differentiate readers from writers (they don't use the same lock/unlock primitives).
Such locks serialise write accesses with other (read/write accesses), but allows concurrent readers:

<div style="text-align:center"><img src="include/12-os-support-for-multithreading/rw.svg" width=550 /></div>

In the example above, we can see that the 3 readers can run their (read-only) critical sections at the same time.
A writer wishing to take the lock must wait until there is no reader to be able to take the lock.
If a writer tries to take the lock and must wait because there are readers holding it, subsequent readers trying to take the lock will succeed and delay the execution of the writer (e.g. here reader 2 and 3).
Hence, **reader-writer locks favour readers**.

## Sequential Locks

The seqlock (sequential lock) is another form of spinlock that has a **sequence number** associated, incremented each time a writer acquires and releases the lock.
Concurrent readers are allowed, they check the number at the beginning and end of their critical section.
If a reader realise at the end of its critical section that the number has changed, it means that a writer started/finished since the beginning of the reader's critical section.

Here is an example of scenario for a seqlock (bottom), compared to what happens with a reader-writer lock (top):

<div style="text-align:center"><img src="include/12-os-support-for-multithreading/seqlock.svg" width=550 /></div>

As one can observe, reader 1 realises at the end of its critical section that writer 1 started its own since it got the lock, so it restarts.
Writer 1 was able to start its critical section directly.
Readers can still run in parallel: seqlocks scale to many readers like the reader-writer lock, but **favours writers**.

## Read-Copy-Update

RCU is a method to protect a critical section that allows concurrent **lockless** readers.
It is suited in situations where **it OK for concurrent readers not to see the same state for a given piece of data**, as long as **all see a consistent state**.

Let's take an example by demonstrating how a linked list.

## RCU Example: Linked List Update

We consider a singly linked list with a head pointer.
Readers traverse the list to extract data from certain nodes: because they do not modify anything, they do not take any lock.
Writers traverse the list to update the data contained in certain nodes.
Writers also add/delete elements.
Each node is a data structure with a few members and a next pointer.

Such a list is illustrated below:

<div style="text-align:center"><img src="include/12-os-support-for-multithreading/rcu2.svg" width=600 /></div>

Let's study what a writer would do with RCU when it wants to **update the content of a node**.

1. First a new node is allocated, and the data from the node we want to update is copied there:

<div style="text-align:center"><img src="include/12-os-support-for-multithreading/rcu4.svg" width=600 /></div>

2. The desired update is performed in the copy:
<div style="text-align:center"><img src="include/12-os-support-for-multithreading/rcu5.svg" width=600 /></div>

3. The new node is made to point to the node after the one we wish to update:
<div style="text-align:center"><img src="include/12-os-support-for-multithreading/rcu6.svg" width=600 /></div>

4. With an atomic operation, the next pointer of the node preceding the one we wish to update is swapped to point to the new node:
<div style="text-align:center"><img src="include/12-os-support-for-multithreading/rcu7.svg" width=600 /></div>

5. At that stage, there may be outstanding readers still reading the old version of the data structure and we need to wait until no reader is accessing that old node: this is called the **grace period**:
<div style="text-align:center"><img src="include/12-os-support-for-multithreading/rcu8.svg" width=600 /></div>

6. When we are certain there is no reader accessing the old node, it can be freed:
<div style="text-align:center"><img src="include/12-os-support-for-multithreading/rcu9.svg" width=600 /></div>

Consider the state of the list a reader would see if it runs during any of the steps we previously described: races are not possible because at any time the readers will either see a consistent state of the queue, i.e. the state before or after the update.
We have made the update atomic with respect to the readers.
Note that due to the grace period, it is possible for some reader to see the old state of the queue *after* the writer has effectively realised the update.
In many situations this is OK, in others it is not: this is to be considered carefully before choosing to use RCU.
Finally, note that the writers do need to take a lock because they still need to be serialised.

## RCU Example in Linux

Linux provides an API to protect critical sections with RCU.
Below is and example of its usage to protect a data structure.
It is taken from [Linux's official documentation](https://www.kernel.org/doc/html/next/RCU/whatisRCU.html).

```c
struct foo { int a; int b; int c; };

DEFINE_SPINLOCK(foo_mutex); // a spinlock to serialise writers
// the reference we want to protect (assume it is initialised somewhere else):
struct foo __rcu *gbl_foo; 

void foo_read(void) {
  struct foo *fp;
  int a, b, c;
    
  rcu_read_lock();
  fp = rcu_dereference(gbl_foo);
  rcu_read_unlock();

  a = fp->a;
  b = fp->b;
  c = fp->c;

  /* do something with what was read ... */
}

void foo_write(int new_ab) {
  struct foo *new_fp, *old_fp;

  new_fp = kmalloc(sizeof(*new_fp), GFP_KERNEL); // allocate new data

  spin_lock(&foo_mutex); // serialise writers

  // get a ref to the data:
  old_fp = rcu_dereference_protected(gbl_foo, lockdep_is_held(&foo_mutex));

  *new_fp = *old_fp; // copy data
  new_fp->a = new_ab; // update data
  new_fp->b = new_ab; // update data

  // atomic ref update:
  rcu_assign_pointer(gbl_foo, new_fp);

  spin_unlock(&foo_mutex);

  synchronize_rcu(); // wait for grace period
  kfree(old_fp);     // free old data
}
```

You can find the source code of a Linux kernel module testing this code, alongside with instructions on how to build and run it [here](https://github.com/olivierpierre/comp35112-devcontainer/tree/main/12-os-support-for-multithreading/rcu). Note that this is kernel code, so you won't be able to run it on unprivileged containers (e.g. GitHub codespaces).

We have our data structure declaration, the type is `struct foo` and it contains 3 members.
The reference to the data structure we want to protect with RCU is `gbl_foo`.
We assume that the data structure it points to is initialised somewhere else (in the full program the module's initialisation function takes care of that).
We define a spinlock `foo_mutex` to serialise the writers.
The two functions `foo_write` and `foo_read` represent the code that the concurrent readers/writers will run.

**Readers Function.**
`foo_read` is relatively simple: it uses `rcu_read_lock` and `rcu_read_unlock` to indicates its critical section.
Note that these functions do not actually take/release a lock, but rather help keep track of readers to know when the grace period has ended.
Within the critical section the reference is grabbed with `rcu_dereference`.

**Writers Function.**
`foo_write` starts by allocating a new data structure with `kmalloc` (the kernel equivalent of `malloc`), and grabs the spinlock serialising writers.
It then grabs a reference to the protected data structure with `rcu_dereference_protected`, an optimised version of `rcu_dereference` that can be used on the writers' side.
It then performs the copy, and updates the copy.
The atomic reference update is performed with `rcu_assign_pointer`.
Next the spinlock can be released.
Finally, `synchronize_rcu` is used to wait until the end of the grace period, i.e. to wait until there is no reader holding a reference to the old data structure, which can finally be deallocated with `kfree`.

