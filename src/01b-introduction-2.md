# Introduction Part 2
---

You can access the slides for this lecture [here](https://olivierpierre.github.io/comp35112/lectures/01b-introduction-2).

We have seen that due to several factors, in particular the clock frequency hitting a plateau in the mid 2000s, single core CPU performance could not increase anymore.
As a result CPU manufacturers started to integrate multiple cores on a single  chip, creating chip multiprocessors or multicores.
Here we will discuss how to exploit the parallelism offered by these CPUs, and also give an overview of the course unit.

## How to Use Multiple Cores?


How to leverage multiple cores?
Of course one can run 2 separate programs, each running in a different **process**, on two different cores in parallel.
This is fine, and these two programs can be old software originally written for single core processor, they don't need to be ported.
But the real difficulty is when we want increased performance for a single application.
So we need a collection of execution flows, such as **threads**, all working together to solve a given problem.
Both cases are illustrated below:

<div style="text-align:center"><img src="include/01b-introduction-2/multicore.svg" width=400 /></div>

## Instruction- vs. Thread-Level Parallelism

**Instruction-Level Parallelism.**
One way to exploit parallelism is through the use of instruction level parallelism (ILP).
How does it work?
Imagine we have a sequential program composed of a series of instructions to be executed one after the other.
The compiler will take this program and is able to determine what instructions can be executed in parallel on multiple cores.
Sometimes instructions can be even executed out of order, as long as there is no dependencies between them.
This is illustrated below:

<div style="text-align:center"><img src="include/01b-introduction-2/ilp.svg" width=500 /></div>

ILP is very practical because we just have to recompile the program, there is no need to modify the program i.e. no effort from the application programmer.
However the amount of parallelism we can extract with such techniques is very limited, due to the dependencies between instructions.



**Thread-Level Parallelism (TLP).**
Another way to exploit parallelism is to mostly rewrite your application with parallelism in mind.
The programmer divides the program into (long) sequences of instructions that are executed concurrently, with some running in parallel on different cores:

<div style="text-align:center"><img src="include/01b-introduction-2/tlp.svg" width=600 /></div>

The program executing is still represented as a process, and the sequences of instructions running concurrently are named **threads**.
Now because of scheduling we do not have control over the order in which most of the threads' operations are realised, so for the computations to be meaningful the threads need to **synchronise** somehow.

Another important and related issue, is how to share data between threads.
Threads belonging to the same program execute within a single process and they share an address space, i.e. they will read the same data at a given virtual address in memory.
What happens if a thread reads a variable currently being written by another thread?
What happen if two threads try to write the same variable at the same time?
Obviously we don't want these things to happen and shared data access need to be properly **synchronised**: threads need to make sure they don't step on each other's feet when accessing shared data.

A set of threads can run concurrently on a single core.
Thy will time-share the core, i.e. their execution will be interlaced and the total execution time for the set of threads will be the sum of each thread execution time.
On a multicore processor, threads can run in parallel on different cores, and ideally the total execution time would be the time of the sequential version divided by the number of threads.

<div style="text-align:center"><img src="include/01b-introduction-2/tlp2.svg" width=750 /></div>

So contrary to ILP which is limited, TLP can really help to fully exploit the parallelism brought by multiple cores.
However that means rewriting the application to use threads so there is some effort required from the application programmer.
The application itself also needs to be suitable for being divided into several execution flows.

## Data Parallelism

The data manipulated by certain programs, as well as the way it is manipulated, is very well-fitted for parallelism.
For example it is the case with applications doing computations on single and multi-dimensional arrays.
Here we have a matrix-matrix addition, where each element of the result matrix can be computed in parallel.
This is called **data parallelism**.
Many applications exploiting data parallelism perform the same or a very similar operation on all elements of a data set (an array, a matrix, etc.).
In this example, where two matrices are summed, each thread (represented by a color) sums the two corresponding members of the operand matrices, and all of these sums can be done in parallel:
<div style="text-align:center"><img src="include/01b-introduction-2/data-parallelism.svg" width=500 /></div>

A few examples of application domains that lend themselves well to data parallelism are matrix/array operations (extensively used in AI applications), Fourier Transform, a lot of graphical computations like filters, anti-aliasing, texture mapping, light and shadow computations, etc.
Differential equations applications are also good candidates, and these are extensively used in domains such as weather forecasting, engineering simulations, and financial modelling.

## Complexity of Parallelism

Parallel programming is generally considered to be difficult, but depends a lot on the program structure:

<div style="text-align:center"><img src="include/01b-introduction-2/programming.svg" width=500 /></div>

In scenarios where all the parallel execution flows, let's say threads, are doing the same thing, and they don't share much data, then it can be quite straightforward.
On the other end, in situations where all the threads are doing something different, or when they share a lot of data in write mode, when they communicate a lot and need to synchronise, then such programs can be quite hard to reason about, to develop, and to debug.

## Chip Multiprocessor Considerations

Here are a few considerations with chip multiprocessors that we will cover in this course unit.
First **how should the hardware, the chip itself, be built**.
When we have multiple cores, how are they connected together?
How are they connected to memory?
Are they supposed to be used for particular programming patters such as data parallelism? or multithreading?
If we want to build a multicore, should we use a lot of simple cores or just a few complex cores?
Should the processor be general purpose, or specialised towards particular workloads?

We also have  problematics regarding **software, i.e. how to program these chip multiprocessors**.
Can we use a conventional programming language? 
Possibly an extended version of a popular language?
Should we rather use a specific language, or a totally new approach?

# Overview of Lectures

Beyond this introduction, we will cover in this course unit the following topics:
- Thread-based programming, thread synchronisation
- Cache coherency in homogeneous shared memory multiprocessors
- Memory consistency
- Hardware support for thread synchronisation
- Operating system support for threads, concurrency within the kernel
- Alternative programming views
- Speculation and transactional memory
- Heterogeneous processors/cores and programs
- Radical approaches (e.g. dataflow programming)
