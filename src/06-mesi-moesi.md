# MESI and MOESI Cache Coherence
---

You can access the slides for this lecture [here](https://olivierpierre.github.io/comp35112/lectures/06-mesi-moesi).

Here we will present a few optimisations implemented on top of MSI.
These optimisations give us two new protocols, MESI and MOESI.

## Unnecessary Communication

In a snoopy bus-based cache coherence system, the bus itself is a critical resource, as it is shared by all cores.
Only one component can use the bus at a time, so unnecessary use of the bus is a waste of time and impacts performance.
In some scenarios, MSI can send a lot of unnecessary requests on the bus.
Take for example the following case:

<div style="text-align:center"><img src="include/06-mesi-moesi/unnecessary-comm-1.svg" width=700 /></div>

One core, core 2, has the data in the *shared* state.
And all other cores have the data in the *invalid* state.
If there is a write to core 2 we transition from *invalid*-*invalid*-*invalid*-*shared* to *invalid*-*invalid*-*invalid*-*modified*.
MSI would still broadcast an invalidate request on the bus to all cores even if it's unnecessary.

However, in another scenario, for example when all cores have the data in the shared state, and there is a write on any of these cores, the broadcast is actually needed:

<div style="text-align:center"><img src="include/06-mesi-moesi/unnecessary-comm-2.svg" width=700 /></div>

The central problem is that with MSI the core that writes does not know the status of the data on the other cores so it blindly broadcast invalidate messages.
How can we differentiate these cases?

## Optimising for Non-Shared Values

We need to distinguish between the two shared cases:
- In the first case a cache holds the only copy of a value which is in sync with memory (in other words it is not modified).
- In the second case a cache holds a copy of the value which is in sync with memory and there are also other copies in other caches.

In the first case we do not need to send an invalidate message on write, whereas in the second an invalidate message is needed:

<div style="text-align:center"><img src="include/06-mesi-moesi/unnecessary-comm-3.svg" width=700 /></div>

## MESI Protocol

The unshared case (first case described above) is very common: in real application, the majority of variables are unshared (e.g. all of a thread's local variables).

The key idea with MESI is to split the *shared* state into two states that corresponds to the two cases we have presented:
  - **Exclusive**, in which a cache has the only copy of the cache line (and its content is in sync with memory)
  - Truly **shared**, in which the cache holds one of several shared copies of the cache line (and once again its content is in sync with memory)

The relevant transitions are as follows.
We switch to *exclusive* (E) after a read caused a fetch from memory.
We switch to *truly shared* (S) after a read that gets value from another cache.
These transitions are illustrated below:

<div style="text-align:center"><img src="include/06-mesi-moesi/mesi.svg" width=600 /></div>



MESI is a simple extension, but it yields a **significant reduction in bus usage**.
Therefore, in practice MESI is more widely used than MSI.
We won't cover MESI in details here, however a notable point is that a cache line eviction on a remote core can cause a line in the local core being in state *truly shared* to be the only remaining copy.
In that case we should theoretically switch to *exclusive* but in practice it is hard to detect, so we stay in *truly shared*.

## MOESI Protocol

MOESI is a further optimisation in which we split the *modified* state in two:
- **Modified** is the same as before, the cache contains a copy which differs from that in memory but there are no other copies.
- **Owned**: the cache contains a copy which differs from that in memory and there may be copies in other caches which are in state S, these copies having the same value as that of the owner.

This is illustrated below:

<div style="text-align:center"><img src="include/06-mesi-moesi/moesi.svg" width=600 /></div>

# MOESI Protocol

The owner is the only cache that can make changes without sending an invalidate message.
MOESI allows the latest version of the cache line to be shared between caches without having to write it back to memory immediately.
When it writes, the owner broadcasts the changes to the other copies, without a writeback:

<div style="text-align:center"><img src="include/06-mesi-moesi/moesi-2.svg" width=300 /></div>

Only when a cache line in state *owned* or *modified* gets evicted will any write back to memory be done.


