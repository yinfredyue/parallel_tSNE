#include "perplexity_search.h"


__global__ void ComputePijKernel(
    volatile float *__restrict__ pij,
    const float *__restrict__ squared_dist,
    const float *__restrict__ betas,
    const unsigned int num_points,
    const unsigned int num_near_neighbors)
{
    register int TID, i, j;
    register float dist, beta;

    TID = threadIdx.x + blockIdx.x * blockDim.x;
    if (TID >= num_points * num_near_neighbors)
        return;

    i = TID / num_near_neighbors;
    j = TID % num_near_neighbors;

    beta = betas[i];
    dist = squared_dist[TID];

    // condition deals with evaluation of pii
    // FAISS neighbor zero is i so ignore it
    pij[TID] = (j == 0 & dist == 0.0f) ? 0.0f : __expf(-beta * dist); //TODO: This probably never evaluates to true
}


__global__ void PerplexitySearchKernel(
    volatile float *__restrict__ betas,
    volatile float *__restrict__ lower_bound,
    volatile float *__restrict__ upper_bound,
    volatile int *__restrict__ found,
    const float *__restrict__ neg_entropy,
    const float *__restrict__ row_sum,
    const float perplexity_target,
    const float epsilon,
    const int num_points)
{
    register int i, is_found;
    register float perplexity, neg_ent, sum_P, perplexity_diff, beta, min_beta, max_beta;
    i = threadIdx.x + blockIdx.x * blockDim.x;
    if (i >= num_points)
        return;

    neg_ent = neg_entropy[i];
    sum_P = row_sum[i];
    beta = betas[i];

    min_beta = lower_bound[i];
    max_beta = upper_bound[i];

    perplexity = (neg_ent / sum_P) + __logf(sum_P);
    perplexity_diff = perplexity - __logf(perplexity_target);
    is_found = (perplexity_diff < epsilon && -perplexity_diff < epsilon);
    if (!is_found)
    {
        if (perplexity_diff > 0)
        {
            min_beta = beta;
            beta = (max_beta == FLT_MAX || max_beta == -FLT_MAX) ? beta * 2.0f : (beta + max_beta) / 2.0f;
        }
        else
        {
            max_beta = beta;
            beta = (min_beta == -FLT_MAX || min_beta == FLT_MAX) ? beta / 2.0f : (beta + min_beta) / 2.0f;
        }
        lower_bound[i] = min_beta;
        upper_bound[i] = max_beta;
        betas[i] = beta;
    }
    found[i] = is_found;
}


void SearchPerplexity(          cublasHandle_t &handle,
                                thrust::device_vector<float> &pij,
                                thrust::device_vector<float> &squared_dist,
                                const float perplexity_target,
                                const float epsilon,
                                const int num_points,
                                const int num_near_neighbors)
{
    // use beta instead of sigma (this matches the bhtsne code but not the paper)
    // beta is just multiplicative instead of divisive (changes the way binary search works)
    printf("SearchPerplexity called\n");
    return;

    thrust::device_vector<float> betas(num_points, 1.0f);
    thrust::device_vector<float> lower_bound_beta(num_points, -FLT_MAX);
    thrust::device_vector<float> upper_bound_beta(num_points, FLT_MAX);
    thrust::device_vector<float> entropy(num_points * num_near_neighbors);
    thrust::device_vector<int> found(num_points);

    // TODO: this doesn't really fit with the style
    const int BLOCKSIZE1 = 1024;
    const int NBLOCKS1 = iDivUp(num_points * num_near_neighbors, BLOCKSIZE1);

    const int BLOCKSIZE2 = 128;
    const int NBLOCKS2 = iDivUp(num_points, BLOCKSIZE2);

    size_t iters = 0;
    int all_found = 0;
    thrust::device_vector<float> row_sum, neg_entropy;
    do
    {
        // compute Gaussian Kernel row
        ComputePijKernel<<<NBLOCKS1, BLOCKSIZE1>>>(
            thrust::raw_pointer_cast(pij.data()),
            thrust::raw_pointer_cast(squared_dist.data()),
            thrust::raw_pointer_cast(betas.data()),
            num_points, num_near_neighbors);
        GpuErrorCheck(cudaDeviceSynchronize());

        // compute entropy of current row
        row_sum = tsnecuda::util::ReduceSum(handle, pij, num_near_neighbors, num_points, 0);
        thrust::transform(pij.begin(), pij.end(), entropy.begin(), tsnecuda::util::FunctionalEntropy());
        neg_entropy = tsnecuda::util::ReduceAlpha(handle, entropy, num_near_neighbors, num_points, -1.0f, 0);

        // binary search for beta
        PerplexitySearchKernel<<<NBLOCKS2, BLOCKSIZE2>>>(
            thrust::raw_pointer_cast(betas.data()),
            thrust::raw_pointer_cast(lower_bound_beta.data()),
            thrust::raw_pointer_cast(upper_bound_beta.data()),
            thrust::raw_pointer_cast(found.data()),
            thrust::raw_pointer_cast(neg_entropy.data()),
            thrust::raw_pointer_cast(row_sum.data()),
            perplexity_target, epsilon, num_points);
        GpuErrorCheck(cudaDeviceSynchronize());

        // Check if searching is done
        all_found = thrust::reduce(found.begin(), found.end(), 1, thrust::minimum<int>());
        iters++;
    } while (!all_found && iters < 200);
    // TODO: Warn if iters == 200 because perplexity not found?

    tsnecuda::util::BroadcastMatrixVector(pij, row_sum, num_near_neighbors, num_points, thrust::divides<float>(), 1, 1.0f);
}

