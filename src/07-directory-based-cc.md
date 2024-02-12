# Directory-Based Cache Coherence
---

You can access the slides for this lecture [here](https://olivierpierre.github.io/comp35112/lectures/07-directory-based-cc/).

Here we will cover a cache coherence protocol that is quite different from the bus-based protocols we have seen until now.
It is named **directory-based coherence protocol**.

## Directory Based Coherence

We have seen that shared bus based coherence does not scale well to large amount of cores.
This is because only one entity can use the bus at a time.
Can we implement a cache coherence protocol with a less directly connected network, such as a grid, or a general packet switched network:

<div style="text-align:center"><img src="include/07-directory-based-cc/grid.svg" width=780 /></div>


One possible solution is to use a ***directory* holding information about data (i.e. cache lines) in the memory**
We are going to describe a simple version of this scheme.

## Directory Structure

The architecture of a directory-based cache coherence system is as follows:

<div style="text-align:center"><img src="include/07-directory-based-cc/directory.svg" width=400 /></div>

Each core has a local cache.
They are linked together through an interconnect network, as we mentioned something less directly connected than with bus-based coherence.
The memory is also connected to the network.
Attached to the network is also a component named the **directory**.
The directory contains **one entry for each possible cache line**, so its size depends on the amount of memory.
Each entry in the directory has ***n* present bits**, *n* being the number of cores.
If one of these bits is set, it means that the corresponding cache has a copy of the line in question.
For each entry there is also a **dirty bit in the directory**.
When it is set it means that only 1 cache has the corresponding line, and that cache is the only owner of that line.
In every cache each line also has a **local valid bit**, indicating the validity of the cache line, as well as a **local dirty bit**, indicating that the cache is the sole owner of the line or not.
A core wishing to make a memory access may need to query the directory about the state of the line to be accessed.

## Directory Protocol

Similarly to what we did for MSI, let's have a look at what happens upon core read/write operations in various scenarios, considering a dual-core CPU.

**Read Hit in Local Cache.**
In that case a core wants to read some data, and it's present in the cache, indicated with the valid bit.
There is no need to contact the directory and the core just reads from the cache:

<div style="text-align:center"><img src="include/07-directory-based-cc/directory-1.svg" width=360 /></div>

**Read miss in Local Cache.**
In case of a read miss (i.e. data is not present in the cache or the corresponding local valid bit is unset), the directory is consulted and the actions taken depend what happens in this scenario depends on the value of the directory dirty bit for that value.

1. If the ***directory dirty bit is unset***, first we consult the directory to see if another cache has the line in question: if that is the case, the line can be retrieved from that other cache.
If no other cache has the line, it can be safely fetched from memory.
The directory bit corresponding to the reading core is then set to 1, as well as the local valid bit in the cache of the reading core.

The two scenarios for a read miss in local cache with directory bit unset are illustrated below:

<div style="text-align:center"><img src="include/07-directory-based-cc/directory-2.svg" width=450 /></div>

2. If the ***directory dirty bit is set***, we know that another cache has the last version of the cache line, and that it is the one and only owner of the line.
So we force that core to sync with memory, and have it also send the line to the reading core.
We can clear the directory dirty bit, as is no exclusive owner for that cache line anymore.
The local valid bit is also set in the reading core, as well as the present bit in the directory for that core.
This is illustrated below:

<div style="text-align:center"><img src="include/07-directory-based-cc/directory-3.svg" width=360 /></div>

**Write hit in Local Cache with Local Dirty Bit Set.**
In that case, we know the line in cache is valid, and that the reading core is the sole owner of that line: the write can be performed directly in the cache:

<div style="text-align:center"><img src="include/07-directory-based-cc/directory-6.svg" width=360 /></div>

**Write Hit in Local Cache with Local Dirty Bit Unset.**
In that case the writing core is not the sole owner of the cache line, so it consults the directory to know which caches have the line and sends invalidate messages to them.
The corresponding bits in the directory can then be cleared.
As the writing core is now the sole owner of the line, the local dirty bit is set and the directory dirty bit is set too.

**Write Miss in Local Cache.**
Here again the actions to take depends on the value of the directory dirty bit for the cache line written.

1. If the ***directory dirty bit is unset***, the directory present bits are consulted to see if any cache has the line.
If that is the case, the cache line is retrieved from the corresponding remote cache, and the writing core also sends an invalidate message to any remote cache having the line.
If no remote cache has the line, it is fetched from memory.
The present bit is set in the directory for the writing core, and the directory dirty bit is also set.
Finally, the local dirty bit is set in the writing core.

This is illustrated below:

<div style="text-align:center"><img src="include/07-directory-based-cc/directory-4.svg" width=360 /></div>

2. If the ***directory dirty bit is set***, it means that another core has the exclusive last version of the data.
The writing core sends a message to the remote core, which updates memory and sends the cache line to the writing core.
The writing core performs the write operation and sets its local dirty bit.
In the directory, the dirty bit stays set because we still have an exclusive owner.
However, the owner is now the writing core, so we set the presence bits accordingly.

This is illustrated below:

<div style="text-align:center"><img src="include/07-directory-based-cc/directory-5.svg" width=360 /></div>

## Analysis, NUMA Systems

We described a directory-based protocol that is roughly equivalent to the bus-based MSI protocol.
There are multiple optimisations possible, but we won't go into details.
The important thing to note is that, even if directory-based coherency is designed to scale to more cores than snooping, having a single directory centralising coherency metadata is a serious bottleneck.
So the solution is to distribute this metadata, and have multiple directories, each taking care of a subset of the memory address space.
This is often coupled with a distributed memory structures where part of the memory is physically local to the processor, and part is remote.
This is particular to medium and large multiprocessor systems that have multiple CPU chips.
The latency to access local and remote memory is different in these systems, and we talk about **Non-Uniform memory Access, NUMA** systems.

Here is an example of such system:

<div style="text-align:center"><img src="include/07-directory-based-cc/directory-numa.svg" width=800 /></div>

In this example we have 2 sockets, which means 2 processor chips, interconnected, so they can operate on a single shared address space.
Part of the physical memory is local to socket 1 and part is local to socket 2.
We also have 2 directories.
Access non-local memory takes more time.

## Drawbacks

Directory-based coherency is not a panacea and there are a few drawbacks.
Without a common bus network many of the previous **communications will take a significant number of CPU cycles**.
In the presence of long and possibly delays such protocols usually require **replies to messages**, handshakes, to work correctly, and many doubt that it can be made to work efficiently for heavily shared memory applications.
Some machines that used directory-based coherency include [SGI Origin](https://en.wikipedia.org/wiki/SGI_Origin_2000), as well as the [Intel Xeon Phi](https://en.wikipedia.org/wiki/Xeon_Phi).
