// small_dense.zig --------------------------------------------------------------------------------------------|
// Shared row-major indexing for the small dense systems built during reference-data preparation.              |
//                                                                                                             |
// This file is intentionally narrow. The only live helper is index(row, column, column_count), because both   |
// cross-section fitting and Cholesky solving need to address the same flat matrix layout without introducing  |
// a matrix object or copying through a wrapper type.                                                          |
//                                                                                                             |
// called by                                                                                                   |
//   input/reference/cross_sections.zig assembles weighted polynomial normal equations for                     |
//     differentialVector and effectiveCrossSectionFromSensitivity.                                            |
//   common/math/linalg/cholesky.zig factors and solves those same flat normal-equation matrices.              |
//   unit tests lock the address formula so callers agree on the slice layout.                                 |
//                                                                                                             |
// route map                                                                                                   |
//   cross_sections.differentialVector                                                                         |
//     -> normal[dense.index(row, column, term_count)] accumulates the weighted Vandermonde normal matrix      |
//     -> cholesky.factorInPlace / solveWithFactor use the same term_count stride                              |
//   cholesky.factorInPlace / solveWithFactor                                                                  |
//     -> dense.index maps lower-triangle reads and diagonal writes in the caller-owned factor slice           |
//                                                                                                             |
// hot path                                                                                                    |
//   The index arithmetic is inside the small dense factor/solve loops. Keeping it as one inlineable formula   |
//   gives both callers the same layout while still compiling down to row * column_count + column.             |
//                                                                                                             |
// memory                                                                                                      |
//   Matrices are caller-owned []f64 slices. This file owns no storage, performs no allocation, and carries no |
//   shape checks; callers validate slice lengths at the operation boundary.                                   |
// ------------------------------------------------------------------------------------------------------------|

pub fn index(row: usize, column: usize, column_count: usize) usize {
    return row * column_count + column;
}
