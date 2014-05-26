#pragma once

#ifdef __OPENCL_VERSION__
#pragma OPENCL EXTENSION cl_APPLE_fp64_ops : enable
#endif

//double depends on cl_khr_fp64 extension
// which isn't working on my machine ... 
typedef float real;
#ifdef __OPENCL_VERSION__
typedef float2 real2;
typedef float4 real4;
#else
typedef cl_float2 real2;
typedef cl_float4 real4;
#endif

#define DIM	2
#define NUM_STATES	2+DIM
#define GAMMA 1.4

struct Interface {
	//Roe-specific values
	real4 eigenvalues;
	real4 eigenvectors[NUM_STATES];			//stored as columns 
	real4 eigenvectorsInverse[NUM_STATES];	//
	real4 rTilde;
	real4 deltaQTilde;
	
	//base cell values
	real2 x;
	real4 flux;
	bool solid;
};
typedef struct Interface Interface;

struct Cell {
	//base cell values
	real4 q;
	real2 x;

	Interface interfaces[DIM];
};
typedef struct Cell Cell;
