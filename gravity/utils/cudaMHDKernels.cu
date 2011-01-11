#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#ifdef UNIX
#include <stdint.h>
#include <unistd.h>
#endif
#include "mex.h"

// CUDA
#include "cuda.h"
#include "cuda_runtime.h"
#include "cublas.h"
#include "GPUmat.hh"

// static paramaters
static int init = 0;
static GPUmat *gm;

double **getSourcePointers(const mxArray *prhs[], int num, int *retNumel);
double **makeDestinationArrays(GPUtype src, mxArray *retArray[], int howmany);
//double *makeDestinationArray(GPUtype src, mxArray *retArray[]);

#define OP_SOUNDSPEED 1
#define OP_GASPRESSURE 2
#define OP_TOTALPRESSURE 3
#define OP_MAGPRESSURE 4
#define OP_TOTALANDSND 5
#define OP_WARRAYS 6
#define OP_RELAXINGFLUX 7
#define OP_SEPERATELRFLUX 8
__global__ void cukern_Soundspeed(double *rho, double *E, double *px, double *py, double *pz, double *bx, double *by, double *bz, double *dout, double gam, int n);
__global__ void cukern_GasPressure(double *rho, double *E, double *px, double *py, double *pz, double *bx, double *by, double *bz, double *dout, double gam, int n);
__global__ void cukern_TotalPressure(double *rho, double *E, double *px, double *py, double *pz, double *bx, double *by, double *bz, double *dout, double gam, int n);
__global__ void cukern_MagneticPressure(double *bx, double *by, double *bz, double *dout, int n);
__global__ void cukern_TotalAndSound(double *rho, double *E, double *px, double *py, double *pz, double *bx, double *by, double *bz, double *total, double *sound, double gam, int n);
__global__ void cukern_CalcWArrays(double *rho, double *E, double *px, double *py, double *pz, double *bx, double *by, double *bz, double *P, double *Cfreeze, double *rhoW, double *enerW, double *pxW, double *pyW, double *pzW, int dir, int n);

__global__ void cukern_SeperateLRFlux(double *arr, double *wArr, double *left, double *right, int n);
__global__ void cukern_PerformFlux(double *array0, double *Cfreeze, double *fluxRa, double *fluxRb, double *fluxLa, double *fluxLb, double *out, double lambda, int n);

#define BLOCKWIDTH 256
#define THREADLOOPS 1


