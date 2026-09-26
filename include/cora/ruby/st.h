#ifndef CORA_RUBY_ST_H
#define CORA_RUBY_ST_H

#include "../ruby.h"

typedef uintptr_t st_data_t;
typedef uintptr_t st_index_t;

typedef struct st_table {
    st_index_t num_entries;
    void *entries;
    st_index_t capacity;
} st_table;

#define ST_CONTINUE 0
#define ST_STOP 1
#define ST_DELETE 2
#define ST_CHECK 3

st_table *st_init_numtable(void);
st_table *st_init_numtable_with_size(st_index_t size);
void st_free_table(st_table *table);
int st_insert(st_table *table, st_data_t key, st_data_t value);
int st_lookup(st_table *table, st_data_t key, st_data_t *value);
int st_delete(st_table *table, st_data_t *key, st_data_t *value);
int st_foreach(st_table *table, int (*callback)(st_data_t, st_data_t, st_data_t), st_data_t arg);
int st_strcasecmp(const char *a, const char *b);
int st_strncasecmp(const char *a, const char *b, size_t length);
#define ST2FIX(x) LONG2FIX(x)

#endif
