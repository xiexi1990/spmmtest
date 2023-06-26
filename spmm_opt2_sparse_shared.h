#pragma once
#include "spmm_base.h"

class SPMM_OPT2_SPARSE_SHARED : public SPMM_BASE
{
public:
    using SPMM_BASE::SPMM_BASE;

    float *vout_ref;
    int *vin_sparse_selector;
    int dim_sparse;

protected:
    int *_warp4;
    int num_warps;
    

public:
    double do_test(bool timing, int dim);
protected:
    void run(int dim);

};
