#pragma once
#include <stdlib.h>
void *tv_mongo_open(const char *uri, char **error);
void tv_mongo_close(void *client);
char *tv_mongo_command(void *client, const char *database, const char *json, char **error);
