#ifndef ZDISAMAR_PLUGIN_H
#define ZDISAMAR_PLUGIN_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ZDISAMAR_PLUGIN_ABI_VERSION 1u

typedef enum zdisamar_plugin_lane {
  ZDISAMAR_PLUGIN_DECLARATIVE = 0,
  ZDISAMAR_PLUGIN_NATIVE = 1
} zdisamar_plugin_lane;

typedef struct zdisamar_plugin_capability {
  const char *slot;
  const char *name;
} zdisamar_plugin_capability;

typedef struct zdisamar_plugin_info {
  const char *plugin_id;
  const char *plugin_version;
  uint32_t abi_version;
  uint32_t capability_count;
  const zdisamar_plugin_capability *capabilities;
  uint32_t lane;
} zdisamar_plugin_info;

typedef struct zdisamar_host_api {
  void (*log_message)(int32_t level, const char *message, void *user_data);
  void *user_data;
} zdisamar_host_api;

typedef struct zdisamar_plugin_vtable {
  int32_t (*prepare)(const void *plan_context, void *plugin_state);
  int32_t (*execute)(const void *request_view, void *plugin_state);
  void (*destroy)(void *plugin_state);
} zdisamar_plugin_vtable;

typedef int32_t (*zdisamar_plugin_entry_fn)(
    const zdisamar_host_api *host_api,
    const zdisamar_plugin_info **out_info,
    const zdisamar_plugin_vtable **out_vtable);

#ifdef __cplusplus
}
#endif

#endif
