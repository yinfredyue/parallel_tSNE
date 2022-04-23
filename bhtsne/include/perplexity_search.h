/**
 * @brief Kernels for computing t-SNE perplexity and unnormalized pij.
 *
 * @file apply_forces.cu
 * @author Roshan Rao
 * @date 2018-05-08
 * Copyright (c) 2018, Regents of the University of California
 */
#ifndef SRC_INCLUDE_KERNELS_PERPLEXITY_SEARCH_H_
#define SRC_INCLUDE_KERNELS_PERPLEXITY_SEARCH_H_

#include "common.h"
#include "util/cuda_utils.h"
#include "util/reduce_utils.h"
#include "util/matrix_broadcast_utils.h"
#include "util/thrust_transform_functions.h"


__global__
void PerplexitySearchKernel(volatile float * __restrict__ betas,
                            volatile float * __restrict__ lower_bound,
                            volatile float * __restrict__ upper_bound,
                            volatile int * __restrict__ found,
                            const float * __restrict__ neg_entropy,
                            const float * __restrict__ row_sum,
                            const float perplexity_target,
                            const float epsilon,
                            const int num_points);
__global__
void ComputePijKernel(volatile float * __restrict__ pij,
                      const float * __restrict__ squared_dist,
                      const float * __restrict__ betas,
                      const unsigned int num_points,
                      const unsigned int num_near_neighbors);

void SearchPerplexity(cublasHandle_t &handle,
                            thrust::device_vector<float> &pij,
                            thrust::device_vector<float> &squared_dist,
                            const float perplexity_target,
                            const float epsilon,
                            const int num_points,
                            const int num_near_neighbors);


#endif
