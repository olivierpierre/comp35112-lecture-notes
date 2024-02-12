# Load-Linked and Store-Conditional
---

You can access the slides for this lecture [here](https://olivierpierre.github.io/comp35112/lectures/11-ll-sc).

We have seen that read-modify-write atomic instructions could implement synchronisation, but that their complexity made them inefficient in certain situations.
Here we are going to see a couple of simple hardware instructions working together to implement a synchronisation mechanism: **load-linked and store-conditional** (LL/SC).

LL/SC is a synchronisation mechanism used in modern RISC processors such as ARM, PowerPC, RISC-V, and so on.
It relies on 2 separate instructions that slightly differ from traditional loads and stores: **load-linked** and **store-conditional**.
They have additional effects on processor state, which allows them to act atomically as a pair while avoiding holding the cache coherence bus until completion.

## Load-Linked

Let's first see load linked.
It takes two registers as parameters:

```asm
ldl %r1, %r2
```

Similar to a traditional load instruction, load linked loads register `%r1` with the value from memory at the address in register `%r2`.
It also sets a special **load linked flag** on the core which executes it.
And it records the address placed in `%r2` inside a register on the core, named **locked address register**.
The core holds some state related to this load link instruction.

## Store-Conditional

Store conditional also takes two parameters:

```asm
stc %r1, %r2
```

The instruction *tries* to store the value in `%r1` into memory, at the address in register `%r2`.
Different from a traditional store, it only succeeds if the load linked flag is set.
After the store conditional is executed, the value of the load linked flag is returned in `%r1`.
This value represents whether or not the store was successful.
After the operation the load-linked flag is cleared.

## The Load-Linked Flag

The reason to be for the load linked flag is to indicate if the memory slot accessed has been modified by another core between the load-linked and the store-conditional: on that slot: **after a load-linked, the load linked flag is cleared if another core writes to the locked address**.
This is detected by comparison with the "locked address register".
The processor snoops the memory address bus to detect this.

Let's take an example, we have the memory, and two cores each with the LL/SC flag:

<div style="text-align:center"><img src="include/11-ll-sc/llc-sc-1.svg" width=300 /></div>

Core 1 does a load link from address 12 and its flag is set:

<div style="text-align:center"><img src="include/11-ll-sc/llc-sc-2.svg" width=300 /></div>

But before core 1 does his store conditional, core 2 writes to address 12.
This automatically clears the flag on core 1:

<div style="text-align:center"><img src="include/11-ll-sc/llc-sc-3.svg" width=300 /></div>

The subsequent store-conditional from core 1 will fail:

<div style="text-align:center"><img src="include/11-ll-sc/llc-sc-4.svg" width=300 /></div>

Other events clearing the flag include context switches and interruptions.
These change the control flow intended by the programmer.
Overall the load linked flag **allows to be sure that a LL/SC pair is executed atomically or not with respect to the locked address**.

## Our Semaphore with LL/SC

Let's have a look at how we can implement a semaphore with LL/SC in assembly:

```asm
/* Address of the lock in %r2 */

loop: ldl %r1, %r2
      comp $0, %r1  /* S == 0 (semaphore already taken)? */
      beq loop      /* if so, try again */
      mov $0, %r1   /* looks like it's free, prepare to take the semaphore */
      stc %r1, %r2  /* Try to take it */
      cmp $1, %r1   /* Did the write succeed? */
      bne loop      /* If not, someone beat us to it... try again */

      /* critical section here... */

      st $1, %r2    /* release the semaphore with a simple store */
```

The lock is a simple byte in memory, when it is `1` the semaphore is free, when it is `0` the semaphore is taken.
We assume the address of the lock is stored in `%r2`.
We start by doing a load link `ldl` from this address into `%r1`.
If the value is `0` the semaphore is taken, so we branch back to the beginning of the loop.
If it's `1` the semaphore seems to be free, so the code must now try to take it.
We put the constant `0` into `%r1` and then try to store this value into the byte representing the lock, with a store conditional in the address that is in `%r2`.
Now remember that store conditional may fail if someone else wrote to the lock byte between the moment we checked its value with the load-linked.
So we check if our store conditional succeeded by checking if `%r1` contains `1`.
If not, someone beat us to the lock, and we have to try again, we branch back.
If we got the lock, we execute the critical section, and release the lock with a simple store.

The code highlighted below with the `*` prefix executes atomically with respect to the memory location pointed by `%r2`, between the moment the thread thinks that the lock is free, and the moment it actually takes the lock:

```c
/* Address of the lock in %r2 */

loop: ldl %r1, %r2
*     comp $0, %r1  /* S == 0 (semaphore already taken)? */
*     beq loop      /* if so, try again */
*     mov $0, %r1   /* looks like it's free, prepare to take the semaphore */
      stc %r1, %r2  /* Try to take it */
      cmp $1, %r1   /* Did the write succeed? */
      bne loop      /* If not, someone beat us to it... try again */

      /* critical section here... */

      st $1, %r2    /* release the semaphore with a simple store */
```

If another entity manages to take the lock (in other words to write to the address in `%r2`) during the highlighted section (or the thread is descheduled), or if something breaks the  execution flow like an interrupt or a context switch, the `stc` executed as part of the lock taking operation will fail and the loop will repeat.
Otherwise, everything between `ldl` and `stc` must have executed as if "atomically" so the core has the lock.
Any write to that location/interrupt/context switch during the atomic part will lead to `stc` failing.

## The Power of LL/SC

With instructions like test-and-set, the load and the store can be guaranteed to be atomic by RMW behaviour.
Although the code between LL and SC is not atomic in absolute, we know that anything between the `ldl` and the `stc` has executed atomically **with respect to the synchronisation variable**.
This can be more powerful than `tas` for certain forms of usage, for example LL/SC are an easy and efficient way to implement the behaviour of fetch-and-add and other atomic instructions.
They also reduce the number of special instructions that need to be supported by the architecture, and are well suited to RISC processors.

## Spinlocks

All the versions of the `wait` operation we developed for our semaphore use a busy loop to implement the act of waiting.
Threads never go to sleep and keep trying to get the lock over and over again.
This is called busy waiting or spinning, and locks using that method for waiting are named **spinlocks**.
They monopolise the processor and can hurt performance when the lock is contented.

Putting waiting threads to sleep, in other words scheduling them out of the CPU, would be much more efficient from the resource usage point of view: when a thread sleeps waiting for a lock to be free, it relinquishes the core and another task/thread can be scheduled on that core.
There are various more sophisticated forms of locking to address this.
They are implemented at the OS level and the basic hardware support is the same.
We'll say a few words about OS support in the next lecture.
