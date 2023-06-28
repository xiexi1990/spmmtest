#include "spmm_opt2_sparse_v3.h"
#include "data.h"
#include <string>
#include <iostream>
#define CONSTINT const int

using namespace std;

extern string base_dir, graph;

const int WARPS_PER_BLOCK = 12;

#define DIM_MUL(x) ((x + 31) / 32) * 32

__global__ void spmm_kernel_opt2_sparse_v3(const int *_warp4, const int *idx, const float *val, const float *vin_data, const int *vin_selector, float *vout, const int num_v, const int num_e, const int feat_in, const int dim_sparse, const int num_warps)
{
    const int4 *warp4 = reinterpret_cast<const int4 *>(_warp4);
    extern __shared__ float out_cache[];

    const int total_tid = blockIdx.x * blockDim.x + threadIdx.x; 
    const int total_warpid = total_tid / 32; 
    const int laneid = threadIdx.x % 32;  
    const int wid = threadIdx.x / 32;

    const int sparse_laneid = threadIdx.x % dim_sparse;  
    const int sparse_wid = threadIdx.x / dim_sparse;
    
    const int4 w_info = warp4[total_warpid];
    CONSTINT warp_row = w_info.x;
    CONSTINT warp_loc = w_info.y;
    CONSTINT warp_len = w_info.z;

    int4 sparse_w_info;
    int sparse_warp_row, sparse_warp_loc, sparse_warp_len;
    if(sparse_wid < blockDim.x / 32){
        sparse_w_info = warp4[blockIdx.x * blockDim.x / 32 + sparse_wid];
        sparse_warp_row = sparse_w_info.x;
        sparse_warp_loc = sparse_w_info.y;
        sparse_warp_len = sparse_w_info.z;
    }

#pragma unroll
    // for (int ext = 0; ext < (feat_in + 31) / 32; ext++)
    // {
    //     out_cache[wid * DIM_MUL(feat_in) + laneid + ext * 32] = 0;
    // }

    
    for (int ext = 0; ext < (feat_in + 32 - 1) / 32; ext++)
    {
        out_cache[threadIdx.x + ext * blockDim.x] = 0;
    }


    if (total_warpid >= num_warps )
        return; 
    
    
    __syncthreads();
    

    if(sparse_wid < blockDim.x / 32){
    #pragma unroll
        for (int i = 0; i < sparse_warp_len; i++)
        {
            int nz_loc = sparse_warp_loc + i;
            float left_val = __ldg(val + nz_loc);
            int right_loc = __ldg(idx + nz_loc) * dim_sparse + sparse_laneid;
            float right_val = vin_data[right_loc];
            // atomicAdd(&vout[warp_row * feat_in + __ldg(vin_selector + right_loc)], left_val * right_val);
            out_cache[sparse_wid * DIM_MUL(feat_in) + __ldg(vin_selector + right_loc)] += left_val * right_val;
        }
    }
    __syncthreads();
    
#pragma unroll
    for (int ext = 0; ext < (feat_in + 32 - 1) / 32; ext++)
    {
        atomicAdd(&vout[warp_row * feat_in + laneid + ext * 32], out_cache[wid * DIM_MUL(feat_in) + laneid + ext * 32]);
    }
    
    
}

void SPMM_OPT2_SPARSE_V3::run(int dim)
{
    int shared_size = (WARPS_PER_BLOCK + 0 * WARPS_PER_BLOCK / 2) * DIM_MUL(dim) * sizeof(float);

    spmm_kernel_opt2_sparse_v3<<<grid, block, shared_size>>>(_warp4, idx, val, vin, vin_sparse_selector, vout, num_v, num_e, dim, dim_sparse, num_warps);
}

double SPMM_OPT2_SPARSE_V3::do_test(bool timing, int dim)
{
    this->num_warps = cuda_read_array(&this->_warp4, "/home/xix22010/py_projects/graph_preprocess/warp_4/" + this->_graph + ".warp4") / 4;
    int block_num = (num_warps + (WARPS_PER_BLOCK) - 1) / (WARPS_PER_BLOCK);
    if (!timing)
    {
        cout << "block num = " << block_num << endl;
    }

    grid.x = block_num;
    block.x = WARPS_PER_BLOCK * 32;

    double ret = timing_body(timing, dim);

    cudaFree(this->_warp4);
    return ret;
}