void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[]) {
  if (init == 0) {
    // Initialize function
    // mexLock();
    // load GPUmat
    gm = gmGetGPUmat();
    init = 1;
  }

  // Determine appropriate number of arguments for RHS
  if (nrhs < 2) mexErrMsgTxt("Require at least (computation type, input argument)");
  int operation = (int)*mxGetPr(prhs[0]);

  dim3 blocksize; blocksize.x = BLOCKWIDTH; blocksize.y = blocksize.z = 1;
  int numel; dim3 gridsize;

  // Select the appropriate kernel to invoke
  if((operation == OP_SOUNDSPEED) || (operation == OP_GASPRESSURE) || (operation == OP_TOTALPRESSURE)) {
    if( (nlhs != 1) || (nrhs != 10)) { mexErrMsgTxt("Soundspeed operator is Cs = cudaMHDKernels(1, rho, E, px, py, pz, bx, by, bz, gamma)"); }
    double gam = *mxGetPr(prhs[9]);
    double **srcs = getSourcePointers(prhs, 8, &numel);
    gridsize.x = numel / (BLOCKWIDTH*THREADLOOPS); if(gridsize.x * (BLOCKWIDTH*THREADLOOPS) < numel) gridsize.x++;
    gridsize.y = gridsize.z =1;
    double **destPtr = makeDestinationArrays(gm->gputype.getGPUtype(prhs[1]), plhs, 1);
//printf("%i %i %i %i %i %i\n", blocksize.x, blocksize.y, blocksize.z, gridsize.x, gridsize.y, gridsize.z);
    switch(operation) {
      case OP_SOUNDSPEED:       cukern_Soundspeed<<<gridsize, blocksize>>>(srcs[0], srcs[1], srcs[2], srcs[3], srcs[4], srcs[5], srcs[6], srcs[7], destPtr[0], gam, numel); break;
      case OP_GASPRESSURE:     cukern_GasPressure<<<gridsize, blocksize>>>(srcs[0], srcs[1], srcs[2], srcs[3], srcs[4], srcs[5], srcs[6], srcs[7], destPtr[0], gam, numel); break;
      case OP_TOTALPRESSURE: cukern_TotalPressure<<<gridsize, blocksize>>>(srcs[0], srcs[1], srcs[2], srcs[3], srcs[4], srcs[5], srcs[6], srcs[7], destPtr[0], gam, numel); break;
    }
    free(destPtr);

  } else if((operation == OP_MAGPRESSURE)) {
    if( (nlhs != 1) || (nrhs != 4)) { mexErrMsgTxt("Magnetic pressure operator is Pm = cudaMHDKernels(4, bx, by, bz)"); }

    double **srcs = getSourcePointers(prhs, 3, &numel);
    gridsize.x = numel / (BLOCKWIDTH*THREADLOOPS); if(gridsize.x * (BLOCKWIDTH*THREADLOOPS) < numel) gridsize.x++;
    gridsize.y = gridsize.z =1;
    double **destPtr = makeDestinationArrays(gm->gputype.getGPUtype(prhs[1]), plhs, 1);

    cukern_MagneticPressure<<<gridsize, blocksize>>>(srcs[0], srcs[1], srcs[2], destPtr[0], numel);
    free(destPtr);

  } else if((operation == OP_TOTALANDSND)) {
    if( (nlhs != 2) || (nrhs != 10)) { mexErrMsgTxt("Soundspeed operator is [Ptot Cs] = cudaMHDKernels(5, rho, E, px, py, pz, bx, by, bz, gamma)"); }
    double gam = *mxGetPr(prhs[9]);
    double **srcs = getSourcePointers(prhs, 8, &numel);
    gridsize.x = numel / (BLOCKWIDTH*THREADLOOPS); if(gridsize.x * (BLOCKWIDTH*THREADLOOPS) < numel) gridsize.x++;
    gridsize.y = gridsize.z =1;
    double **destPtr = makeDestinationArrays(gm->gputype.getGPUtype(prhs[1]), plhs, 2);

    cukern_TotalAndSound<<<gridsize, blocksize>>>(srcs[0], srcs[1], srcs[2], srcs[3], srcs[4], srcs[5], srcs[6], srcs[7], destPtr[0], destPtr[1], gam, numel);
    free(destPtr);
  } else if ((operation == OP_WARRAYS)) {
    if( (nlhs != 5) || (nrhs != 12)) { mexErrMsgTxt("solving W operator is [rhoW enerW pxW pyW pzW] = cudaMHDKernels(6, rho, E, px, py, pz, bx, by, bz, P, cFreeze, direction)"); }
    int dir = (int)*mxGetPr(prhs[11]);
    double **srcs = getSourcePointers(prhs, 10, &numel);
    gridsize.x = numel / (BLOCKWIDTH*THREADLOOPS); if(gridsize.x * (BLOCKWIDTH*THREADLOOPS) < numel) gridsize.x++;
    gridsize.y = gridsize.z =1;
    double **destPtr = makeDestinationArrays(gm->gputype.getGPUtype(prhs[1]), plhs, 5);

    cukern_CalcWArrays<<<gridsize, blocksize>>>(srcs[0], srcs[1], srcs[2], srcs[3], srcs[4], srcs[5], srcs[6], srcs[7], srcs[8], srcs[9], destPtr[0], destPtr[1], destPtr[2], destPtr[3], destPtr[4], dir, numel);
    free(destPtr);
  } else if ((operation == OP_RELAXINGFLUX)) {
    if( (nlhs != 1) || (nrhs != 8)) { mexErrMsgTxt("relaxing flux operator is fluxed = cudaMHDKernels(7, old, tempfreeze, right, right_shifted, left, left_shifted, lambda)"); }
    double lambda = *mxGetPr(prhs[7]);
    double **srcs = getSourcePointers(prhs, 6, &numel);
    gridsize.x = numel / (BLOCKWIDTH*THREADLOOPS); if(gridsize.x * (BLOCKWIDTH*THREADLOOPS) < numel) gridsize.x++;
    gridsize.y = gridsize.z =1;
    double **destPtr = makeDestinationArrays(gm->gputype.getGPUtype(prhs[1]), plhs, 1);

    cukern_PerformFlux<<<gridsize, blocksize>>>(srcs[0], srcs[1], srcs[2], srcs[3], srcs[4], srcs[5], destPtr[0], lambda, numel);
    free(destPtr);
  } else if ((operation == OP_SEPERATELRFLUX)) {
    if ((nlhs != 2) || (nrhs != 3)) { mexErrMsgTxt("flux seperation operator is [Fl Fr] = cudaMHDKernels(8, array, wArray)"); }
    double **srcs = getSourcePointers(prhs, 2, &numel);
    gridsize.x = numel / (BLOCKWIDTH*THREADLOOPS); if(gridsize.x * (BLOCKWIDTH*THREADLOOPS) < numel) gridsize.x++;
    gridsize.y = gridsize.z =1;
    double **destPtr = makeDestinationArrays(gm->gputype.getGPUtype(prhs[1]), plhs, 2);

    cukern_SeperateLRFlux<<<gridsize, blocksize>>>(srcs[0], srcs[1], destPtr[0], destPtr[1], numel);
    free(destPtr);
  }

}

