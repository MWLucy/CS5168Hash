#include "../common/book.h"
#include "lock.h"

#define SIZE    (100*1024*1024)
#define ELEMENTS    (SIZE / sizeof(unsigned int))
#define HASH_ENTRIES     1024

//Structure contains a key value pair as well as pointer to next entry.
//In this way it is very similar to a linked list.
struct Entry {
    unsigned int    key;
    void            *value;
    Entry           *next;
};

//Table Structure
struct Table {
    size_t  count;
    Entry   **entries;
    Entry   *pool;
};

//Here, a simple modulo is used to hash.
__device__ __host__ size_t hash( unsigned int key,
                                 size_t count ) {
    return key % count;
}

//Table initilization using CUDA memset and malloc.
void initialize_table( Table &table, int entries, int elements ) {
    table.count = entries;
    HANDLE_ERROR( cudaMalloc( (void**)&table.entries, entries * sizeof(Entry*)) );
    HANDLE_ERROR( cudaMemset( table.entries, 0, entries * sizeof(Entry*) ) );
    HANDLE_ERROR( cudaMalloc( (void**)&table.pool, elements * sizeof(Entry)) );
}

//This copies the table to the host memory so we can compare
//in the same way done in CPU
void copy_table_to_host( const Table &table, Table &hostTable) {
    hostTable.count = table.count;
    hostTable.entries = (Entry**)calloc( table.count, sizeof(Entry*) );
    hostTable.pool = (Entry*)malloc( ELEMENTS * sizeof( Entry ) );

    HANDLE_ERROR( cudaMemcpy( hostTable.entries, table.entries, table.count * sizeof(Entry*), cudaMemcpyDeviceToHost ) );
    HANDLE_ERROR( cudaMemcpy( hostTable.pool, table.pool, ELEMENTS * sizeof( Entry ), cudaMemcpyDeviceToHost ) );

    for (int i=0; i<table.count; i++) {
        if (hostTable.entries[i] != NULL)
            hostTable.entries[i] = (Entry*)((size_t)hostTable.entries[i] - (size_t)table.pool + (size_t)hostTable.pool);
    }
    for (int i=0; i<ELEMENTS; i++) {
        if (hostTable.pool[i].next != NULL)
            hostTable.pool[i].next = (Entry*)((size_t)hostTable.pool[i].next - (size_t)table.pool + (size_t)hostTable.pool);
    }
}

//Free table once done timing
void free_table( Table &table ) {
    HANDLE_ERROR( cudaFree( table.pool ) );
    HANDLE_ERROR( cudaFree( table.entries ) );
}

//Bulk of parallelism is done here.
__global__ void add_to_table( unsigned int *keys, void **values, Table table, Lock *lock ) {
    int tid = threadIdx.x + blockIdx.x * blockDim.x;
    int stride = blockDim.x * gridDim.x;

    while (tid < ELEMENTS) {
        unsigned int key = keys[tid];
        size_t hashValue = hash( key, table.count );
        for (int i=0; i<32; i++) {
            if ((tid % 32) == i) {
                Entry *location = &(table.pool[tid]);
                location->key = key;
                location->value = values[tid];
                lock[hashValue].lock();
                location->next = table.entries[hashValue];
                table.entries[hashValue] = location;
                lock[hashValue].unlock();
            }
        }
        tid += stride;
    }
}

//Verification of table same as in CPU
void verify_table( const Table &dev_table ) {
    Table   table;
    copy_table_to_host( dev_table, table );

    int count = 0;
    for (size_t i=0; i<table.count; i++) {
        Entry   *current = table.entries[i];
        while (current != NULL) {
            ++count;
            if (hash( current->key, table.count ) != i)
                printf( "%d hashed to %ld, but was located at %ld\n", current->key, hash(current->key, table.count), i );
            current = current->next;
        }
    }
    if (count != ELEMENTS)
        printf( "%d elements found in hash table.  Should be %ld\n", count, ELEMENTS );
    else
        printf( "All %d elements found in hash table.\n", count );

    free( table.pool );
    free( table.entries );
}


int main( void ) {
    unsigned int *buffer = (unsigned int*)big_random_block( SIZE );

    unsigned int *dev_keys;
    void         **dev_values;
    HANDLE_ERROR( cudaMalloc( (void**)&dev_keys, SIZE ) );
    HANDLE_ERROR( cudaMalloc( (void**)&dev_values, SIZE ) );
    HANDLE_ERROR( cudaMemcpy( dev_keys, buffer, SIZE, cudaMemcpyHostToDevice ) );

    Table table;
    initialize_table( table, HASH_ENTRIES, ELEMENTS );

    //Creation of atomic locks
    Lock    lock[HASH_ENTRIES];
    Lock    *dev_lock;
    HANDLE_ERROR( cudaMalloc( (void**)&dev_lock, HASH_ENTRIES * sizeof( Lock ) ) );
    HANDLE_ERROR( cudaMemcpy( dev_lock, lock, HASH_ENTRIES * sizeof( Lock ), cudaMemcpyHostToDevice ) );

    //CudaEvent is used for timing
    cudaEvent_t     start, stop;
    HANDLE_ERROR( cudaEventCreate( &start ) );
    HANDLE_ERROR( cudaEventCreate( &stop ) );
    HANDLE_ERROR( cudaEventRecord( start, 0 ) );

    add_to_table<<<60,256>>>( dev_keys, dev_values, table, dev_lock );

    HANDLE_ERROR( cudaEventRecord( stop, 0 ) );
    HANDLE_ERROR( cudaEventSynchronize( stop ) );
    float   elapsedTime;
    HANDLE_ERROR( cudaEventElapsedTime( &elapsedTime, start, stop ) );
    printf( "Time to hash:  %3.1f ms\n", elapsedTime );

    verify_table( table );

    HANDLE_ERROR( cudaEventDestroy( start ) );
    HANDLE_ERROR( cudaEventDestroy( stop ) );
    free_table( table );
    HANDLE_ERROR( cudaFree( dev_lock ) );
    HANDLE_ERROR( cudaFree( dev_keys ) );
    HANDLE_ERROR( cudaFree( dev_values ) );
    free( buffer );
    return 0;
}

