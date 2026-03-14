#ifndef ZDISAMAR_DISAMAR_H
#define ZDISAMAR_DISAMAR_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ZDISAMAR_ABI_VERSION 1u

typedef struct zdisamar_engine zdisamar_engine;
typedef struct zdisamar_plan zdisamar_plan;
typedef struct zdisamar_workspace zdisamar_workspace;

typedef enum zdisamar_status {
  ZDISAMAR_STATUS_OK = 0,
  ZDISAMAR_STATUS_INVALID_ARGUMENT = 1,
  ZDISAMAR_STATUS_INTERNAL = 2
} zdisamar_status;

typedef enum zdisamar_solver_mode {
  ZDISAMAR_SOLVER_SCALAR = 0,
  ZDISAMAR_SOLVER_POLARIZED = 1,
  ZDISAMAR_SOLVER_DERIVATIVE_ENABLED = 2
} zdisamar_solver_mode;

typedef struct zdisamar_plan_desc {
  const char *model_family;
  const char *transport_solver;
  const char *retrieval_algorithm;
  uint32_t solver_mode;
} zdisamar_plan_desc;

typedef struct zdisamar_scene_desc {
  const char *scene_id;
  double spectral_start_nm;
  double spectral_end_nm;
  uint32_t spectral_samples;
} zdisamar_scene_desc;

typedef struct zdisamar_request_desc {
  struct zdisamar_scene_desc scene;
  uint32_t diagnostics_flags;
} zdisamar_request_desc;

typedef struct zdisamar_result_desc {
  uint64_t plan_id;
  const char *scene_id;
  const char *solver_route;
  uint32_t status;
} zdisamar_result_desc;

zdisamar_status zdisamar_engine_create(zdisamar_engine **out_engine);
void zdisamar_engine_destroy(zdisamar_engine *engine);

zdisamar_status zdisamar_plan_prepare(
    zdisamar_engine *engine,
    const zdisamar_plan_desc *plan_desc,
    zdisamar_plan **out_plan);
void zdisamar_plan_destroy(zdisamar_plan *plan);

zdisamar_status zdisamar_workspace_create(
    zdisamar_engine *engine,
    zdisamar_workspace **out_workspace);
void zdisamar_workspace_destroy(zdisamar_workspace *workspace);

zdisamar_status zdisamar_execute(
    zdisamar_engine *engine,
    const zdisamar_plan *plan,
    zdisamar_workspace *workspace,
    const zdisamar_request_desc *request_desc,
    zdisamar_result_desc *out_result);

#ifdef __cplusplus
}
#endif

#endif
