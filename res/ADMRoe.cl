/*
The components of the Roe solver specific to the ADM equations
paritcularly the spectral decomposition

This currently only supports 1D
*/

#include "HydroGPU/Roe.h"

__kernel void calcEigenBasis(
	__global real* eigenvaluesBuffer,
	__global real* eigenfieldsInverseBuffer,
	__global real* eigenfieldsBuffer,
	const __global real* stateBuffer)
{
	int4 i = (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0);
	if (i.x < 2 || i.x >= SIZE_X - 1 
#if DIM > 1
		|| i.y < 2 || i.y >= SIZE_Y - 1
#endif
#if DIM > 2
		|| i.z < 2 || i.z >= SIZE_Z - 1
#endif
	) return;
	int index = INDEXV(i);

#if NUM_STATES != 5
#error only supports 1D 
#endif
	
	//for (int side = 0; side < DIM; ++side) {
	{const int side = 0;
		int indexPrev = index - stepsize[side];

		int interfaceIndex = side + DIM * index;
		
		const __global real* stateL = stateBuffer + NUM_STATES * indexPrev;
		const __global real* stateR = stateBuffer + NUM_STATES * index;
		
		__global real* eigenvalues = eigenvaluesBuffer + NUM_STATES * interfaceIndex;
		__global real* eigenfieldsInverse = eigenfieldsInverseBuffer + EIGENFIELD_SIZE * interfaceIndex;
		__global real* eigenfields = eigenfieldsBuffer + EIGENFIELD_SIZE * interfaceIndex;

		//q0 = d/dx ln alpha
		//q1 = d/dx ln g = d/dx ln g_xx

		//I'm assigning the fwd and reverse eigenfield info the same
		// I guess only the linear systems technically need both
		// I should make that a special case of the base Roe solver
		// and merge eigenvectorsBuffer and eigenvectorsInverse buffer into one eigenfieldsBuffer
		real alpha = .5f * (stateL[STATE_ALPHA] + stateR[STATE_ALPHA]);
		real f = ADM_BONA_MASSO_F;
		real g = .5f * (stateL[STATE_G] + stateR[STATE_G]);
		
		//the only variable used for the eigenfield functions
		eigenfieldsInverse[EIGENFIELD_F] = eigenfields[EIGENFIELD_F] = f;

		//eigenvalues

		real eigenvalue = alpha * sqrt(f/g); 
		eigenvalues[0] = -eigenvalue;
		eigenvalues[1] = 0.f;
		eigenvalues[2] = 0.f;
		eigenvalues[3] = 0.f;
		eigenvalues[4] = eigenvalue;
	}
}

void eigenfieldTransform(
	real* results,
	const __global real* eigenfield,
	const real* input)
{
	//cell
	real v1 = input[STATE_A];
	real v2 = input[STATE_D];
	real v3 = input[STATE_K_TILDE];

	//interface
	real f = eigenfield[EIGENFIELD_F];
	real sqrt_f = sqrt(f);

	//correlates with the eigenvalues
	results[0] = v1 / (2.f * f) - v3 / (2.f * sqrt_f);
	results[1] = 0.f;
	results[2] = 0.f;
	results[3] = -2.f * v1 / f + v2;
	results[4] = v1 / (2.f * f) + v3 / (2.f * sqrt_f);
}

void eigenfieldInverseTransform(
	__global real* results,
	const __global real* eigenfield,
	const real* input)
{
	//cell
	//correlates with the rows written in the eigenfieldTransform function
	real v1 = input[0];
	real v2 = input[3];
	real v3 = input[4];

	//interface
	real f = eigenfield[EIGENFIELD_F];
	real sqrt_f = sqrt(f);

	results[STATE_ALPHA] = 0.f;
	results[STATE_G] = 0.f;
	results[STATE_A] = (v1 + v3) * f;
	results[STATE_D] = 2.f * v1 + v2 + 2.f * v3;
	results[STATE_K_TILDE] = sqrt_f * (v3 - v1);
}

__kernel void addSource(
	__global real* derivBuffer,
	const __global real* stateBuffer)
{
	int4 i = (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0);
	if (i.x < 2 || i.x >= SIZE_X - 2 
#if DIM > 1
		|| i.y < 2 || i.y >= SIZE_Y - 2 
#endif
#if DIM > 2
		|| i.z < 2 || i.z >= SIZE_Z - 2
#endif
	) {
		return;
	}
	int index = INDEXV(i);
	
	__global real* deriv = derivBuffer + NUM_STATES * index;
	const __global real* state = stateBuffer + NUM_STATES * index;
	real alpha = state[STATE_ALPHA];
	real g = state[STATE_G];
	real A = state[STATE_A];
	real D = state[STATE_D];
	real KTilde = state[STATE_K_TILDE];
	real f = ADM_BONA_MASSO_F;
	real df_dalpha = ADM_BONA_MASSO_DF_DALPHA;
	real tmp1 = alpha / sqrt(g);
	real tmp2 = .5f * D - A;
	deriv[STATE_ALPHA] -= tmp1 * alpha * f * KTilde / g;
	deriv[STATE_G] -= 2.f * tmp1 * KTilde;
	deriv[STATE_A] += KTilde * tmp1 * (f * tmp2 - A * alpha * df_dalpha);
	deriv[STATE_D] += 2.f * KTilde * tmp1 * tmp2;
	deriv[STATE_K_TILDE] += A * tmp1 * tmp2;
}