// Given the RHS and how many cuda arrays we expect, extracts a set of pointers to GPU memory for us
// Also conveniently checked for equal array extent and returns it for us
double **getSourcePointers(const mxArray *prhs[], int num, int *retNumel)
{
  GPUtype src;
  double **gpuPointers = (double **)malloc(num * sizeof(double *));
  int iter;
  int numel = gm->gputype.getNumel(gm->gputype.getGPUtype(prhs[1]));
  for(iter = 0; iter < num; iter++) {
    src = gm->gputype.getGPUtype(prhs[iter+1]);
    if (gm->gputype.getNumel(src) != numel) { free(gpuPointers); mexErrMsgTxt("Fatal: Arrays contain nonequal number of elements."); }
    gpuPointers[iter] = (double *)gm->gputype.getGPUptr(src);
  }

retNumel[0] = numel;
return gpuPointers;
}

// Creates destination array that the kernels write to; Returns the GPU memory pointer, and assigns the LHS it's passed
double **makeDestinationArrays(GPUtype src, mxArray *retArray[], int howmany)
{
int d = gm->gputype.getNdims(src);
const int *ssize = gm->gputype.getSize(src);
int x;
int newsize[3];
for(x = 0; x < 3; x++) (x < d) ? newsize[x] = ssize[x] : newsize[x] = 1;

double **rvals = (double **)malloc(howmany*sizeof(double *));
int i;
for(i = 0; i < howmany; i++) {
  GPUtype ra = gm->gputype.create(gpuDOUBLE, d, newsize, NULL);
  retArray[i] = gm->gputype.createMxArray(ra);
  rvals[i] = (double *)gm->gputype.getGPUptr(ra);
  }

return rvals;

}

//#define KERNEL_PREAMBLE int x = THREADLOOPS*(threadIdx.x + blockDim.x*blockIdx.x); if (x >= n) {return;} int imax; ((x+THREADLOOPS) > n) ? imax = n : imax = x + THREADLOOPS; for(; x < imax; x++)
#define KERNEL_PREAMBLE int x = threadIdx.x + blockDim.x*blockIdx.x; if (x >= n) { return; }

