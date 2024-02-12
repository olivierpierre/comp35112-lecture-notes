# Shared Memory Multiprocessors
---

You can access the slides for this lecture [here](https://olivierpierre.github.io/comp35112/lectures/04-shared-memory-multiprocessors).

We have previously introduced how to program with threads that share memory for communication.
Here we will talk about how the hardware is set up to ensure that threads running on different cores can share memory by seeing a common address space.
In particular, we will introduce the issue of cache coherency on multicore processor.

## Multiprocessor Structure

The majority of general purpose multiprocessors are **shared memory**.
In this model all the cores have a unified view on memory, e.g. in the figure on the top of the example below they can all read and write the data at address x in a coherent way.
This is by opposition to distributed memory systems where each core or processor has its own local memory, and does not necessarily have a direct and coherent access to other processor's memory.

<div style="text-align:center"><img src="include/04-shared-memory-multiprocessors/shm.svg" width=250 /></div>

Shared memory multiprocessors are dominant because they are easier to program.
However, shared memory hardware is usually more complex.
In particular, each core on a shared memory multiprocessor has its own local cache, 
Here  we will introduce the problem of cache coherency in shared memory multiprocessor systems.
In the next lecture we'll see how it is managed concretely.

## Caches

A high performance uniprocessor has the following structure:

<div style="text-align:center"><img src="include/04-shared-memory-multiprocessors/caches-2.svg" width=400 /></div>

Main memory is far too slow to keep up with modern processor speed it can take up to hundreds of cycles to access, versus the CPU registers that are accessed instantaneously/
So another type of on-chip memory is introduced, the cache.
It is much faster than main memory, being accessed in a few cycles.
It is also expensive, so its size is relatively small, and thus the cache is used to maintain a subset of the program data and instructions.

The cache can have multiple levels: generally in multiprocessors we have a level 1 and sometimes level 2 caches that are local to each core, and a shared last level cache.

If an entire program data-set can fit in the cache, the CPU can run at full speed.
However, it is rarely the case on modern applications and new data/instructions needed by the program have to be fetched from memory (on each cache miss).
Also, newly written data in cache must eventually be written back to main memory.

## The Cache Coherency Problem

With just one CPU things are simple, data just written to the cache can be read correctly whether or not it has been written to memory.
But things get more complicated when we have multiple processors.
Indeed, several CPUs may share data, i.e. one can write a value that the other needs to read.
How does that work with the cache?

Consider the following situation, illustrated on the schema below.
We have a dual-core with CPU A and B, and some data `x` in RAM.
CPU A first reads it, then updates it in its own cache into `x'`.
Then later we have CPU B that wishes to read the same data.
It's not in its cache, so it fetches it from memory, and ends up reading the old value `x`.

<div style="text-align:center"><img src="include/04-shared-memory-multiprocessors/multiprocessor-caches-2.svg" width=500 /></div>

Clearly that is not OK: A and B expect to share memory and to see a common address space.
Threads use shared memory for communications and after some data, e.g. a global variable, is updated by a thread running on a core, another thread running on another core expects to read the updated version of this data: cores equipped with caches must still have a *coherent* view on memory, this is the **cache coherency problem**.

## The Cache Coherency Problem

An apparently obvious solution would be to ensure that every write in the cache is directly propagated to memory.
It is called a write-through cache policy:

<div style="text-align:center"><img src="include/04-shared-memory-multiprocessors/multiprocessor-caches-3.svg" width=400 /></div>


However, this would mean that every time we write we need to write to memory.
And every time we read we also need to fetch from memory in case the data was updated.
This is very slow and negates the cache benefits, thus it's not a good idea.

## The Cache Coherency Problem

So how can we overcome these issues?
Can we communicate cache-to-cache rather than always go through memory?
In other words, when a new value is written in one cache, all other values somehow located in other caches somehow would need to be either updated or invalidated.
Another issue is: what if two processors try to write to the same location.
In other words how to avoid having two separate cache copies?
This is what we refer to by cache coherency.
So things are getting complex, and we need to develop a model.
How to efficiently achieve cache coherency in a shared memory multiprocessor is the topic of the next lecture.
