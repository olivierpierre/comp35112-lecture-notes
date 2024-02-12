# Shared Memory Programming
---

You can access the slides for this lecture [here](https://olivierpierre.github.io/comp35112/lectures/03-shared-memory-programming). All the code samples given here can be found online, alongside instructions on how to bring up the proper environment to build and execute them [here](https://github.com/olivierpierre/comp35112-devcontainer).


## Processes and Address Spaces

The process is the basic unit of execution for a program on top of an operating system: each program runs within its own process.
A process executing on the CPU accesses memory with load and store instructions, indexing the memory with addresses.
In the vast majority of modern processors virtual memory is enabled very early at boot time, and from that point every load/store instruction executed by the CPU targets a **virtual address**.

With virtual memory, the OS gives to each process the illusion that it can access all the memory.
The set of addresses the CPU can index with load/store instructions when running a given process is called the **virtual address space** (abbreviated as *address space* from now on).
It ranges from address `0` all the way to what the width of the address bus lets the CPU address, generally 48 bits (256 TB).
This (very large) size for the virtual address space of each process is unrelated to the amount of RAM in the computer: in practice the address space is very sparse and most of it is not actually mapped to physical memory.

On this example we have two address spaces (i.e. 2 processes), and both see something different in memory at address `0x42`:

<div style="text-align:center"><img src="include/03-shared-memory-programming/processes-2.svg" width=750 /></div>

This is because through virtual memory, the address `0x42` is mapped to different locations in physical memory.
This mapping is achieved through the page table.
Each page table defines a unique virtual address space, and as such there is one page table per process.
This also allows to make sure processes cannot address anything outside their address space.

To leverage parallelism, two processes, i.e. two programs, can run on two different cores of a  multicore processor.
However, how can we use parallelism within the same program?

## Threads

A thread is a flow of control executing a program
It is a sequence of instructions executed on a CPU core
A process can consist of one or multiple threads
In other words, we can have for a single program several execution flows running on different cores and sharing a single address space.

In the example below we have two processes: A and B, each with its own address space:

<div style="text-align:center"><img src="include/03-shared-memory-programming/threads-4.svg" width=750 /></div>

In our example process A runs 3 threads, and they all see the green data.
Process B has 4 threads, and they see the same orange data.
A cannot access the orange data, and B cannot access the green data, because they run in disjoint address spaces.
However, all threads in A can access the green data, and all threads in B can access the orange data.
For example, if two threads in B read the memory at the address pointed by the red arrows, they will see the same value: `x`: **threads communicate using shared memory**, by accessing a common address space.
Seeing the same address space is very convenient for communications, that can be achieved through global variables or pointers to anywhere in the address space.

One can program with threads in various languages:
- C/C++/Fortran – using the POSIX threads (Pthread) library
- Java
- Many other languages: Python, C#, Haskell, Rust, etc.

## Threads in C/C++ with Pthread

Pthread is the **POSIX thread library** available for C/C++ programs.
We use the [`pthread_create`](https://linux.die.net/man/3/pthread_create) function to create and launch a thread.
It takes as parameter the function to run and optionally its arguments.

In the illustration below we have time flowing downwards.
The main thread of a process (that is automatically created by the OS when the program is started) calls `pthread_create` to create a child thread.
Children threads can use [`pthread_exit`](https://linux.die.net/man/3/pthread_exit) to stop their execution, and parent threads can call [`pthread_join`](https://linux.die.net/man/3/pthread_join) to wait for another thread to finish:

<div style="text-align:center"><img src="include/03-shared-memory-programming/pthread-3.svg" width=400 /></div>

A good chunk of this course unit, including lab exercises 1 and 2, will focus on shared memory programming in C/C++ with pthreads.
Use the Linux manual pages for the different pthread functions we'll cover (`man pthread_*`) and Google “pthreads” for lots of documentation.
In particular see the [Oracle Multithreaded Programming Guide](https://docs.oracle.com/cd/E53394_01/pdf/E54803.pdf).

Here is an example of a simple pthread program:

```c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>

#define NOWORKERS 5

// Function executed by all threads
void *thread_fn(void *arg) {
    int id = (int)(long)arg;

    printf("Thread %d running\n", id);

    pthread_exit(NULL);  // exit

    // never reached
}

int main(void) {
  // Each thread is controlled through a pthread_t data structure
  pthread_t workers[NOWORKERS];

  // Create and launch the threads
  for(int i=0; i<NOWORKERS; i++)
    if(pthread_create(&workers[i], NULL, thread_fn, (void *)(long)i)) {
      perror("pthread_create");
      return -1;
    }

  // Wait for threads to finish
  for (int i = 0; i < NOWORKERS; i++)
    if(pthread_join(workers[i], NULL)) {
      perror("pthread_join");
      return -1;
  }

  printf("All done\n");
}
```
This program creates 5 children threads which all print a message on the standard output then exit.
The main thread waits for the 5 children to finish, and exit.
This is all done using the functions we just covered.

<div style="text-align:center"><img src="include/03-shared-memory-programming/pthread-example.svg" width=300 /></div>

Notice how an integer is passed as parameter to each thread's function: it is cast as a `void *` because this is what `pthread_create` expects (in case we want to pass something larger we would put a pointer to a larger data structure here).
That value is passed as the parameter `arg` to the thread's function.
In our example we cast it back to an `int`.
We use the threads' parameters to uniquely identify each thread with an id.

Assuming the source code is present in a source file named `pthread.c`, you can compile and run it as follows:

```shell
gcc pthread.c -o pthread -lpthread
./pthread
```
## Threads in Java
There are two ways of defining a thread in Java:
- Creating a class that inherits from [`java.lang.Thread`](https://docs.oracle.com/javase/8/docs/api/java/lang/Thread.html).
- Creating a class that implements [`java.lang.Runnable`](https://docs.oracle.com/javase/8/docs/api/java/lang/Runnable.html).

The reason to be for the second approach is that it lets you inherit from something else than `Thread`, as multiple inheritance is not supported in Java.

With both approaches, one need to implement the `run` method to define what the thread does when it starts running.
From the parent, `Thread.start` start the execution of the thread, and `Thread.join` waits for a child to complete its execution.

Below is an example of a Java program with the exact same behaviour as our pthread C example, using the first approach (inheriting from `java.lang.Thread`):

```java
class MyThread extends Thread {
    int id;
    MyThread(int id) { this.id = id; }
    public void run() { System.out.println("Thread " + id + " running"); }
}

class Demo {
    public static void main(String[] args) {
        int NOWORKERS = 5;
        MyThread[] threads = new MyThread[NOWORKERS];

        for (int i = 0; i < NOWORKERS; i++)
            threads[i] = new MyThread(i);
        for (int i = 0; i < NOWORKERS; i++)
            threads[i].start();

        for (int i = 0; i < NOWORKERS; i++)
            try {
                threads[i].join();
            } catch (InterruptedException e) { /* do nothing */ }
        System.out.println("All done");
    }
}

```

This example defines the `MyThread` class inheriting from `Thread`.
In the constructor `MyThread` we just initialise an identifier integer member variable `id`.
We implement the `run` method, it just prints the fact that the thread is running as well as its id.
In the main function we create an array of `MyThread` objects, one per thread we want to create.
Each is given a different id.
Then we launch them all in a loop with `start`, and we wait for each to finish with `join`.

We can compile and run it as follows:

```shell
javac java-thread.java
java Demo
```

The second approach to threads in Java, i.e. implementing the `Runnable` interface, is illustrated in the program below:

```java
class MyRunnable implements Runnable {
    int id;
    MyRunnable(int id) { this.id = id; }
    public void run() { System.out.println("Thread " + id + " running"); }
}

class Demo {
    public static void main(String[] args) {
        int NOWORKERS = 5;
        Thread[] threads = new Thread[NOWORKERS];
        for (int i = 0; i < NOWORKERS; i++) {
            MyRunnable r = new MyRunnable(i);
            threads[i] = new Thread(r);
        }
        for (int i = 0; i < NOWORKERS; i++)
            threads[i].start();

        for (int i = 0; i < NOWORKERS; i++)
            try {
                threads[i].join();
            } catch (InterruptedException e) { /* do nothing */ }
        System.out.println("All done");
    }
}
```
Here we create a class `MyRunnable` implementing the interface in question.
For each thread we create a `Thread` object and we pass to the constructor a `MyRunnable` object instance.
Then we can call `start` and `join` on the thread objects.

## Output of Our Example Programs

For both Java and C examples, an example output is:

```shell
Thread 1 running
Thread 0 running
Thread 2 running
Thread 4 running
Thread 3 running
All done
```

One can notice that over multiple execution, the same program will yield a different order.
This illustrates the fact that without any form of synchronisation, the programmer has **no control over the order of execution.**: the OS scheduler decides, and it is nondeterministic.
A possible scheduling scenario is:
<div style="text-align:center"><img src="include/03-shared-memory-programming/scheduling.svg" width=300 /></div>

Another possible scenario assuming a single core processor:
<div style="text-align:center"><img src="include/03-shared-memory-programming/scheduling2.svg" width=400 /></div>

Of course this lack of control over the order of execution can be problematic in some situations where we really need a particular sequencing of certain thread operations, for example when a thread needs to accomplish a certain task before another thread can start doing its job.
Later in the course unit we will see how to use synchronisation mechanisms to manage this.

## Data Parallelism

#### Dividing Work between Threads

# Data Parallelism

As we saw previously, data parallelism is a relatively simple form of parallelism found in many applications such as computational science.
There is data parallelism when we have some data structured in such a way that the operations to be performed on it can easily be parralelised.
This is very suitable for parallelism, the goal is to divide the computations into chunks, computed in parallel.

Take for example the operation of summing two arrays, i.e. we sum each element of same index in A and B and put the result in C:

<div style="text-align:center"><img src="include/03-shared-memory-programming/vector.svg" width=750 /></div>

We can have a different thread realise each addition, or fewer threads each taking care of a subset of the additions.
This type of parallelism is exploited in vector and array processors.
General purpose CPU architectures have vector instructions extensions allowing things like applying the same operation on all elements of an array.
For example Intel x86-64 use to have SSE and now AVX.
From a very high level perspective, GPUs also work in that way.

Let's see a second example more in details, matrix-matrix multiplication.
We'll use square matrices for the sake of simplicity.
Recall that with matrix multiplication, each element of the result matrix is computed as the sum of the multiplication of the elements in one column of the first matrix with the element in one line of the second matrix:

<div style="text-align:center"><img src="include/03-shared-memory-programming/mat-mult.svg" width=450 /></div>

How can we parallelise this operation?
We can have 1 thread per element of the result matrix, each thread computing the value of the element in question
With a *n* x *n* matrix that gives us *n*<sup>2</sup> threads:

<div style="text-align:center"><img src="include/03-shared-memory-programming/mat-mult-1.svg" width=450 /></div>

If we don't have a lot of cores we may want to create fewer threads, it is generally not very efficient to have more threads than cores
So another strategy is to have a thread per row or per column of the result matrix:

<div style="text-align:center"><img src="include/03-shared-memory-programming/mat-mult-2.svg" width=450 /></div>

- Finally, we can also create an arbitrary number of threads by dividing the number of elements of the result matrix by the number of threads that we want and have each thread take care of a subset of the elements:

<div style="text-align:center"><img src="include/03-shared-memory-programming/mat-mult-3.svg" width=450 /></div>

Given all these strategies, there are two important questions with respect to the amount of effort/expertise required from the programmer:
- **What is the best strategy to choose according to the situation?**
Does the programmer need to be an expert to perform this choice?
- **How does the programmer indicate in the code the strategy to use?**
Is there a lot of code to add to a non-parallel version of the code? 
If we want to change strategy, do we have to rewrite most of the program?

The programmer's effort should in general be minimised if we want a particular parallel framework, programming language or style of programming to become popular/widespread.
But of course it also depends on the performance gained from parallelisation
Maybe it's okay to rewrite entirely an application with a given paradigm/language/framework if it results in a 10x speedup.

## Implicit vs. Explicit Parallelism

Here is an example of C/C++ parallelisation framework called [OpenMP](https://www.openmp.org/):

```c
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>

#define N 1000

int A[N][N];
int B[N][N];
int C[N][N];

int main(int argc, char **argv) {

  for(int i=0; i<N; i++)
    for(int j=0; j<N; j++) {
      A[i][j] = rand()%100;
      B[i][j] = rand()%100;
    }

#pragma omp parallel
  {
    for(int i=0; i<N; i++)  // this loop is parallelized automatically
      for(int j=0; j<N; j++) {
        C[i][j] = 0;
        for(int k=0; k<N; k++)
          C[i][j] = C[i][j] + A[i][k] * B[k][j];
        }
  }

  printf("matrix multiplication done\n");
  return 0;
}
```

We can parallelise the matrix multiplication operation in a very simple way by adding a simple annotation in the code: `#pragma omp parallel`.
All the iterations of the first outer loop will then be done in parallel by different threads.
The programmer's effort is minimal: the framework is taking care of managing the threads, and also to spawn the ideal number of threads according to the machine executing the program.
We will cover OpenMP in more details later in this course unit.

To compile and run this program, assuming the source code is in a file named `openmp.c`:

```shell
gcc openmp.c -fopenmp -o openmp
./openmp
```

This notion of programmer's effort is linked to the concepts of explicit and implicit parallelism.
With **explicit parallelism**, the programmer has to write/modify the application's code to indicate what should be done in parallel and what should be done sequentially.
This ranges from writing all the threads' code manually, or just putting some annotations in sequential programs (e.g. our example with OpenMP).
On the other hand, we have **implicit parallelism**, which requires absolutely no effort from the programmer: the system works out parallelism by itself.
This is achieved for example by some languages able to make strong assumption about data sharing, for example pure functions in functional languages have no side effects so they can run in parallel.

## Example Code for Implicit Parallelism

Here are a few examples of implicit parallelism.
Languages like Fortran allow expression on arrays, and some of these operations will be automatically parralelised, for example summing all elements of two arrays:

```fortran
A = B + C
```

If we have pure functions (functions that do not update anything but local variables), e.g. with a functional programming language, these functions can be executed in parallel.
In these examples the compiler can run `f` and `g` in parallel:

```fortran
y = f(x) + g(z)
```

Another example:

```fortran
p = h(f(x),g(z))
```

## Automatic Parallelisation

In an ideal world, the compiler would **take an ordinary sequential program and derive the parallelism automatically**.
Implicit parallelism is the best type of parallelism from the engineering effort point of view, because the programmer does not have to do anything.
If we have a sequential program it would be great if the compiler can automatically extract all the parallelism.
There was a lot of effort invested in such technologies at the time of the first parallel machines, before the multicore era.
It works well on small programs but in the general case, analysing dependencies in order to define what can be done in parallel and what needs to be done sequentially becomes very hard.
And of course the compiler needs to be conservative not to break the program, i.e. if it is not 100% sure that two steps can be run in parallel they need to run sequentially.
So overall performance gains through implicit parallelism are quite limited, and to get major gains one need to go the explicit way.

## Example Problems for Parallelisation

Below are a few examples of dependencies that a compiler may face when trying to extract parallelism automatically.
They all regard parallelising all of some iterations of a loop.

**Case 1.**
Here, in the first loop, 3 slots after the index computed at each iteration, we have a read dependency:
```c
for (int i = 0 ; i < n-3 ; i++) {
  a[i] = a[i+3] + b[i] ;      // at iteration i, read dependency with index i+3
}
```

**Case 2.**
Here we have another read dependency, this time 5 slots before the index computed at each iteration:

```c
for (int i = 5 ; i < n ; i++) {
  a[i] += a[i-5] * 2 ;         // at iteration i, read dependency with index i-5
}
```

**Case 3.**
Here, still a read dependency, and we don't know if the slot read is before or after the one being computed:

```c
for (int i = 0 ; i < n ; i++) {
  a[i] = a[i + j] + 1 ;       // at iteration i, read dependency with index ???
}
```

# Automatic Parallelisation

Let's consider *case 1* above.
We can illustrate the data dependency over a few iterations of the loop as follows:

<div style="text-align:center"><img src="include/03-shared-memory-programming/dep-table.svg" width=300 /></div>


If we parallelise naively and run each iteration in parallel, there is a chance for e.g. iteration 3 to finish before iteration 0, which would break the program.
We can observe that the dependency has a positive offset: we read at each iteration what was in the array before the loop started.
We are never supposed to read a value computed by the loop itself.
So the solution to parallelise this loop is to internally make a new version of the array and read from an unmodified copy:

```c
parrallel_for(int i=0; i<n-3; i++)
        new_a[i] = a[i+3] + b[i];
a = new_a;
```

If we consider *case 2* above, the trick we just presented does not work.
Let's illustrate the dependency:

<div style="text-align:center"><img src="include/03-shared-memory-programming/dep-table2.svg" width=300 /></div>

Because what we read at iteration `i` is supposed to have been written 5 iteration before, we can't rely on a read-only copy
Also, parallelising all iterations will break the program.
We observe that at a given time, there is no dependency between sets of 5 iterations, (e.g. iterations 5-9 or iterations 10-14).
The solution here is thus to limit the parallelism to 5.

Concerning *case 3* above, because of the way the code is structured, it is not possible to automatically parallelise the loop.

## Shared Memory

Everything in this lecture has been said on the basis that threads share memory
In other words they can all access the same memory, and they will all see the same data at a given address
Without shared memory, for example when the concurrent execution flows composing a parallel application run on separate machines, these execution flows have to communicate via messages, more like a distributed system.