// THIS KERNEL CALCULATES SOUNDSPEED 
__global__ void cukern_Soundspeed(double *rho, double *E, double *px, double *py, double *pz, double *bx, double *by, double *bz, double *dout, double gam, int n)
{
//int x = threadIdx.x + blockDim.x*blockIdx.x;
//if (x >= n) { return; }
double gg1 = gam*(gam-1.0);

KERNEL_PREAMBLE
dout[x] = sqrt(abs( (gg1*(E[x] - .5*(px[x]*px[x] + py[x]*py[x] + pz[x]*pz[x])/rho[x]) + (2.0 -.5*gg1)*(bx[x]*bx[x] + by[x]*by[x] + bz[x]*bz[x]))/rho[x] ));
}

// THIS KERNEL CALCULATES GAS PRESSURE
__global__ void cukern_GasPressure(double *rho, double *E, double *px, double *py, double *pz, double *bx, double *by, double *bz, double *dout, double gam, int n)
{
//int x = threadIdx.x + blockDim.x*blockIdx.x; if (x >= n) { return; }

KERNEL_PREAMBLE
dout[x] = (gam-1.0)*abs(E[x] - .5*((px[x]*px[x]+py[x]*py[x]+pz[x]*pz[x])/rho[x] + bx[x]*bx[x]+by[x]*by[x]+bz[x]*bz[x]));
}

// THIS KERNEL CALCULATES TOTAL PRESSURE
__global__ void cukern_TotalPressure(double *rho, double *E, double *px, double *py, double *pz, double *bx, double *by, double *bz, double *dout, double gam, int n)
{
//int x = threadIdx.x + blockDim.x*blockIdx.x; if (x >= n) { return; }

KERNEL_PREAMBLE
dout[x] = (gam-1.0)*abs(E[x] - .5*((px[x]*px[x]+py[x]*py[x]+pz[x]*pz[x])/rho[x])) + .5*(2.0-gam)*(bx[x]*bx[x]+by[x]*by[x]+bz[x]*bz[x]);
}

// THIS KERNEL CALCULATES MAGNETIC PRESSURE
__global__ void cukern_MagneticPressure(double *bx, double *by, double *bz, double *dout, int n)
{
//int x = threadIdx.x + blockDim.x*blockIdx.x; if (x >= n) { return; }
KERNEL_PREAMBLE
dout[x] = .5*(bx[x]*bx[x]+by[x]*by[x]+bz[x]*bz[x]);
}

__global__ void cukern_TotalAndSound(double *rho, double *E, double *px, double *py, double *pz, double *bx, double *by, double *bz, double *total, double *sound, double gam, int n)
{
//int x = threadIdx.x + blockDim.x*blockIdx.x; if (x >= n) { return; }
double gg1 = gam*(gam-1.0);

KERNEL_PREAMBLE {
	total[x] = (gam-1.0)*abs(E[x] - .5*((px[x]*px[x]+py[x]*py[x]+pz[x]*pz[x])/rho[x])) + .5*(2.0-gam)*(bx[x]*bx[x]+by[x]*by[x]+bz[x]*bz[x]);
	sound[x]   = sqrt(abs( (gg1*(E[x] - .5*(px[x]*px[x] + py[x]*py[x] + pz[x]*pz[x])/rho[x]) + (2.0 -.5*gg1)*(bx[x]*bx[x] + by[x]*by[x] + bz[x]*bz[x]))/rho[x] ));
	}
}

