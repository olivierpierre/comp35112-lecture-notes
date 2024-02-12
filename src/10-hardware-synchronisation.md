# Hardware Support for Synchronisation
---

You can access the slides for this lecture [here](https://olivierpierre.github.io/comp35112/lectures/10-hardware-synchronisation).

We have seen how synchronisation is crucial to parallel programming.
Here we are going to see what are the hardware mechanisms on modern CPUs that are used to implement synchronisation mechanisms such as locks.

## Implementing Synchronisation

When programming a multithreaded application that relies on shared memory for communication between threads, synchronisation mechanisms are required to protect critical section and ensure they execute without races.
There are multiple mechanisms (locks, barriers, etc.), but they are all closely related and most can be built on top of a common basic set of operations.

We have also seen that source code statement such as `i++` can be translated by the compiler into several instructions: they are not executed atomically, so they are unfit to help us implement synchronisation mechanisms.
If we implement a synchronisation primitive, for example a lock, we need to make sure that its access primitives (here lock and unlock operations) are executed atomically, otherwise the lock itself, which by nature is a form of shared data, will be subject to race conditions.
Intuitively this seems difficult.
Indeed, if we consider say the lock operation, it involves 2 memory accesses: 1) checking if the lock is available (reading a memory slot) and if so taking the lock (writing in the memory slot).
How can these 2 memory operation be realised atomically?
To achieve that we need hardware support.

We will illustrate how synchronisation primitives can be built on top of the relevant hardware mechanisms by presenting the implementation of the simplest lock possible: a **binary semaphore**, in a processor with a snoopy cache.
This lock can be held by at most 1 thread, and waiting threads use busy-waiting.

## Example: Binary Semaphore

Our binary semaphore is a single shared boolean variable **`S`** in memory, and the status of the lock (free/held) depends on its value:
- When `S == 1` the protected resource is free, i.e. the lock is ready to be taken.
- When `S == 0` the resource is busy and the lock is taken.

As mentioned earlier, operations on the semaphore should be **atomic**.
These operations are:
  - **`wait(S)`**: wait until `S != 0` then set `S = 0` (i.e. take the lock)
  - **`signal(S)`**: set `S = 1` (i.e. release the lock)

We have the lock and unlock operation.
Lock can also be called `wait`.
It consists in waiting for the lock to be free, i.e. for the variable to be different from 0, then setting it to 0 to indicate that we take the lock.
Once again this should be atomic, if two threads see that the lock is free and sets the variable at the same time, things won't work.
Then we have the unlock operation, called `signal`: we simply release the lock by setting the variable to 1.
This operation should also be atomic, a priori that is not an issue because it can be translated to a simple store, but even in that case we need to be careful: foe example if the variable is on 64 bits and we are on a 32-bit CPU, the compiler may translate S=1 into two load operations, making it non-atomic.

## Semaphore Usage to Protect Critical Sections

Recall that **critical sections** are the code sections where shared resources are manipulated, and that we want them to be executed in a serial fashion, i.e by 1 thread at a time, and atomically, i.e. when 1 thread starts to execute the critical section, it should finish before another thread can enter that critical section: this is what we want to achieve with the lock.


The lock is operated as follows.
We initialise the lock to `1`, i.e. ready to be taken.
A thread calls `wait` (i.e. tries to take the lock) before the critical section.
When several threads call `wait` at the same time, only one thread will atomically succeed and set it to `0`, the others will (busy) wait on the lock for it to go back to `1`.
When the thread holding the lock is done with its critical section, it releases it by calling `signal`, which sets the value of the lock back to `1`, and if there are waiting threads one of them will then be able to take the lock.
This ensures that the code protected by our semaphore is executed serially and atomically:

<div style="text-align:center"><img src="include/10-hardware-synchronisation/semaphore.svg" width=400 /></div>

## Atomicity Needed

How to implement `wait`?
A naive implementation in C would be something like that:

```c
// naive implementation in C:
while(S == 0);
S = 0;
```

While the semaphore value is 0 we spin waiting, and once it reaches 1 we set it to 0 to indicate that we got the lock.
The problem is that if we look at the machine code generated by the compiler from this source code, we see something like that (in pseudo-assembly):

