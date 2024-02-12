# Synchronisation in Parallel Programming - Locks and Barriers
---

You can access the slides for this lecture [here](https://olivierpierre.github.io/comp35112/lectures/08b-condition-variables).
All the code samples given here can be found online, alongside instructions on how to bring up the proper environment to build and execute them [here](https://github.com/olivierpierre/comp35112-devcontainer).

We have seen previously two synchronisation mechanisms that are barriers as well as locks.
Here we will present third one, condition variables.

## Event Signalling

Recall our bounded buffer example from the lecture on locks, in which producer/consumer threads may need to wait for the buffer to become non-full/non-empty.
For example a thread attempting to extract from an empty buffer needs to wait for it to become non-empty, and same thing for a thread attempting to deposit in a buffer that is full
There are two intuitive solutions to implement that wait.
The one we saw previously involves **sleeping** in a loop until the condition we wait for becomes true, for example a producer thread waits until the buffer becomes non-full as follows:

```c
while(full) {
    pthread_mutex_unlock(&b->lock);
    usleep(100);
    pthread_mutex_lock(&b->lock);
    full = (b->count == b->max_elements);
}
```

Another approach is **busy waiting**: we get rid of the sleep and the thread will keep trying non-stop until the condition becomes true:

```c
while(full) {
    pthread_mutex_unlock(&b->lock);
    /* busy wait */
    pthread_mutex_lock(&b->lock);
    full = (b->count == b->max_elements);
}
```

Note that in that case we still need to unlock the buffer's lock to give a chance to other threads to access the queue and make the condition we wait for become true: without this other threads will starve.

**Both solutions are suboptimal**: sleeping for an arbitrary time may lead to long wakeup latencies, and busy waiting wastes a lot of CPU cycles because the threads keeps trying non-stop.

Let's see an example with a thread trying to deposit in a full buffer.
With a sleep-based method things look as follows:

<div style="text-align:center"><img src="include/08b-condition-variables/condvar-sleep.svg" width=600 /></div>

Thread 2 is trying to deposit in the buffer, but the buffer is full.
So at regular intervals, here every 100 microseconds, thread 2 going to check if the buffer is still full and if so it will sleep for another 100 microseconds.
The good thing here is that during all that time, something else can use that CPU core.
Imaging now that in the meantime another thread, thread 1, extracts something from the queue.
Once the execution of thread 1's critical section is done, thread 2 could actually perform its deposit operation right away because the buffer is not full anymore.
However, thread 2 is in the middle of its 100 microseconds sleep, so it will have to wait until the end of that sleep operation to be able to start making progress.
This is why **sleeping may lead to long wakeup delays**.

Let's now examine the same scenario, but with a busy-waiting approach:

<div style="text-align:center"><img src="include/08b-condition-variables/condvar-spin.svg" width=600 /></div>

Because it keeps checking when the buffer becomes non-full, thread 2 has a much shorter wakeup delay compared to the sleeping solution.
However, during the entire busy waiting period, thread 2 monopolises the CPU and nothing else can use that core: **busy waiting wastes CPU cycles**.

## Condition Variables

A condition variable is a synchronisation primitive that can address this problem.
It is used for event signalling between threads: it allows to signal threads that sleep waiting for a conjunction of two events:
- **a lock becoming free**, and 
- **an arbitrary condition becoming true**, for example the buffer becoming non-full or non-empty.

One may wonder why is there the condition regarding the lock in addition to the arbitrary event.
The reason is first that the implementation requires it, the condition variable needs to be itself protected from concurrent accesses with the lock.
Second, such a primitive is generally used to synchronise access to shared data structures which is something that itself requires a lock.

With condition variables you get the best of both worlds: not only a waiting thread wakes up with a very low latency, but it also waits by sleeping so it does not hang the CPU:

<div style="text-align:center"><img src="include/08b-condition-variables/condvar-cond.svg" width=500 /></div>

## Applying Condition Variables to Our Example

How can we use a condition variable with our bounded buffer example?
Assume a thread wants to deposit in a buffer that is full:

<div style="text-align:center"><img src="include/08b-condition-variables/bb-condvar1.svg" width=400 /></div>

We are going to use a condition variable to indicate when the buffer becomes non-full.
With the buffer's lock held, the thread will call a function to sleep on that condition variable:

<div style="text-align:center"><img src="include/08b-condition-variables/bb-condvar2.svg" width=400 /></div>

Later say another thread extracts an element from the buffer.
If the extracting thread realises it made the buffer non-full, it calls a function to signal that the condition relative to the condition variable has happened:

<div style="text-align:center"><img src="include/08b-condition-variables/bb-condvar4.svg" width=400 /></div>

When the extracting thread releases the lock, that will trigger the awakening of the thread waiting, which will grab the lock and finally perform its deposit:

<div style="text-align:center"><img src="include/08b-condition-variables/bb-condvar5.svg" width=400 /></div>

We similarly use a condition variable to represent the buffer becoming non-empty.
When a thread attempts to deposit an element into an empty buffers it waits on that condition variable.
Another thread depositing something and realising it makes the buffer non-empty will then signal that variable, waking up the deposit thread, so it can perform its operation.

<div style="text-align:center"><img src="include/08b-condition-variables/bb-condvar6.svg" width=400 /></div>

## Condition Variables with the POSIX Thread Library

The multiple steps we just presented actually translate to something quite simple in the code because the condition variable's implementation takes care of a lot of things under the hood.
Let's see how we the code looks like for our bounded buffer example, this time using a condition variable to signal the events corresponding to 1) the buffer becoming non-full and 2) the buffer becoming non-empty.
We will only present here the subset of the program that is relevant to the use of condition variables, but you can access the entire program [here](https://github.com/olivierpierre/comp35112-devcontainer/blob/main/08b-condition-variables/condvar.c).

**Bounded Buffer Representation and Initialisation.**
The data structure representing the bounded buffer is updated to include 2 condition variable: one to notify threads waiting on full buffer (`condfull`), and the other to notify threads waiting on empty buffer (`condempty`):

```c
typedef struct {
    int *buffer;            // the buffer
    int max_elements;       // size of the buffer
    int in_index;           // index of the next free slot
    int out_index;          // index of the next message to extract
    int count;              // number of used slots
    pthread_mutex_t lock;   // lock protecting the buffer
    pthread_cond_t condfull;    // condvar to notify threads waiting on full buffer
    pthread_cond_t condempty;   // condvar to notify threads waiting on empty buffer
} bounded_buffer;
```

The bounded buffer initialisation code is updated with the initialisation of both condition variables:

```c
int init_bounded_buffer(bounded_buffer *b, int size) {
    b->buffer = malloc(size * sizeof(int));
    if(!b->buffer)
        return -1;

    b->max_elements = size;
    b->in_index = 0;
    b->out_index = 0;
    b->count = 0;

    /* Initialize mutex and both condition variables */
    if(pthread_mutex_init(&b->lock, NULL) || pthread_cond_init(&b->condfull, NULL) ||
            pthread_cond_init(&b->condempty, NULL))
        return -1;

    return 0;
}
```

Condition variable initialisation is done with [`pthread_cond_init`](https://linux.die.net/man/3/pthread_cond_init).
Note the type of the condition variable, `pthread_cond_t`.

The function `deposit` is updated as follows:

```c
void deposit(bounded_buffer *b, int message) {
    pthread_mutex_lock(&b->lock);

    int full = (b->count == b->max_elements);

    while(full) {
        /* Buffer is full, use the condition variable to wait until it becomes
         * non-full. */
        if(pthread_cond_wait(&b->condfull, &b->lock)) {
            perror("pthread_cond_wait");
            pthread_exit(NULL);
        }

        /* pthread_cond_wait returns (with the lock held) when the buffer
         * becomes non-full, but the buffer may have been accessed by another
         * thread in the meantime so we need to re-check and cotninue waiting
         * if needed. */
        full = (b->count == b->max_elements);
    }

    b->buffer[b->in_index] = message;
    b->in_index = (b->in_index + 1) % b->max_elements;

    /* If the buffer was empty, signal a waiting thread. This works only if
     * max 2 threads access the buffer concurrently. For more, broadcast should
     * be used instead of signal. More about that in the next lecture (the one
     * entitled "More about Locks"). */
    if(b->count++ == 0)
        if(pthread_cond_signal(&b->condempty)) {
            perror("pthread_cond_signal");
            pthread_exit(NULL);
        }

    pthread_mutex_unlock(&b->lock);
}
```

When `deposit` detects that the buffer is full, it waits on the condition variable until it becomes non-full.
That wait is achieved by calling [`pthread_cond_wait`](https://linux.die.net/man/3/pthread_cond_wait), which takes a pointer to the condition variable to wait upon, as well as a pointer to the corresponding lock.
It should be called with the lock held.
The implementation of `pthread_cond_wait` operation will take care of releasing the lock and putting the thread to sleep,
On the other side, an extracting thread realising that the buffer becomes non-full will signal that condition variable, and the waiting thread will wake up, the implementation of `pthread_cond_wait` will take care of taking the lock again before returning.
Once it returns, although the thread hold the lock, it is still needed to check the condition, before another thread could have been able to deposit an element in the meantime,
If the buffer is still non-full, the thread can proceed with the deposit.
Otherwise, it starts the wait operation again.

`deposit` also takes care of signalling potential threads waiting on the other condition variable (`condempty`) that the buffer has become non-empty.
After its insertion is done, it checks that the amount of elements of the buffer is equals to `0` and if so, it signals the condition variable with [`pthread_cond_signal`](https://linux.die.net/man/3/pthread_cond_signal).


The `extract` function looks similar:

```c
int extract(bounded_buffer *b) {
    pthread_mutex_lock(&b->lock);

    int empty = !(b->count);

    while(empty) {
        /* Buffer is empty, wait until it is not the case using the condition
         * variable. */
        if(pthread_cond_wait(&b->condempty, &b->lock)) {
            perror("pthread_cond_wait");
            pthread_exit(NULL);
        }
        empty = !(b->count);
    }

    int message = b->buffer[b->out_index];
    b->out_index = (b->out_index + 1) % b->max_elements;

    /* If the buffer becomes non-full, signal a potential deposit thread waiting
     * for that. */
    if(b->count-- == b->max_elements) {
        if(pthread_cond_signal(&b->condfull)) {
            perror("pthread_cond_signal");
            pthread_exit(NULL);
        }
    }

    pthread_mutex_unlock(&b->lock);
    return message;
}
```
A thread attempting to extract from an empty buffer will wait on it using the corresponding condition variable and `pthread_cond_wait`.
Upon extracting an element, a thread will also signal the other condition variable that the buffer has become non-full, which will wake up any deposit thread waiting.
