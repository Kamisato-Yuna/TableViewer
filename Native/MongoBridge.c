#include "MongoBridge.h"
#include <mongoc/mongoc.h>
#include <pthread.h>
#include <string.h>
static pthread_once_t initialized = PTHREAD_ONCE_INIT;
static void initialize_driver(void) { mongoc_init(); }
void *tv_mongo_open(const char *text, char **error) {
    pthread_once(&initialized, initialize_driver);
    bson_error_t e;
    mongoc_uri_t *uri = mongoc_uri_new_with_error(text, &e);
    if (!uri) { *error = strdup("Invalid MongoDB URI. Check the connection settings."); return NULL; }
    mongoc_uri_set_option_as_int32(uri, "serverSelectionTimeoutMS", 8000);
    mongoc_uri_set_option_as_bool(uri, "serverSelectionTryOnce", false);
    mongoc_uri_set_option_as_int32(uri, "connectTimeoutMS", 8000);
    mongoc_uri_set_option_as_int32(uri, "socketTimeoutMS", 15000);
    mongoc_client_t *client = mongoc_client_new_from_uri(uri);
    mongoc_uri_destroy(uri);
    if (!client) { *error = strdup("Unable to create a MongoDB client."); return NULL; }
    mongoc_client_set_appname(client, "TableViewer");
    return client;
}
void tv_mongo_close(void *client) { if (client) mongoc_client_destroy(client); }
char *tv_mongo_command(void *client, const char *database, const char *json, char **error) {
    bson_error_t e;
    bson_t *command = bson_new_from_json((const uint8_t *)json, -1, &e);
    if (!command) { *error = strdup(e.message); return NULL; }
    bson_t reply;
    bool ok = mongoc_client_command_simple(client, database, command, NULL, &reply, &e);
    bson_destroy(command);
    if (!ok) { *error = strdup(e.message); bson_destroy(&reply); return NULL; }
    char *canonical = bson_as_canonical_extended_json(&reply, NULL);
    char *result = strdup(canonical);
    bson_free(canonical);
    bson_destroy(&reply);
    return result;
}
