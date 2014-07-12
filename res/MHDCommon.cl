#include "HydroGPU/Shared/Common.h"

__kernel void initVariables(
	__global real* stateBuffer)
{
	int4 i = (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0);
	int index = INDEXV(i);
	__global real* state = stateBuffer + NUM_STATES * index;
	//comes in rho, mx, my, mz, ETotal, bx, by, bz
	real totalEnergyDensity = state[4];	//ETotal = density * (eKinetic + eInternal + ePotential)
	real4 magneticField = (real4)(state[5], state[6], state[7], 0.f);
	real magneticEnergyDensity = .5f * dot(magneticField, magneticField) / VACCUUM_PERMEABILITY;
	//goes out
	state[STATE_MAGNETIC_FIELD_X] = magneticField.x;
	state[STATE_MAGNETIC_FIELD_Y] = magneticField.y;
	state[STATE_MAGNETIC_FIELD_Z] = magneticField.z;
	state[STATE_ENERGY_TOTAL] = totalEnergyDensity + magneticEnergyDensity;
}

//TODO 
//separate the dx/dt calculation from integrate flux
//incorporate this with the dx/dt calcluation
//and then use that for arbitrary explicit integrators
__kernel void addMHDSource(
	__global real* stateBuffer,
	const __global real* dtBuffer)
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
	real dt = dtBuffer[0];
	
	int index = INDEXV(i);
	
	real divB = .5f * (
		(stateBuffer[STATE_MAGNETIC_FIELD_X + NUM_STATES * (index + stepsize.x)] 
			- stateBuffer[STATE_MAGNETIC_FIELD_X + NUM_STATES * (index - stepsize.x)]) / DX
#if DIM > 1
		+ (stateBuffer[STATE_MAGNETIC_FIELD_Y + NUM_STATES * (index + stepsize.y)] 
			- stateBuffer[STATE_MAGNETIC_FIELD_Y + NUM_STATES * (index - stepsize.y)]) / DY
#endif
#if DIM > 2
		+ (stateBuffer[STATE_MAGNETIC_FIELD_Z + NUM_STATES * (index + stepsize.z)] 
			- stateBuffer[STATE_MAGNETIC_FIELD_Z + NUM_STATES * (index - stepsize.z)]) / DZ
#endif
	);
	
	__global real* state = stateBuffer + NUM_STATES * index;

	real4 velocity = VELOCITY(state);
	real4 magneticField = (real4)(state[STATE_MAGNETIC_FIELD_X], state[STATE_MAGNETIC_FIELD_Y], state[STATE_MAGNETIC_FIELD_Z], 0.f);
	
	real source[NUM_STATES];
	source[STATE_DENSITY] = 0.f;
	source[STATE_MOMENTUM_X] = magneticField.x;
	source[STATE_MOMENTUM_Y] = magneticField.y;
	source[STATE_MOMENTUM_Z] = magneticField.z;
	source[STATE_MAGNETIC_FIELD_X] = velocity.x;
	source[STATE_MAGNETIC_FIELD_Y] = velocity.y;
	source[STATE_MAGNETIC_FIELD_Z] = velocity.z;
	source[STATE_ENERGY_TOTAL] = dot(magneticField, velocity);

	for (int i = 0; i < NUM_STATES; ++i) {
		stateBuffer[i] -= dt * divB * source[i];
	}
}