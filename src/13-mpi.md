# Message Passing Interface
---

You can access the slides for this lecture [here](https://olivierpierre.github.io/comp35112/lectures/13-mpi/).
All the code samples given here can be found online, alongside instructions on how to bring up the proper environment to build and execute them [here](https://github.com/olivierpierre/comp35112-devcontainer).


Here we will talk briefly about MPI.
It's a standard defining a set of operation allowing to write distributed application that can be massively parrallel.

## MPI

MPI is a standard that describes a set of basic functions that can be used to create parallel applications, possibly spanning multiple computers.
These functions are available in libraries for C/C++ and Fortran.
Such applications are portable between various parallel systems that support the standard.
MPI is used to program many types of systems, not only shared memory machines as we have seen until now, but also custom massively parallel machines also called manycores or supercomputers.
MPI can be used to run a single application over an entire set of machine, a cluster of computers.
An important thing to note is that MPI relies on message passing and not shared memory for communications.
This allows an MPI application to exploit parallelism beyond the boundary of a single machine.
For these reasons MPI is the most widely used API for parallel programming.
Still programming in MPI has a cost: the application must be designed from scratch with message passing in mind, so porting existing applications is costly.

## Messages, Processes, Communicators

<div style="text-align:center"><img src="include/13-mpi/mpi.svg" width=350 /></div>

In MPI each parallel unit of execution is running as a **process**.
Each process is identified by its **rank**, which is an integer.
Processes exchange **messages**, characterised by the rank of the sending and receiving processes, as well as an integer tag that allows to define message types.

Processes are grouped, they are initially within a single group which can be split later.
Messages can be sent over what is called a **communicator** linked to a process group in order to restrict the communication to a subset of the processes.

## MPI Hello World

Here is a minimal MPI application in C:

```c
#include <mpi.h>
#include <stdio.h>

int main(int argc, char** argv) {
    // Initialize the MPI environment
    MPI_Init(NULL, NULL);

    // Get the number of processes and the rank of the process
    int world_size, world_rank;
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);
    MPI_Comm_rank(MPI_COMM_WORLD, &world_rank);

    // Get the name of the processor (machine)
    char processor_name[MPI_MAX_PROCESSOR_NAME];
    int name_len;
    MPI_Get_processor_name(processor_name, &name_len);

    // Print off a hello world message
    printf("Hello world from processor %s, rank %d out of %d processes\n",
           processor_name, world_rank, world_size);

    // Finalize the MPI environment.
    MPI_Finalize();
}
```

This code will be executed by each process of our application.
We start by initialising the MPI library with `MPI_Init`.
Then we get the total number of processes running for this application with `MPI_Comm_size`.
We get the identifier of the current process, i.e. its rank, with `MPI_Comm_rank`.
Then we get the name of the processor (the machine executing the process) into a character array, and finally we print all this information before exiting.

To build and run this example you need the MPI Library.
To install the MPICH implementation on Ubuntu/Debian use the following command:

```bash
sudo apt install mpich
```

To compile the aforementioned example, use the provided gcc wrapper:
```bash
mpicc mpi-hello.c -o mpi-hello
```

To run the program use `mpirun`.
The number of processes created by default depends on the version of the library.
Some versions create a single process, others create a number of process equals to the number of cores of the machine:

```bash
mpirun mpi-hello
mpirun -n 8 mpi-hello # Manually specify the number of processes to run
```
## Blocking `send` and `recv`

To send and receive messages we have the `MPI_Send` and `MPI_Recv` functions.
They take the following parameters:
- `data` is a pointer to a buffer containing the data to send/receive.
As you can see its type is `void *` so it can point to anything.
In other words the messages sent and received can embed any type of data structure.
- `cnt` is the number of items to send or receive, in the case an array is transmitted.
- `t` is the type of the data exchanged.
For this the MPI library offers macros for integers, floating point numbers, and so on.
- `dst` is the rank of the receiving process for send.
- `src` is the rank of the sending process for receive.
Note that there are some macros to specify sending and receiving from *any* process.
- `com` is the communicator describing the subset of processes that can participate in this communication.
- `st` will be set with status information that can be checked after receive completes.

```c
MPI_Send(void* data, int cnt, MPI_Datatype t, int dst, int tag, MPI_Comm com);
MPI_Recv(void* data, int cnt, MPI_Datatype t, int src, int tag, MPI_Comm com, MPI_Status* st);
```

Let's study a simple example of MPI program using the send and receive primitives.
Our example is an application that creates N processes.
At the beginning the first process of rank 0 creates a counter and initialises it to 0.
Then it sends this value to another random process, let's say 2.
2 receives the value, increments it by one, and sends the result to another random process.
And rinse and repeat.
This process is illustrated below:

<div style="text-align:center"><img src="include/13-mpi/bounce.svg" width=550 /></div>

The code for the application is below:

```c
#include <stdio.h>
#include <stdlib.h>
#include <mpi.h>

#define BOUNCE_LIMIT    20

int main(int argc, char** argv) {
    MPI_Init(NULL, NULL);
    int my_rank, world_size;
    MPI_Comm_rank(MPI_COMM_WORLD, &my_rank);
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);

    if (world_size < 2) {
        fprintf(stderr, "World need to be >= 2 processes\n");
        MPI_Abort(MPI_COMM_WORLD, 1);
    }

    /* The first process is in charge of sending the first message */
    if(my_rank == 0) {
        int payload = 0;
        int target_rank = 0;

        /* We don't want the process to send a message to itself */
        while(target_rank == my_rank)
            target_rank = rand()%world_size;

        printf("[%d] sent int payload %d to %d\n", my_rank, payload,
                target_rank);

        /* Send the message */
        MPI_Send(&payload, 1, MPI_INT, target_rank, 0, MPI_COMM_WORLD);
    }

    while(1) {
        int payload;

        /* Wait for reception of a message */
        MPI_Recv(&payload, 1, MPI_INT, MPI_ANY_SOURCE, 0, MPI_COMM_WORLD,
                MPI_STATUS_IGNORE);

        /* Receiving -1 means we need to exit */
        if(payload == -1) {
            printf("[%d] received stop signal, exiting\n", my_rank);
            break;
        }

        if(payload == BOUNCE_LIMIT) {
            /* We have bounced enough times, send the stop signal, i.e. a
             * message with -1 as payload, to all other processes */
            int stop_payload = -1;
            printf("[%d] broadcasting stop signal\n", my_rank, payload);

            for(int i=0; i<world_size; i++)
                if(i != my_rank)
                    MPI_Send(&stop_payload, 1, MPI_INT, i, 0, MPI_COMM_WORLD);
            break;
        }

        /* increment payload */
        payload++;
        int target_rank = my_rank;

        /* Choose the next process to send a message to */
        while(target_rank == my_rank)
            target_rank = rand()%world_size;

        printf("[%d] received payload %d, sending %d to %d\n", my_rank,
                payload-1, payload, target_rank);

        MPI_Send(&payload, 1, MPI_INT, target_rank, 0, MPI_COMM_WORLD);
    }

    MPI_Finalize();
}
```

You can download this code [here](https://github.com/olivierpierre/comp35112-devcontainer/blob/main/13-mpi/send-recv.c).

Recall that this code is executed by each process in our application.
We start by getting the total number of processes and our rank with `MPI_Comm_size` and `MPI_Comm_rank`.
Then the process of rank `0` will initialise the application, and sends with `MPI_Send` the initial message to a random process.
The rest of the code is an infinite loop in which each process starts by waiting for the reception of a message with `MPI_Recv`.
Once a message is received, the counter's value is increased and sent to a random process with `MPI_Send`.
When a process detects that the counter has reached its maximum value, it sends a special message (`-1`) to all processes indicating that they need to exit.

## Collective Operations

In addition to send and receive there are also various collective operations
They allow to easily create **barriers** (`MPI_Barrier`), and to **broadcast** a message to multiple processes (`MPI_Bcast`).
While broadcast sends the same piece of data to multiple processes, **scatter** (`MPI_Scatter`) breaks a data into parts and sends each part to a different process.
**Gather** (`MPI_Gather`) is the inverse of scatter and allows aggregating elements sent from multiple process into a single piece of data.
There is also reduce (`MPI_Reduce`), that allows to combine values sent by different processes with a reduction operation, for example an addition
With such operations, many programs make little use of the more basic primitives `MPI_Send`/`MPI_Recv`.

MPI also has other features, including **non-blocking communications** with `MPI_Isend` and `MPI_Ireceive`.
These functions do not wait for the request completion, and they return directly, so in general they are used in combination with `MPI_Test` to check the completion of a request, and `MPI_Wait` to wait for a completion.
There is also a feature called **persistent communications** that is useful to define messages that are sent repeatedly with the same arguments.
Furthermore, there are 3 **communication modes**:
- With the *standard* one, a call to send returns when the message has been sent but not necessarily yet received.
- With the *synchronous* one, a call to send returns when the message has been received.
- And with the *buffered* one, the send oprtation returns even before the message is sent, something that will be done later.
- Finally MPI also allows a process to directly write in the memory of another process using `MPI_Put` and `MPI_Get`.

This is just a very brief introduction to MPI.
To learn more, one can for example check out this [course](https://www.mcs.anl.gov/research/projects/mpi/tutorial/gropp/talk.html), as well as the official MPI [standard](https://www.mpi-forum.org/docs/).