```c
// address of `S` in `%r2`
loop: ldr %r1, %r2   // load the semaphore value
      cmp %r1, $0    // check if it is equal to zero
      beq loop       // if so lock is already taken, branch to try again i.e. spin
      str $0, %r2    // lock is free, take it
```

Our naive attempt at implementing `wait` compiles into the following operations.
We assume that the address of the lock variable `S` is in `%r2`.
We read the value of `S` it in a register `%r1` with a load operation.
Then we compare it to `0` and if it is equal to `0` it means the lock is taken, so we need to wait: the code branches back to try again.
Otherwise, the lock is free, and we use a store to set the value of `S` to `0` to indicate we have taken the lock.
As one can observe `wait` is not atomic at the machine code level and requires several instructions, including two memory accesses (reading/storing the value of `S`) to be executed.


As atomicity is not guaranteed, with e.g. 2 threads accessing the semaphore, the following scenario can occur:

<div style="text-align:center"><img src="include/10-hardware-synchronisation/scenario.svg" width=250 /></div>

First thread 1 does the load and thread 2 does the same right after.
Both do the comparison, see that it's not `0` so they don't branch, and then they both do the store.
Both threads have taken the lock, which of course is not correct behaviour.

## Atomic Instructions

So it is clear that wait must be atomic, i.e. the entire lock taking operation must be done by a single thread at once.
This requires special instructions supported by the hardware, called **atomic instructions**.
These will realise at once all the operations required for the lock taking operation, without the possibility to be interrupted in the middle, and with the guarantee that no other core in the system will access memory at the same time.

Implementing synchronisation primitives like `wait()` with these atomic instructions involves a compromise between complexity and performance.
There are also various way for the hardware to implement these atomic instructions, with different performance/complexity tradeoffs.
Also note that variable `S` may be cached, and the desired atomic behaviour might require coherence operations in the cache.

## Atomic Test-And-Set Instruction

An example of atomic instruction is **test-and-set**.
It is present in many CPUs (e.g. Motorola 68K).
It takes a register containing an address at parameter and performs, atomically, the following things:
- It checks that the memory slot addressed by the register contains `0`, and if it is the case, it sets the content of that memory slot to `1` as well as the CPU zero flag.
- If the memory slot was not 0, the zero flag is cleared.

Here is an example of usage in pseudo assembly, we just execute test and set (`tas`) on a memory slot which address is present in the register `%r2`:

```c
tas %r2
```


If memory location addressed by `%r2` contains `0`, `tas` switches its content to `1` and set the CPU zero flag, otherwise it clears the zero flag and does not update memory.

The behaviour of this instruction is atomic: it cannot be interrupted, and no other core can modify what is pointed by `%r2` in memory while the `tas` runs.


Let's illustrate an example.
Say we want to do a test and set on address `0x42`.
We place that address in a register, say `%r2`.
And we execute `tas %r2`.
Now assume address `0x42` contains `0`.
Test and set will then switch it to `1`, and will also set the zero flag of the core to 1:
<div style="text-align:center"><img src="include/10-hardware-synchronisation/tas1.svg" width=700 /></div>

If instead before the test and set address `0x42` contains something else than 0, for example 1, test and set won't touch it and will clear the zero flag on the core:
<div style="text-align:center"><img src="include/10-hardware-synchronisation/tas2.svg" width=700 /></div>

## Our Semaphore with `tas`

We can implement our semaphore with the test and set atomic instruction as follows.
We have our lock S in memory at a given address,
This is the `wait` operation, i.e. trying to take the lock:

```c
// Address of S in %r2
// Loops (i.e. wait) while [%r2] != 0
loop: tas %r2
      bnz loop // branch if zero flag not set
```

We have the address of our lock in `%r2`.
We try a test and set, and if the lock's value is `1`, we consider that the lock is not free
In that case the test and set will not modify the lock's value and will clear the zero flag.
So the `bnz` (branch if not zero) will go back to the `loop` label, and we try again, i.e. we spin, until the lock is free.