__global__ void cukern_CalcWArrays(double *rho, double *E, double *px, double *py, double *pz, double *bx, double *by, double *bz, double *P, double *Cfreeze, double *rhoW, double *enerW, double *pxW, double *pyW, double *pzW, int dir, int n)
{
//int x = threadIdx.x + blockDim.x*blockIdx.x; if (x >= n) { return; }

KERNEL_PREAMBLE {

switch(dir) {
  case 1:
    rhoW[x]  = px[x] / Cfreeze[x];
    enerW[x] = (px[x] * (E[x] + P[x]) - bx[x]*(px[x]*bx[x]+py[x]*by[x]+pz[x]*bz[x]) ) / (rho[x] * Cfreeze[x]);
    pxW[x]   = (px[x]*px[x]/rho[x] + P[x] - bx[x]*bx[x])/Cfreeze[x];
    pyW[x]   = (px[x]*py[x]/rho[x]        - bx[x]*by[x])/Cfreeze[x];
    pzW[x]   = (px[x]*pz[x]/rho[x]        - bx[x]*bz[x])/Cfreeze[x];
    break;
  case 2:
    rhoW[x]  = py[x] / Cfreeze[x];
    enerW[x] = (py[x] * (E[x] + P[x]) - by[x]*(px[x]*bx[x]+py[x]*by[x]+pz[x]*bz[x]) ) / (rho[x] * Cfreeze[x]);
    pxW[x]   = (py[x]*px[x]/rho[x]        - by[x]*bx[x])/Cfreeze[x];
    pyW[x]   = (py[x]*py[x]/rho[x] + P[x] - by[x]*by[x])/Cfreeze[x];
    pzW[x]   = (py[x]*pz[x]/rho[x]        - by[x]*bz[x])/Cfreeze[x];
    break;
  case 3:
    rhoW[x]  = pz[x] / Cfreeze[x];
    enerW[x] = (pz[x] * (E[x] + P[x]) - bz[x]*(px[x]*bx[x]+py[x]*by[x]+pz[x]*bz[x]) ) / (rho[x] * Cfreeze[x]);
    pxW[x]   = (pz[x]*px[x]/rho[x]        - bz[x]*bx[x])/Cfreeze[x];
    pyW[x]   = (pz[x]*py[x]/rho[x]        - bz[x]*by[x])/Cfreeze[x];
    pzW[x]   = (pz[x]*pz[x]/rho[x] + P[x] - bz[x]*bz[x])/Cfreeze[x];
    break;
  }

}
/*mass.wArray    = mom(X).array ./ freezeSpd.array;

    %--- ENERGY DENSITY ---%
    ener.wArray    = velocity .* (ener.array + press) - mag(X).cellMag.array .* ...
                        ( mag(1).cellMag.array .* mom(1).array ...
                        + mag(2).cellMag.array .* mom(2).array ...
                        + mag(3).cellMag.array .* mom(3).array) ./ mass.array;
    ener.wArray    = ener.wArray ./ freezeSpd.array;

    %--- MOMENTUM DENSITY ---%
    for i=1:3
        mom(i).wArray    = (velocity .* mom(i).array + press*dirVec(i)...
                             - mag(X).cellMag.array .* mag(i).cellMag.array) ./ freezeSpd.array;
    end*/

}

__global__ void cukern_PerformFlux(double *array0, double *Cfreeze, double *fluxRa, double *fluxRb, double *fluxLa, double *fluxLb, double *out, double lambda, int n)
{
//int x = threadIdx.x + blockDim.x*blockIdx.x; if (x >= n) { return; }
KERNEL_PREAMBLE 
out[x] = array0[x] - lambda*Cfreeze[x]*(fluxRa[x] - fluxRb[x] + fluxLa[x] - fluxLb[x]);

//v(i).store.array = v(i).array - 0.5*fluxFactor .* tempFreeze .* ...
//                        ( v(i).store.fluxR.array - v(i).store.fluxR.shift(X,-1) ...
//                        + v(i).store.fluxL.array - v(i).store.fluxL.shift(X,1) );
}

__global__ void cukern_SeperateLRFlux(double *arr, double *wArr, double *left, double *right, int n)
{
//int x = threadIdx.x + blockDim.x*blockIdx.x; if (x >= n) { return; }
KERNEL_PREAMBLE {
	left[x]  = .5*(arr[x] - wArr[x]);
	right[x] = .5*(arr[x] + wArr[x]);
	}

}

