# Cache Coherence in Multiprocessors
---

You can access the slides for this lecture [here](https://olivierpierre.github.io/comp35112/lectures/05-cache-coherence).

We have previously introduced the issue of **cache coherence** in multiprocessors.
The problem is that with a multiprocessor each core has a local cache, and data in that cache may not be in sync with memory.
We need to avoid situations where two cores have multiple copies of the same data with different values for that data.
If we try to naively use in a multicore a traditional cache system (as used in single core CPUs), the following can happen:

<div style="text-align:center"><img src="include/05-cache-coherence/issue.svg" width=500 /></div>


1. At first we have the data `x` in memory and core A reads it then updates it to `x'`.
For performance reasons A does not write the data in memory yet.
2. Later, B wants to read the data.
It's not in B's cache so it fetched it from memory: B reads `x` which is not the last version of the data.

This of course breaks the program.
So we need to define a protocol to make sure that all caches have a coherent view on memory.
This involves **cache to cache communication**: for performance reasons, we want to avoid involving memory as much as we can.

## Coping with Multiple Cores

Here we will cover a simple protocol named bus-based coherence or **bus snooping**.
All the cores are interconnected with a bus that is also linked to memory:

<div style="text-align:center"><img src="include/05-cache-coherence/bus.svg" width=600 /></div>

Each core has have some special cache management hardware.
This hardware can observe all the transactions on the bus and it is also able to modify the cache content independently of the core.
With this hardware, when a given cache observes pertinent transactions on the bus, it can take appropriate actions
Another way to look at this is that **a cache can send messages to other caches, and receive messages from other caches**.


## Cache States, MSI Protocol

On the hardware we described we'll present now a **cache coherence protocol**, i.e. a way for the caches to exchange messages in order to maintain a coherent view on the memory's content for all cores.

Recall that caches hold data (and read/write it from/to memory) at the granularity of a **cache line** (generally 64 byte).
Each cache has 2 control bits for each line it contains, encoding the state the line currently is in:

<div style="text-align:center"><img src="include/05-cache-coherence/lines.svg" width=400 /></div>

Each line can be can be in one of three different states:
- **Modified** state: the cache line is valid and has been written to but the latest
    values have not been updated in memory yet
  - A line can be in the modified state in at most 1 core
- **Invalid**: there may be an address match on this line but the data is
not valid
    - We must go to memory and fetch it or get it from another cache
- **Shared**: implicit 3rd state, not invalid and not modified
    - A valid cache entry exists and the line has the same values as main
    memory
    - Several caches can have the same line in that state

These states can be illustrated as follows:

<div style="text-align:center"><img src="include/05-cache-coherence/msi1.svg" width=150 /> <img src="include/05-cache-coherence/msi2.svg" width=150 /> <img src="include/05-cache-coherence/msi3.svg" width=180 /></div>


The Modified/Shared/Invalid states, as well as the transitions we'll describe next, define the **MSI protocol**.

## Possible States for a Dual-Core CPU

Let's describe the MSI protocol on a dual core processor for the sake of simplicity.
For a given cache line, we have the following possible states:

<div style="text-align:center"><img src="include/05-cache-coherence/states-full.svg" width=800 /></div>

The different combinations of states on the dual core are as follows:
- **(a) modified-invalid**: one cache has the line in the *modified* state, i.e. the data in there is valid and not in sync with memory, and the other cache has the line in the *invalid* state.
- **(b) invalid-invalid**: we have the line *invalid* in both caches.
- **(c) invalid-shared**: the line is *invalid* in one cache, and *shared* (i.e. valid and in sync with memory) in the other cache.
- **(d) shared-shared**: the line is valid and in sync with memory in both caches.

By symmetry we also have **(a') invalid-modified** as well as **(c') shared-invalid**.

Recall that by definition if a cache has the data in the *modified* state, that cache should be the only one with a valid copy of the line in question, hence the states **modified-shared** and **modified-modified**, which break that rule, are **not possible**.

## State Transitions

After we listed all the possible legal states, let's see now, for each state, how read and write operations on each of the two cores affect the state of the dual core.
This regards 3 aspects:
1. **What are the messages sent between cores**: we'll see messages requesting a cache line, messaging asking a remote core to invalidate a given line, and messages asking for both a line content as well as its invalidation from a remote cache.
2. **When memory needs to be involved**, e.g. to fetch a cache line or to write it back.
3. **What are the state transitions** between the state combinations listed above for our dual core.

## State Transitions from (a) Modified-Invalid

Let's start with the *modified*/*invalid* state. In that state core 1 has the line *modified*, it's valid but not in sync with memory, and core 2 has the line *invalid*, it's in the cache but the content is out of date.

**Read or Write on Core 1.**
If we have either a **read or a write on core 1**, these are just served by the cache (cache hits), no memory operation is involved, and there is no state transition.

**Read on Core 2.**
If there is a read on core 2, because the line is *invalid* in its cache it cannot be served from there.
So core 2 places a read request on the bus, which gets snooped by core 1.
We can have only one cache in the *modified* state, so with this particular protocol we are aiming at a *shared*-*shared* final state.
So core 1 writes back the data to memory to have it in sync, and goes to the *shared* state.
Core 1 also sends the line content to core 2 that switches to the *shared* state.
We end up in the (d) *shared*-*shared* state, i.e. both caches have the line valid and in sync with memory:

<div style="text-align:center"><img src="include/05-cache-coherence/transition-2.svg" width=500 /></div>

**Write on Core 2.**
In case of a write on core 2, its cache has the line *invalid*, so it places a read request on the bus, which is snooped by core 1.
Core 1 has the data in *modified* state so it first writes it back to memory, and then sends the line to core 2.
Core 2 updates the line so it sends an invalidate message on the bus, and core 1 switches to the *invalid* state.
Core 2 then switches to *modified*.
Overall the state changes to (a'): invalid/modified:

<div style="text-align:center"><img src="include/05-cache-coherence/transition-3.svg" width=500 /></div>

## State Transitions from (b) Invalid-Invalid

**Read on Core 1 or Core 2.**
In that state both caches have the line but its content is out of date.
If there is a read on one core, the cache in question places a read request on the bus.
Nobody answers and the cache then fetch the data from memory, switches the state to shared.
The system ends up in the (c') *shared*-*invalid* or (c) *invalid*-*shared* state, according to which core performed the read.
For example with core 1 performing the read:

<div style="text-align:center"><img src="include/05-cache-coherence/transition-4.svg" width=500 /></div>

**Write on core 1 or 2.**
If there is a write on a core, the relevant cache does not know about the status of the line in other cores so it places a read request on the bus.
Nobody answers so the line is fetched from memory and the write is performed in the cache so the writing core switch the state to *modified*.
We end up in (a) *modified*-*invalid* or (a') *invalid*-*modified* according to which core performed the write operation, e.g. if it was core 1:

<div style="text-align:center"><img src="include/05-cache-coherence/transition-5.svg" width=500 /></div>

## State Transitions from (c) Invalid-Shared

**Read on Core 1.**
The line is in the *invalid* state on that cache, so it is present but the content is out of date.
The other cache has the line in the *shared* state so it is present, valid, and in sync with memory.
In case of a read on core 1, its cache places a read request on the bus, it is snooped by cache 2 which replies with the cache line.
Core 1 switches to the *shared* state, and the system is now in the (d) *shared*-*shared* state:

<div style="text-align:center"><img src="include/05-cache-coherence/transition-6.svg" width=500 /></div>

**Read on Core 2.**
In case of a read on core 2, the  read is served from the cache, non memory operation is required, and there is no state transition: the system stays in (c) *invalid*-*shared*.

**Write on Core 1.**
Because core 1 has the line in the *invalid* state, it starts by placing a read request on the bus.
Core 2 snoops the request and replies with the data.
It's in the *shared* state so no need for a writeback in memory.
Core 1 wants to update the line, so it places an invalidate request on the bus.
Core 2 receives it and switches to invalid.
Finally core 1 performs the write and switches to modified.
We end up in the (a) *modified*-*invalid* state:

<div style="text-align:center"><img src="include/05-cache-coherence/transition-7.svg" width=500 /></div>

**Write on Core 2.**
In the case of a write on core 2, even if nobody needs to invalidate anything core 2 does not know it, so it places an invalidate message on the bus.
Afterwards it performs the write in the cache and switches to the *modified* state.
We end up in the (a') *invalid*-*modified* state:

<div style="text-align:center"><img src="include/05-cache-coherence/transition-8.svg" width=500 /></div>

## State Transitions from (d) Shared-Shared

**Read on Core 1 or Core 2.**
If there is a read on any of the cores, it is a cache hit, served from the cache.

**Write on Core 1 or Core 2.**
If there is a write on a core, the core in question places an invalidate request on the bus.
The other core snoops the request and switches to *invalid*, it was shared so there is no need for writeback.
The first core can then perform the write and switches to the *modified* state, we end up in the (a) *modified*-*invalid* or (a') *invalid*-*modified* state depending on which core made the update, e.g. if it was core 1:

<div style="text-align:center"><img src="include/05-cache-coherence/transition-9.svg" width=500 /></div>

## Beyond Two Cores

The MSI protocol generalises beyond 2 cores.
Because of the way the snoopy bus works, the read and invalidate messages are in effect broadcasted to all cores.
Any core with a valid value (*shared* or *modified*) can reply to a read request.
For example here, core 1 has the line in the *invalid* state and wishes to perform a read so it broadcasts a read request on the bus and one of the cores having the line in the *shared* state replies:

<div style="text-align:center"><img src="include/05-cache-coherence/transition-mcore-1.svg" width=300 /></div>


When an invalidate request is received, any core in the *shared* state invalidates without writeback, as it is the case for core 3 and core 4 in this example:

<div style="text-align:center"><img src="include/05-cache-coherence/transition-mcore-2.svg" width=300 /></div>

When an invalidate message is received, a core in the modified state writes back before invalidating, e.g. core 4 in this example:

<div style="text-align:center"><img src="include/05-cache-coherence/transition-mcore-3.svg" width=300 /></div>

## Write-Invalidate vs. Write-Update

There are two major types of snooping protocols:
- With **write-invalidate**, when a core updates a cache line, other copies of that line in other caches are **invalidated**.
Future accesses on the other copies will require fetching the updated line  from memory/other caches.
It is the most widespread protocol, used in MSI, but also in other protocols such as MESI and MOESI, that we will cover next.
- With **write-update**:, when a core updates a cache line, the modification is broadcast to copies of that line in other caches: they are **updated**.
This leads to a higher bus traffic compared to write-invalidate.
Example of write-update protocols include [Dragon](https://en.wikipedia.org/wiki/Dragon_protocol) and [Firefly](https://en.wikipedia.org/wiki/Firefly_(cache_coherence_protocol)).

## Cache Snooping Implications on Scalability

Given our description of the way cache snooping works, when an invalidate message is sent, it is important that all cores receive the message within a single bus cycle so that they all invalidate at the same time.
If this does not happen, one core may have the time to perform a write during that process, which would break consistency.

This becomes harder to achieve as we connect higher numbers of cores together into a chip multiprocessor, because the invalidate signal takes more time to propagate.
With more cores the bus capacitance is also higher and the bus cycle is longer.
This seriously impacts performance.
So overall, **a cache snooping-based coherence protocol is a major limitation to the number of cores that can be supported by a CPU**.

