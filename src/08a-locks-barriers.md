# Synchronisation in Parallel Programming - Locks and Barriers
---

You can access the slides for this lecture [here](https://olivierpierre.github.io/comp35112/lectures/08a-locks-barriers).
All the code samples given here can be found online, alongside instructions on how to bring up the proper environment to build and execute them [here](https://github.com/olivierpierre/comp35112-devcontainer).

We have seen previously how to program a shared memory processor using threads, execution flows that share a common address space which is very practical for communications.
However, the examples we have seen were extremely simple: there was no need for threads to synchronise, apart from the final join operation.
There was also no shared data between threads.
Today we are going to see mechanisms that make synchronisation and data sharing (especially in write mode) possible.

## Synchronisation Mechanisms

In a multithreaded program the threads are rarely completely independent: they need to wait for each other at particular points during the computations, and they need to communicate by sharing data, in particular in write mode (e.g. one thread writes a value in memory that is supposed to be read or updated by another thread).
To allow all of this we use software constructs named **synchronisation mechanisms**.
Here we will cover two mechanisms: **barriers**, that let threads wait for each other, and **locks**, allowing threads to share data safely.
In the next lecture we will cover **condition variables**, that lets threads signal the occurrence of events to each other.

## Barriers

A barrier allows selected threads to meet up at a certain point in the program execution.
Upon reaching the barriers, all threads wait until the last one reaches it.

Consider this example:

<div style="text-align:center"><img src="include/08a-locks-barriers/barrier.svg" width=800 /></div>


We have the time flowing horizontally.
Thread 2 reaches the barrier first, and it starts waiting for all the other threads to reach that point.
Thread 1, then 3 do the same.
When thread 4 reaches the barriers, it's the last one, so all threads resume execution.

Barriers are useful in many scenarios.
For example with data parallelism, assuming an application is composed of multiple phases or steps.
An example could be a first step in which threads first filter the input data, based on some rule, and then in a second step the threads perform some computation on the filtered data.
We may want to have a barrier to make sure that the filtering step is finished in all threads before any starts the computing step:

<div style="text-align:center"><img src="include/08a-locks-barriers/barrier2.svg" width=800 /></div>

Another use case is when, because of data dependencies, we can parallelise only a subset of a loop's iterations at a time.
Recall the example from the lecture on [shared memory programming](03-shared-memory-programming.html#automatic-parallelisation-1).
We can put a barrier in a loop to ensure that all the parallel iterations in one step are computed before going to the next step:

<div style="text-align:center"><img src="include/08a-locks-barriers/barrier3.svg" width=800 /></div>

Barriers are very natural when threads are used to implement data parallelism@ we want the whole answer from a given step before proceeding to the next one.

## Barrier Example

Let's write a simple C program using barriers, with the POSIX thread library.
We will create 2 threads, which behaviour is illustrated below:

<div style="text-align:center"><img src="include/08a-locks-barriers/barrier-example3.svg" width=700 /></div>

Each thread performs some kind of computations (green part).
Then each thread reaches the barrier, and prints the fact that it has done so on the standard output.
We will make sure that the amount of computations in one thread (thread 1) is much larger than the amount in the other thread (thread 2), so we should see thread 1 printing the fact that it has reached the barrier *before* thread 2 does so.
Once the two threads are at the barrier, they should both resume execution, and they should print out the fact that they are past the barrier approximately at the same time.
We'll repeat all that a few time in a loop.

This is the code for the program (you can access and download the full code [here](https://github.com/olivierpierre/comp35112-devcontainer/blob/main/08a-locks-barriers/barrier.c)).
```c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <unistd.h>

/* the number of loop iterations: */
#define ITERATIONS      10 

/* make sure one thread spins much longer than the other one: */
#define T1_SPIN_AMOUNT  200000000
#define T2_SPIN_AMOUNT  (10 * T1_SPIN_AMOUNT) 

/* A data structure repreenting each thread: */
typedef struct {
    int id;           // thread unique id
    int spin_amount;  // how much time the thread will spin to emulate computations
    pthread_barrier_t *barrier; // a pointer to the barrier
} worker;

void *thread_fn(void *data) {
    worker *arg = (worker *)data;
    int id = arg->id;
    int iteration = 0;

    while(iteration != ITERATIONS) {

        /* busy loop to simulate activity */
        for(int i=0; i<arg->spin_amount; i++);

        printf("Thread %d done spinning, reached barrier\n", id);

        /* sync on the barrier */
        int ret = pthread_barrier_wait(arg->barrier);
        if(ret != PTHREAD_BARRIER_SERIAL_THREAD && ret != 0) {
            perror("pthread_barrier_wait");
            exit(-1);
        }

        printf("Thread %d passed barrier\n", id);
        iteration++;
    }

    pthread_exit(NULL);
}

int main(int argc, char **argv) {
    pthread_t t1, t2;
    pthread_barrier_t barrier;

    worker w1 = {1, T1_SPIN_AMOUNT, &barrier};
    worker w2 = {2, T2_SPIN_AMOUNT, &barrier};

    if(pthread_barrier_init(&barrier, NULL, 2)) {
        perror("pthread_barrier_init");
        return -1;
    }

    if(pthread_create(&t1, NULL, thread_fn, (void *)&w1) ||
            pthread_create(&t2, NULL, thread_fn, (void *)&w2)) {
        perror("pthread_create");
        return -1;
    }

    if(pthread_join(t1, NULL) || pthread_join(t2, NULL))
        perror("phread_join");

    return 0;
}
```

This code declares a data structure `worker` representing a thread.
It contains an integer identifier `id`, another integer `spin_amount` representing the amount of time the thread should spin to emulate the act of doing computations, and a pointer to a `pthread_barrier_t` data structure representing the barrier the thread will synchronise upon.

The barrier is initialised in the main function with [`pthread_barrier_init`](https://linux.die.net/man/3/pthread_barrier_init).
Notice the last parameter that indicates the amount of threads that will be waiting on the barrier (`2`).
An instance of `worker` is created for each thread in the main function, and the relevant instance is passed as parameter to each thread's function `thread_fn`.

The threads' function starts by spinning with a `for` loop.
As previously described the amount of time thread 2 spins is much higher than for thread 1.
The threads meet up at the barrier by both calling [`pthread_barrier_wait`](https://linux.die.net/man/3/pthread_barrier_wait).

## Locks: Motivational Example 1

We need locks to **protect data that is shared between threads and that can be accessed in write mode by at least 1 thread**.
Let's motivate why this is very important.
Assume that we have a cash machine, which supports various operations and among them cash withdrawal by a client.
This is the pseudocode for the withdrawal function:

```c
int withdrawal = get_withdrawal_amount(); /* amount the user is asking to withdraw */
int total = get_total_from_account();     /* total funds in user account */

/* check whether the user has enough funds in her account */
if(total < withdrawal)
    abort("Not enough money!");

/* The user has enough money, deduct the withdrawal amount from here total */
total -= withdrawal;
update_total_funds(total);

/* give the money to the user */
spit_out_money(withdrawal);
```

First the cash machine queries the bank account to get the amount of money in the account.
It also gets the amount the user wants to withdraw from some input.
The machine then checks that the user has enough money to satisfy the request amount to withdraw.
If not it returns an error.
If the check passes, the machine compute the new value for the account balance and updates it, then spits out the money.

This all seems fine when there is only one cash machine, but consider what happens when concurrency comes into play, i.e. when we have multiple cash machines.

Let's assume we now have 2 transactions happening approximately at the same time from 2 different cash machines.
This could happen in the case of a shared bank account with multiple credit cards for example.
We assume that there is £105 on the account at first, and that the first transaction is a £100 withdrawal while the second is a £10 withdrawal.
One of these transactions should fail because there is not enough money to satisfy both: `100 + 10 > 105`.

A possible scenario is as follows:
1. Both threads get the total amount of money in the account in their local variable `total`, both get 105.
2. Both threads perform the balance check against the withdrawal amount, both pass because `100 < 105` and `10 < 105`.
3. Thread 1 then updates the account balance with `105-100 = 5` and spits out £100.
4. Then thread 2 updates the account, with `105 - 10 = 95` and spits out £10.

A total of £110 has been withdrawn, which is superior to the amount of money the account had in the first place.
Even better, there is £95 left on the account.
We have created free money!

Of course this behaviour is incorrect.
It is called a **race condition**, when shared data (here the account balance) is accessed concurrently in write mode by at least 1 thread (here it is accessed in write mode by both cash machines i.e. threads).
We need locks to solve that issue, to protect the shared data against races.

## Locks: Motivational Example 2

Let's take a second, low-level example.
Consider the i++ statement in a language like java or C.
Let's assume that the compiler or the JVM is transforming this statement into the following machine instructions:

```bash
1. Load the current value of i from memory and copy it into a register
2. Add one to the value stored into the register
3. Store from the register to memory the new value of i
```

Let's assume that `i` is a global variable, accessible from 2 threads running concurrently on 2 different cores.
A possible scenario when the 2 threads execute `i++` approximately at the same time is:

<div style="text-align:center"><img src="include/08a-locks-barriers/mot-table1.svg" width=300 /></div>

In this table time is flowing downwards.
Thread 1 loads `i` in a register, it's 7, then increments it, it becomes 8, and then stores 8 back in memory.
Next, thread 2 loads `i`, it's 8, increment it to 9, and stores back 9.
This behaviour is expected and correct.

The issue is that there are other scenarios possible, for example:

<div style="text-align:center"><img src="include/08a-locks-barriers/mot-table2.svg" width=300 /></div>

Here, both threads load 7 at the same time.
Then they increment the local register, it becomes 8 in both cores
And then they both store 8 back.
This behaviour is not correct: once again we have a race condition because the threads are accessing a shared variable in write mode without proper synchronisation.

**Note that this race condition can also very well happen on a single core** where the threads' execution would be interlaced.

## Critical Sections

The parts of code in a concurrent program where shared data is accessed are called **critical sections**.
In our cash machine example, we can identify the critical section as follows:

```c
int withdrawal = get_withdrawal_amount();

/* critical section starts */
int total = get_total_from_account();
if(total < withdrawal)
    abort("Not enough money!");
total -= withdrawal;
update_total_funds(total);
/* critical section ends */

spit_out_money(withdrawal);
```
For our program to behave correctly without race conditions, the critical sections need to execute:
- **Serially**, i.e. only a single thread should be able to run a critical section at a time;
- **Atomically**: when a thread starts to execute a critical section, the thread must first finish executing the critical section in its entirety before another thread can enter the critical section.

A **lock** is a synchronisation primitive enforcing the serialisation and atomicity of critical sections.

## Locks

Each critical section is protected by its own lock.
Threads wishing to enter the critical section **try** to take the lock and:
- A thread attempting to take a free lock will get it.
- Other threads requesting the lock wait until the lock is released by its holder.

Let's see an example: we have two threads running in parallel.
They both want to execute a critical section approximately at the same time.
Both try to take the lock.
Let's assume thread 1 tried slightly before thread 2 and gets the lock, it can then execute the critical section while thread 2 waits:

<div style="text-align:center"><img src="include/08a-locks-barriers/lock3.svg" width=800 /></div>

Once it has finished executing the critical section, thread 1 releases the lock.
At that point thread 2 tries to take the lock again, succeeds, and start to execute the critical section:

<div style="text-align:center"><img src="include/08a-locks-barriers/lock4.svg" width=800 /></div>

When thread 2 is done with the critical section, it finally releases the lock:

<div style="text-align:center"><img src="include/08a-locks-barriers/lock5.svg" width=800 /></div>

With the lock, we are ensured that the critical section will always be executed serially (i.e. by 1 thread at a time) and atomically (a thread starting to execute the critical section will finish it before another thread enter it).

## Pthreads Mutexes

A commonly used lock offered by the POSIX thread library is the **mutex**, which stands for mutual exclusion lock.
After it is initialised, its use is simple: just enclose the code corresponding to critical sections between a call to `pthread_mutex_lock` and `pthread_mutex_unlock`:

```c
#include <pthread.h>

pthread_mutex_t mutex;

void my_thread_function() {

    pthread_mutex_lock(&mutex);

    /* critical section here */

    pthread_mutex_unlock(&mutex);

}

```

[`pthread_mutex_lock`](https://linux.die.net/man/3/pthread_mutex_lock) is used to attempt to take the lock.
If the lock is free the function will return immediately and the thread will start to execute the critical section.
If the lock is not free, i.e. another thread is currently holding it, the calling thread will be put to sleep until the lock becomes free: the calling thread will then take the lock, `pthread_mutex_lock` will return, and the thread can start to run the critical section.

[`pthread_mutex_unlock`](https://linux.die.net/man/3/pthread_mutex_unlock) is called by a thread holding a lock to release it.
The function returns immediately.

## Lock Usage Example

To present an example of lock usage, we are going to define the following data structure named bounded buffer:

<div style="text-align:center"><img src="include/08a-locks-barriers/bounded-buffer.svg" width=400 /></div>

It's a fixed size buffer in which can be accessed concurrently by multiple threads.
It's also a FIFO producer-consumer buffer: threads can deposit data in the buffer, and thread can also extract data in a first in first out fashion.

We are going to write a program that implements such a bounded buffer and executes 2 threads that access the buffer concurrently: one thread will continuously insert elements in the buffer, and the other will continuously extract elements from it.

The full code for our program is available [here](https://github.com/olivierpierre/comp35112-devcontainer/blob/main/08a-locks-barriers/lock.c).

**Bounded Buffer Declaration and Initialisation.**
This is the code defining the data structure representing the bounded buffer, as well as its initialisation/destruction functions.

```c
typedef struct {
    int *buffer;            // the buffer
    int max_elements;       // size of the buffer
    int in_index;           // index of the next free slot
    int out_index;          // index of the next message to extract
    int count;              // number of used slots
    pthread_mutex_t lock;   // lock protecting the buffer
} bounded_buffer;

int init_bounded_buffer(bounded_buffer *b, int size) {
    b->buffer = malloc(size * sizeof(int));
    if(!b->buffer)
        return -1;

    b->max_elements = size;
    b->in_index = 0;
    b->out_index = 0;
    b->count = 0;
    pthread_mutex_init(&b->lock, NULL);
    return 0;
}

void destroy_bounded_buffer(bounded_buffer *b) {
    free(b->buffer);
}
```

The data structure has a pointer towards a `buffer` that represent the buffer's content, a maximum size `max_elements`, two indexes indicating where to insert the next element in the buffer (`in_index`) and where to extract the next element from the buffer (`out_index`).
Another member of the data structure `count` keep track of the number of slots used in the buffer.
Finally, we have a lock that will protect the accesses to the buffer.
Note the type, `pthread_mutex_t`.

The initialisation function allocates memory for the buffer and sets the different members of the data structure to their initial value.
The lock is initialised with [`pthread_mutex_init`](https://linux.die.net/man/3/pthread_mutex_init).
The destruction function simply free the memory allocated for the buffer.

**Thread Data Structure.**
We will use the following data structure to represent each thread:

```c
typedef struct {
    int iterations;
    bounded_buffer *bb;
} worker;
```

`iterations` represents the number of elements the thread will insert/extract from the buffer, and `bb` is a pointer to the buffer.
Similarly to our example with the barrier, an instance of this data structure will be passed as parameter to each thread's function.

**Producer Thread.**
The producer thread will run the following code:

```c
void deposit(bounded_buffer *b, int message) {
    pthread_mutex_lock(&b->lock);

    int full = (b->count == b->max_elements);

    while(full) {
        pthread_mutex_unlock(&b->lock);
        usleep(100);
        pthread_mutex_lock(&b->lock);
        full = (b->count == b->max_elements);
    }

    b->buffer[b->in_index] = message;
    b->in_index = (b->in_index + 1) % b->max_elements;
    b->count++;

    pthread_mutex_unlock(&b->lock);
}

void *deposit_thread_fn(void *data) {
    worker *w = (worker *)data;

    for(int i=0; i<w->iterations; i++) {
        deposit(w->bb, i);
        printf("[deposit thread] put %d\n", i);
    }

    pthread_exit(NULL);
}
```

The thread runs the `deposit_thread_fn` functions which calls `deposit` in a loop.
`deposit` is going to access the buffer, so it starts by taking the lock.
Before depositing anything in the buffer, we need to check if it is full.
If it is the case, we need to wait for the buffer to become non-full.
We can't hold the lock doing so, that would prevent the consumer thread from removing elements from the buffer.
So we release the lock, sleep a bit with `usleep`, take the lock again, and check again if the buffer is full or not.
All of that is done in a loop which we exit once we know the buffer is indeed non-full, with the lock being held.
After that the insertion is made and the lock is released.

**Consumer Thread.**
The consumer thread runs the following code.

```c
int extract(bounded_buffer *b) {
    pthread_mutex_lock(&b->lock);

    int empty = !(b->count);

    while(empty) {
        pthread_mutex_unlock(&b->lock);
        usleep(100);
        pthread_mutex_lock(&b->lock);
        empty = !(b->count);
    }

    int message = b->buffer[b->out_index];
    b->out_index = (b->out_index + 1) % b->max_elements;
    b->count--;

    pthread_mutex_unlock(&b->lock);
    return message;
}

void *extract_thread_fn(void *data) {
    worker *w = (worker *)data;

    for(int i=0; i<w->iterations; i++) {
        int x = extract(w->bb);
        printf("[extract thread] got %d\n", x);
    }

    pthread_exit(NULL);
}
```

The consumer thread runs the `extract_thread_fn` function, which calls `extract` in a loop.
`extract` starts by taking the lock, and checking if the buffer is empty: if it is the case there is nothing to extract, and it must wait.
This is done in a loop in which the lock is released, and thread sleep with `usleep` to give the opportunity to the producer thread to insert one or more elements in the buffer.
Once it is certain that the buffer is not empty, we exit that loop with the lock held and perform the extraction, before releasing the lock.


## What Happens if We Omit the Locks

Without the locks, the program may seem to behave normally on small examples, especially when the number of threads is low or when the frequency of access to shared data is low.
This is quite bad because it's hiding race conditions.
Indeed, without the locks in reality many instances of incorrect program behaviour can (and will, given enough time) occur:

If two threads call `deposit` at the same time, they may write to the same slot in the buffer, one value being lost:
<div style="text-align:center"><img src="include/08a-locks-barriers/bounded-buffer-race1.svg" width=300 /> <img src="include/08a-locks-barriers/bounded-buffer-race2.svg" width=300 /><img src="include/08a-locks-barriers/bounded-buffer-race3.svg" width=300 /></div>


When the threads depositing concurrently increment the index for the next insertion, it can either be incremented only by one assuming a similar scenario as for the buffer content: in that case we just lose one of the inserted values:

<div style="text-align:center"><img src="include/08a-locks-barriers/bounded-buffer-race4.svg" width=300 /></div>

However, they can also increment the index twice and assuming we got the content overwrite problem we have a slot containing garbage value:

<div style="text-align:center"><img src="include/08a-locks-barriers/bounded-buffer-race5.svg" width=300 /></div>

We can have similar issues in case of unprotected concurrent calls to `deposit`.
And of course, additional problems occur in case of unprotected concurrent calls to `deposit` and `extract` at the same time, for example as both threads update the number of used slots we may loose consistency for that value.

Races may manifest in a number of ways in the program behaviour.
Sometimes the program can even seem to work fine.
As a result **concurrency issues can be extremely hard to reproduce and debug in large program, and it's important to get one's locking strategy right from the start**.
