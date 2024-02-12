# More about Locks
---

You can access the slides for this lecture [here](https://olivierpierre.github.io/comp35112/lectures/09-more-about-locks).
All the code samples given here can be found online, alongside instructions on how to bring up the proper environment to build and execute them [here](https://github.com/olivierpierre/comp35112-devcontainer).

We have seen previously that locks are practical, and in many situations indispensable, to protect critical sections.
However, their use is not without dangers.
This is what we will cover here, along with a bit of additional information about locks.

## Dangers with Locks

One of the common issues with lock is the **deadlock**.
It happens when, due to improper use of locks, the program is stuck waiting indefinitely, trying to take a lock it will never acquire.
We can illustrate it with this picture:

<div style="text-align:center"><img src="include/09-more-about-locks/deadlock.png" width=500 /></div>

Looking at the center part, we can observe that:
- The white truck is stuck because the white car in front of it cannot move;
- The white car in question cannot move because the gray car in front of it is stuck;
- And the gray car is stuck because the white truck cannot move.

The entire situation is blocked!

As soon as a program uses more than one lock, it opens the possibility for deadlocks if the lock/unlock operations are not made in the proper way.
Let's take an example:

```c
typedef struct {
    double balance;
    pthread_mutex_t lock;
} account;

void initialise_account(account *a, double balance) {
    a->balance = balance;
    pthread_mutex_init(&a->lock, NULL);  // return value checks omitted for brevity
}

void transfer(account *from, account *to, double amount) {
    if(from == to)
        return;  // can't take a standard lock twice, avoid account transfer to self

    pthread_mutex_lock(&from->lock);
    pthread_mutex_lock(&to->lock);

    if(from->balance >= amount) {
        from->balance -= amount;
        to->balance += amount;
    }

    pthread_mutex_unlock(&to->lock);
    pthread_mutex_unlock(&from->lock);
}
```

We have a data structure `account` representing a bank account, with a balance, and an associated lock protecting the balance from concurrent access.
`initialise_account` sets a starting balance in the account and initialises the lock.
We also have a function, `transfer`, that moves a given amount of money from one account to another.
This function is supposed to be called from multithreaded code, so it will access the locks relative to each account.
`transfer` first checks that `from` and `to` do not point to the same account, because a standard pthread mutex cannot be taken twice (that would result in undefined behaviour).
Next we first take the lock for the `from` account, then the lock for the `to` account.
We perform the transaction if there is enough money, then release the locks in order.

In order to try out how this code behaves at runtime, one can find the full program is available [here](https://github.com/olivierpierre/comp35112-devcontainer/blob/main/09-more-about-locks/deadlock.c).
At runtime, there is a non-negligible chance that this program hangs indefinitely, because it contains a deadlock.
Note that the deadlock may take multiple runs to occur, because like most concurrency bugs, it happens in specific scheduling conditions.

# Dangers with Locks

How does this deadlock happen?
Here's a scenario that leads to it:

<div style="text-align:center"><img src="include/09-more-about-locks/deadlock.svg" width=400 /></div>

We have two threads calling the `transfer` method approximately at the same time.
Thread 1 calls `transfer` from account `a` to account `b` and the other thread calls transfer from account `b` to account `a`.
Thread 1 gets `a`'s lock first, then it tries to get `b`'s lock.
But in the meantime thread 2 took `b`'s lock and is now trying to lock `a`.
No thread can continue, and the system is stuck, it's a deadlock.

One possible solution to that issue is to give each account a unique identifier that can be used to establish an ordering relationship between accounts.
We use this to sort the objects to lock so that, when given 2 accounts, **all threads will always lock them in the same order**, avoiding the deadlock:

```c
typedef struct {
    int id;              // unique integer id, used to sort accounts
    double balance;
    pthread_mutex_t lock;
} account;

void transfer(account *from, account *to, double amount) {
    if(from == to) return;
    pthread_mutex_t *lock1 = &from->lock, *lock2 = &to->lock;

    if(from->id < to->id) {   // always lock the accounts in the same order
        lock1 = &to->lock;
        lock2 = &from->lock;
    }

    pthread_mutex_lock(lock1);
    pthread_mutex_lock(lock2);
    if(from->balance >= amount) {
        from->balance -= amount;
        to->balance += amount;
    }
    pthread_mutex_unlock(lock2);
    pthread_mutex_unlock(lock1);
}
```

You can access the full version of this program [here](https://github.com/olivierpierre/comp35112-devcontainer/blob/main/09-more-about-locks/deadlock-fixed.c).

In this example we use a simple unique integer `id` for each account.
In the transfer function we use the `id` to sort the accounts.
Establishing such an ordering allows us to always take the locks in the same order, so when a thread calls transfer from `a` to `b` while another calls transfer from `b` to `a`, both will lock the accounts in the same order and only one can obtain both locks at once.

## The Lost Wake-up Issue

Another issue with badly handled synchronisation is the **lost wake-up**.
It happens when the programmer mistakenly uses conditions variables.
Let's take an example with the bounded buffer code from [last lecture](08b-condition-variables.md#applying-condition-variables-to-our-example).

Something that can happen is the following scenario.
Assume we have an empty bounded buffer and 4 threads, A/B/C/D.
Thread A tries to extract something from the empty queue and waits.
Thread B tries the same, and waits:

<div style="text-align:center"><img src="include/09-more-about-locks/lost-wakeup-2.svg" width=300 /></div>

Next thread C deposits something in the empty queue, so it signals a waiting thread.
Let's assume it is thread A:

<div style="text-align:center"><img src="include/09-more-about-locks/lost-wakeup-3.svg" width=300 /></div>

At the same time thread D also deposits in the queue, which is non-empty, so there is no need to signal a waiter:

<div style="text-align:center"><img src="include/09-more-about-locks/lost-wakeup-4.svg" width=300 /></div>

Thread A wakes up, and extracts an element from the queue.
And in the end, B is never awoken, even though the queue is not empty:

<div style="text-align:center"><img src="include/09-more-about-locks/lost-wakeup-5.svg" width=300 /></div>


- In this scenario, the fix would be to use the `pthread_cond_broadcast()` function to signal **all** waiters when someone deposits in an empty queue, than `pthread_cond_signal()`, that signals only a single thread.


## Locking Granularity

The granularity of locking defines how large are the chucks of code protected with a single lock.
It is an important design choice when developing a parallel program.
Large blocks of code protected by locks generally access a mix of shared and non-shared data.
In that case we talk about **coarse-grained** locking:

```c
lock();
/* access a mix of shared and unshared data */
unlock();
```


Because locking serialises the entirety of the protected code, coarse-grained locking limits parallelism.
On the other hand one can have many lock operations, each protecting small quantities of code, this is **fine-grained** locking:

```c
lock();
/* access shared data */
unlock();
/* access non-shared data */
lock();
/* access shared data */
unlock();
```

Fine-grained locking increases parallelism.
However, it may lead to a high overhead from obtaining and releasing many locks.
The program is also harder to write.
So it really is a trade-off: for example when updating certain elements in an array, we can either lock the entire array (coarse-grained locking), or we could lock only the individual element(s) being changed (fine-grained locking).

## Reentrant Lock

By default, a thread locking a lock it already holds results in **undefined behaviour**.
Let's go back to our example and assume that `transfer` does not check if `from` and `to` don't point to the same account:

```c
void transfer(account *from, account *to, double amount) {
  /* no check if from == to */

  // BUGGY when from == to if lock is not reentrant
  pthread_mutex_lock(from->lock);
  pthread_mutex_lock(to->lock);

  if(from->balance >= amount) {
    from->balance -= amount;
    to->balance += amount;
  }
  /* ... */
}
```

Assuming the thread calls this version of `transfer` with the same account by pointed by the `from` and `to` parameters, it will then take the account's lock once, then attempt to take it a second time while already holding it.
On a standard lock this results in undefined behaviour, it's a bug.
This is because by default pthread mutexes are not **reentrant**.
A reentrant lock is a lock that can be taken by a thread that already holds it.

We can update our example program to use reentrant lock:
```c
void initialize_account(account *a, int id, double balance) {
    a->id = id;
    a->balance = balance;

    pthread_mutexattr_t attr;
    if(pthread_mutexattr_init(&attr))
        errx(-1, "pthread_mutexattr_init");
    if(pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE))
        errx(-1, "pthread_mutexattr_settype");
    if(pthread_mutex_init(&a->lock, &attr))
        errx(-1, "pthread_mutex_init");
}
```

The full program's code is available [here](https://github.com/olivierpierre/comp35112-devcontainer/blob/main/09-more-about-locks/reentrant.c).

We can specify that a mutex is reentrant by using the second parameter of the `pthread_mutex_init` function.
It takes a pointer to a data structure of type `pthread_mutexattr_t`, that allows to set various attributes to a created mutex.
It is initialised with `pthread_mutexattr_init`, and we indicate the fact that we want to set the reentrant (`PTHREAD_MUTEX_RECURSIVE`) attribute with `pthread_mutexattr_settype`.

## Other Lock Types

In addition to the mutex, pthread gives you access to other lock types.
While the mutex can only be held by a single thread, even if it is reentrant, a **semaphore** is a lock that can be held by several threads at once.
It is useful for example to arbitrate access to a set of resources that are in limited number.

Further we have the **spinlock**.
Contrary to a mutex that, when it cannot take a lock, has the operating system put the calling thread to sleep, the spinlock uses **busy waiting**.
In other words it spins, meaning it monopolises the CPU in a loop until it can take the lock.
This wastes CPU cycles but gives a better wakeup latency compared to the mutex.

And finally we have **read-write locks**, they allow concurrent reads, but serialise write operations.
We will develop a bit on these in the future lecture regarding operating systems.

For more information about how to use these locks, see the Oracle [Multithreaded Programming Guide](https://docs.oracle.com/cd/E53394_01/pdf/E54803.pdf) (chapter 4).

- **Semaphores**
  - Mutexes that can be hold by multiple threads
  - Useful to coordinate access to a fixed number of resources
- **Spinlocks**
  - Threads attempting to hold an unavailable lock will **busy-wait**
      - As opposed to going to sleep for mutexes
      - Monopolises CPU, lower wakeup latency
- **Read-write locks**
  - Allows concurrent reads and exclusive writes

For more information see the multithreaded programming guide:
https://bit.ly/3FGt3k2
