#pragma once
#include <stdint.h>
typedef struct { uint64_t used, total, compressed, swap; int valid, pressure, swapValid; } MemoryReading;
typedef struct { uint64_t user, system, idle, nice; int valid; } CPUReading;
typedef struct { int pid, parent; uint64_t bytes; char path[4096]; } ProcessReading;
typedef struct { uint64_t received, sent; char name[32]; int valid; } NetworkReading;
MemoryReading read_memory(void);
CPUReading read_cpu(void);
NetworkReading read_network(void);
int process_capacity(void);
int read_processes(ProcessReading *out, int capacity);
uint64_t own_footprint(void);
