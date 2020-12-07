#include "../common/book.h"

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
    Entry   *firstFree;
};

//Here, the hash is more complex.
size_t hash( unsigned int key, size_t count ) {
    a = (a+0x7ed55d16) + (a<<12);
    a = (a^0xc761c23c) ^ (a>>19);
    a = (a+0x165667b1) + (a<<5);
    a = (a+0xd3a2646c) ^ (a<<9);
    a = (a+0xfd7046c5) + (a<<3);
    a = (a^0xb55a4f09) ^ (a>>16);
    return a;
}

//Table initilization using CUDA memset and malloc.
void initialize_table( Table &table, int entries, int elements ) {
    table.count = entries;
    table.entries = (Entry**)calloc( entries, sizeof(Entry*) );
    table.pool = (Entry*)malloc( elements * sizeof( Entry ) );
    table.firstFree = table.pool;
}

//Free table once done timing
void free_table( Table &table ) {
    free( table.entries );
    free( table.pool );
}

//Implementation of cuckoo hash insertion
void add_to_table( Table &table, unsigned int key, void *value ) {
    size_t hashValue = hash( key, table.count );
    bool hashEmpty = false;
    while hashEmpty == false{
        Entry *location = table.firstFree++;
        location->key = key;
        location->value = value;
        location->next = table.entries[hashValue];
    }

    table.entries[hashValue] = location;
}

//Here, the table is verified to make sure all insertions were successful
void verify_table( const Table &table ) {
    int count = 0;
    for (size_t i=0; i<table.count; i++) {
        Entry   *current = table.entries[i];
        while (current != NULL) {
            ++count;
            if (hash( current->key, table.count ) != i)
                printf( "%d hashed to %ld, but was located at %ld\n", current->key, hash( current->key, table.count ), i );
            current = current->next;
        }
    }
    if (count != ELEMENTS)
        printf( "%d elements found in hash table.  Should be %ld\n", count, ELEMENTS );
    else
        printf( "All %d elements found in hash table.\n", count);
}


int main( void ) {
    unsigned int *buffer = (unsigned int*)big_random_block( SIZE );

    Table table;
    initialize_table( table, HASH_ENTRIES, ELEMENTS );
    
    //clock is used for timing.
    clock_t start, stop;
    start = clock();

    for (int i=0; i<ELEMENTS; i++) {
        add_to_table( table, buffer[i], (void*)NULL );
    }

    stop = clock();
    float   elapsedTime = (float)(stop - start) / (float)CLOCKS_PER_SEC * 1000.0f;
    printf( "Time to hash:  %3.1f ms\n", elapsedTime );


    verify_table( table );

    free_table( table );
    free( buffer );
    return 0;
}