When the lock is free its value will be `0` so test and set will set it to `1`, we won't branch, and we'll continue with the lock held.

This is the implementation of the lock release operation, i.e. `signal`:

```c
// We assume that basic store operations
// are atomic
// Address of S in %r2
str $0, %r2
```

Here we assume here that the store assembly instruction is atomic.
Releasing the lock simply consist in setting the value of the lock to `0` to indicate that it is free to take.

> Note that here **we inverted the meaning of the lock's values that we gave previously**.
> With test and set, 0 means the lock is free, and 1 means it is not.
> The lock also needs to be initialised to 0.

## What About the Cache?

If we assume a system with no cache the semaphore operations with test and set are pretty straightforward: `S` is a single shared variable in memory, and it is locked with test and set and released with a simple store.
One thing to note is that atomic operations such as test and set are classified as **read-modify-write** (RMW).
These are the three operations they do atomically, for example test and set reads a memory slot into a register and may modify that value in the register and write it back to memory.
For this to be done atomically the CPU needs to prevent access to memory from the other cores during the execution of the RMW operation by a core.

However, processors do have caches, and by definition `S` is shared: this is the fundamental purpose of a semaphore.
Multiple cores are therefore likely to end up with a copy of `S` in their cache.

## Test-and-Set and the Cache

So for all the operations realised by a RMW instruction to be atomic, the core needs to lock the snoopy bus for the duration of the atomic instruction.
This basically prevents all the other cores to do a write in case they would try to write on the shared variable.
Of course this affects performance.
Further, a particular observation is that test and set is a read only operation when the test fails (when the instruction reads something else than `0`), and in that case this locking of the bus, slowing down cache coherence traffic from other cores, was somehow wasted.

We can avoid this issue with a trick, a particular way to use test and set, called **test and test and set**.

## Test-and-test-and-set

Before looking at assembly, let's see in pseudocode how using test-and-test-and-set for our semaphore taking operation `wait` looks like that:

```c
do {
    while(test(S) == 1);    // traditional load
} while (test-and-set(S));  // test-and-set
```

We have our loop, and in the loop body we spin as long as the lock seems to be taken.
For this we use a normal test, which is cheap because it does not lock the snoopy bus.
And only when the lock seem to be available, i.e. when the test sees that the variable is 0, we do a costly test and set.
This test and set has good chances to succeed.
And if it does not, we go back to spinning with a simple test.

In assembly, `wait` using test-and-test-and-set looks like that:

```c
// address of S in %r2
loop: ldr %r1, %r2   // standard, non atomic (i.e. cheap) load
      cmp %r1, $1
      beq loop       // lock taken
      tas %r2        // lock seems free, try to take it with a costly tas
      bnz loop       // failed to take the lock, try again
```
]

We load the address of the semaphore variable in `%r1`.
We do the simple test, if `S` is `1` the lock is not available, and we branch back to spin.
If `S` is not 1, the locks appears to be free, we can try to take it with an atomic test and set.
If the test and set does not succeed, another core beat us to it, and we branch back to spin.
The waiting loop is only executing a normal load operation `ldr` most of the time, which is internal to the core and its cache, so no bus cycles are wasted.

## Other Synchronisation Primitives

There are other types of atomic instructions implemented in modern CPUs.

**Fetch-and-add** returns the value of a memory location and increments it atomically:

```c
// in pseudocode
fetch_and_add(addr, incr) {
    old_val = *addr;
    *addr += incr;
    return old_val;
}
```
**Compare-and-swap** compares the value of a memory location with a value (in a register) and swaps in another value (in a register) if they are equal:

```c
// in pseudocode
compare_and_swap(addr, comp, new_val) {
    if(*addr != comp)
        return false;

    *addr = new_val;
    return true;
}
```

All these instructions are *read-modify-write* (RMW), with the need to lock the snoopy bus during their execution.
However, RMW instructions are not really desirable with all CPU designs: their nature does not fit well with simple RISC pipelines, where RMW in effect a CISC instruction requiring a read, a test and a write.
In the next lecture we will see another form of hardware mechanism used to implement synchronisation primitives, more suitable to RISC architectures: **load-linked and store-conditional**.